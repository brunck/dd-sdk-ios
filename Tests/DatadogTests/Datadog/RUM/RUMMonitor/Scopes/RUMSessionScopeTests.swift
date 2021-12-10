/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMSessionScopeTests: XCTestCase {
    private let parent: RUMApplicationScope = .mockWith(rumApplicationID: "rum-123")

    func testDefaultContext() {
        let scope: RUMSessionScope = .mockWith(parent: parent, samplingRate: 100)

        XCTAssertEqual(scope.context.rumApplicationID, "rum-123")
        XCTAssertNotEqual(scope.context.sessionID, .nullUUID)
        XCTAssertNil(scope.context.activeViewID)
        XCTAssertNil(scope.context.activeViewPath)
        XCTAssertNil(scope.context.activeUserActionID)
    }

    func testContextWhenSessionIsSampled() {
        let scope: RUMSessionScope = .mockWith(parent: parent, samplingRate: 0)

        XCTAssertEqual(scope.context.rumApplicationID, "rum-123")
        XCTAssertEqual(scope.context.sessionID, .nullUUID)
        XCTAssertNil(scope.context.activeViewID)
        XCTAssertNil(scope.context.activeViewPath)
        XCTAssertNil(scope.context.activeUserActionID)
    }

    func testWhenSessionExceedsMaxDuration_itGetsClosed() {
        var currentTime = Date()
        let scope: RUMSessionScope = .mockWith(parent: parent, samplingRate: 50, startTime: currentTime)

        XCTAssertTrue(scope.process(command: RUMCommandMock(time: currentTime)))

        // Push time forward by the max session duration:
        currentTime.addTimeInterval(RUMSessionScope.Constants.sessionMaxDuration)

        XCTAssertFalse(scope.process(command: RUMCommandMock(time: currentTime)))
    }

    func testWhenSessionIsInactiveForCertainDuration_itGetsClosed() {
        var currentTime = Date()
        let scope: RUMSessionScope = .mockWith(parent: parent, samplingRate: 50, startTime: currentTime)

        XCTAssertTrue(scope.process(command: RUMCommandMock(time: currentTime)))

        // Push time forward by less than the session timeout duration:
        currentTime.addTimeInterval(0.5 * RUMSessionScope.Constants.sessionTimeoutDuration)

        XCTAssertTrue(scope.process(command: RUMCommandMock(time: currentTime)))

        // Push time forward by the session timeout duration:
        currentTime.addTimeInterval(RUMSessionScope.Constants.sessionTimeoutDuration)

        XCTAssertFalse(scope.process(command: RUMCommandMock(time: currentTime)))
    }

    func testItManagesViewScopeLifecycle() {
        let scope: RUMSessionScope = .mockWith(parent: parent, samplingRate: 100, startTime: Date())
        XCTAssertEqual(scope.viewScopes.count, 0)
        _ = scope.process(command: RUMStartViewCommand.mockWith(identity: mockView))
        XCTAssertEqual(scope.viewScopes.count, 1)
        _ = scope.process(command: RUMStopViewCommand.mockWith(identity: mockView))
        XCTAssertEqual(scope.viewScopes.count, 0)

        _ = scope.process(command: RUMStartViewCommand.mockWith(identity: mockView))
        XCTAssertEqual(scope.viewScopes.count, 1)
        _ = scope.process(command: RUMStopViewCommand.mockWith(identity: mockView))
        XCTAssertEqual(scope.viewScopes.count, 0)
    }

    // MARK: - Background Events Tracking

    func testGivenNoViewScopeAndBackgroundEventsTrackingEnabled_whenCommandCanStartBackgroundView_itCreatesBackgroundScope() {
        // Given
        let currentTime = Date()
        let scope: RUMSessionScope = .mockWith(
            isInitialSession: .mockRandom(), // no matter if its initial session or not
            parent: parent,
            samplingRate: 100,
            startTime: currentTime,
            backgroundEventTrackingEnabled: true
        )
        XCTAssertTrue(scope.viewScopes.isEmpty)

        // When
        let command = RUMCommandMock(time: currentTime, canStartBackgroundView: true, canStartApplicationLaunchView: false)
        XCTAssertTrue(scope.process(command: command))

        // Then
        XCTAssertEqual(scope.viewScopes.count, 1, "It should start background view scope")
        XCTAssertEqual(scope.viewScopes[0].viewStartTime, currentTime)
        XCTAssertEqual(scope.viewScopes[0].viewName, RUMSessionScope.Constants.backgroundViewName)
        XCTAssertEqual(scope.viewScopes[0].viewPath, RUMSessionScope.Constants.backgroundViewURL)
    }

    func testGivenNoActiveViewScopeAndBackgroundEventsTrackingEnabled_whenCommandCanStartBackgroundView_itCreatesBackgroundScope() {
        // Given
        let currentTime = Date()
        let scope: RUMSessionScope = .mockWith(
            isInitialSession: .mockRandom(), // no matter if its initial session or not
            parent: parent,
            samplingRate: 100,
            startTime: currentTime,
            backgroundEventTrackingEnabled: true
        )
        _ = scope.process(command: RUMStartViewCommand.mockWith(time: currentTime, identity: "view"))
        _ = scope.process(command: RUMStartResourceCommand.mockAny())
        _ = scope.process(command: RUMStopViewCommand.mockWith(time: currentTime.addingTimeInterval(1), identity: "view"))

        XCTAssertEqual(scope.viewScopes.count, 1, "It has one view scope...")
        XCTAssertFalse(scope.viewScopes[0].isActiveView, "... but the view is not active")

        // When
        let command = RUMCommandMock(time: currentTime.addingTimeInterval(2), canStartBackgroundView: true, canStartApplicationLaunchView: false)
        XCTAssertTrue(scope.process(command: command))

        // Then
        XCTAssertEqual(scope.viewScopes.count, 2, "It should start background view scope")
        XCTAssertEqual(scope.viewScopes[1].viewStartTime, currentTime.addingTimeInterval(2))
        XCTAssertEqual(scope.viewScopes[1].viewName, RUMSessionScope.Constants.backgroundViewName)
        XCTAssertEqual(scope.viewScopes[1].viewPath, RUMSessionScope.Constants.backgroundViewURL)
    }

    func testGivenNoViewScopeAndBackgroundEventsTrackingEnabled_whenCommandCanNotStartBackgroundView_itDoesNotCreateBackgroundScope() {
        // Given
        let currentTime = Date()
        let scope: RUMSessionScope = .mockWith(
            isInitialSession: .mockRandom(), // no matter if its initial session or not
            parent: parent,
            samplingRate: 100,
            startTime: currentTime,
            backgroundEventTrackingEnabled: true
        )
        XCTAssertTrue(scope.viewScopes.isEmpty)

        // When
        let command = RUMCommandMock(time: currentTime, canStartBackgroundView: false, canStartApplicationLaunchView: false)
        XCTAssertTrue(scope.process(command: command))

        // Then
        XCTAssertTrue(scope.viewScopes.isEmpty, "It should not start any view scope")
    }

    func testGivenNoViewScopeAndBackgroundEventsTrackingDisabled_whenReceivingAnyCommand_itNeverCreatesBackgroundScope() {
        // Given
        let currentTime = Date()
        let scope: RUMSessionScope = .mockWith(
            isInitialSession: .mockRandom(), // no matter if its initial session or not
            parent: parent,
            samplingRate: 100,
            startTime: currentTime,
            backgroundEventTrackingEnabled: false
        )
        XCTAssertTrue(scope.viewScopes.isEmpty)

        // When
        let command = RUMCommandMock(time: currentTime, canStartBackgroundView: .mockRandom(), canStartApplicationLaunchView: false)
        XCTAssertTrue(scope.process(command: command))

        // Then
        XCTAssertTrue(scope.viewScopes.isEmpty, "It should not start any view scope")
    }

    // MARK: - Application Launch Events Tracking

    func testGivenInitialSessionWithNoViewTrackedBefore_whenCommandCanStartApplicationLaunchView_itCreatesAppLaunchScope() {
        // Given
        let currentTime = Date()
        let scope: RUMSessionScope = .mockWith(
            isInitialSession: true,
            parent: parent,
            samplingRate: 100,
            startTime: currentTime,
            backgroundEventTrackingEnabled: .mockRandom() // no matter of BET state
        )
        XCTAssertTrue(scope.viewScopes.isEmpty)

        // When
        let command = RUMCommandMock(time: currentTime, canStartBackgroundView: false, canStartApplicationLaunchView: true)
        XCTAssertTrue(scope.process(command: command))

        // Then
        XCTAssertEqual(scope.viewScopes.count, 1, "It should start application launch view scope")
        XCTAssertEqual(scope.viewScopes[0].viewStartTime, currentTime)
        XCTAssertEqual(scope.viewScopes[0].viewName, RUMSessionScope.Constants.applicationLaunchViewName)
        XCTAssertEqual(scope.viewScopes[0].viewPath, RUMSessionScope.Constants.applicationLaunchViewURL)
    }

    func testGivenNotInitialSessionWithNoViewTrackedBefore_whenCommandCanStartApplicationLaunchView_itDoesNotCreateAppLaunchScope() {
        // Given
        let currentTime = Date()
        let scope: RUMSessionScope = .mockWith(
            isInitialSession: false,
            parent: parent,
            samplingRate: 100,
            startTime: currentTime,
            backgroundEventTrackingEnabled: .mockRandom() // no matter of BET state
        )
        XCTAssertTrue(scope.viewScopes.isEmpty)

        // When
        let command = RUMCommandMock(time: currentTime, canStartBackgroundView: false, canStartApplicationLaunchView: true)
        XCTAssertTrue(scope.process(command: command))

        // Then
        XCTAssertTrue(scope.viewScopes.isEmpty, "It should not start any view scope")
    }

    func testGivenAnySessionWithSomeViewsTrackedBefore_whenCommandCanStartApplicationLaunchView_itDoesNotCreateAppLaunchScope() {
        // Given
        let currentTime = Date()
        let scope: RUMSessionScope = .mockWith(
            isInitialSession: .mockRandom(), // any session, no matter if initial or not
            parent: parent,
            samplingRate: 100,
            startTime: currentTime,
            backgroundEventTrackingEnabled: .mockRandom() // no matter of BET state
        )
        _ = scope.process(command: RUMStartViewCommand.mockWith(time: currentTime, identity: "view"))
        _ = scope.process(command: RUMStopViewCommand.mockWith(time: currentTime.addingTimeInterval(1), identity: "view"))
        XCTAssertTrue(scope.viewScopes.isEmpty)

        // When
        let command = RUMCommandMock(time: currentTime.addingTimeInterval(2), canStartBackgroundView: false, canStartApplicationLaunchView: true)
        XCTAssertTrue(scope.process(command: command))

        // Then
        XCTAssertTrue(scope.viewScopes.isEmpty, "It should not start any view scope")
    }

    // MARK: - Background Events x Application Launch Events Tracking

    func testGivenAppInForegroundAndBETEnabledAndInitialSession_whenCommandCanStartBothApplicationLaunchAndBackgroundViews_itCreatesAppLaunchScope() {
        // Given
        let currentTime = Date()
        let scope: RUMSessionScope = .mockWith(
            isInitialSession: true, // initial session
            parent: parent,
            samplingRate: 100,
            startTime: currentTime,
            backgroundEventTrackingEnabled: true // BET enabled
        )
        XCTAssertTrue(scope.viewScopes.isEmpty, "No views tracked before")

        // When
        let command = RUMCommandMock(time: currentTime, canStartBackgroundView: true, canStartApplicationLaunchView: true)
        XCTAssertTrue(scope.process(command: command))

        // Then
        XCTAssertEqual(scope.viewScopes.count, 1, "It should start application launch view scope")
        XCTAssertEqual(scope.viewScopes[0].viewStartTime, currentTime)
        XCTAssertEqual(scope.viewScopes[0].viewName, RUMSessionScope.Constants.applicationLaunchViewName)
        XCTAssertEqual(scope.viewScopes[0].viewPath, RUMSessionScope.Constants.applicationLaunchViewURL)
    }

    func testGivenAppInBackgroundAndBETEnabledAndInitialSession_whenCommandCanStartBothApplicationLaunchAndBackgroundViews_itCreatesBackgroundScope() {
        // Given
        let currentTime = Date()
        let scope: RUMSessionScope = .mockWith(
            isInitialSession: true, // initial session
            parent: parent,
            samplingRate: 100,
            startTime: currentTime,
            backgroundEventTrackingEnabled: true // BET enabled
        )
        XCTAssertTrue(scope.viewScopes.isEmpty, "No views tracked before")

        // When
        let command = RUMCommandMock(time: currentTime, canStartBackgroundView: true, canStartApplicationLaunchView: true)
        XCTAssertTrue(scope.process(command: command))

        // Then
        XCTAssertEqual(scope.viewScopes.count, 1, "It should start background view scope")
        XCTAssertEqual(scope.viewScopes[0].viewStartTime, currentTime)
        XCTAssertEqual(scope.viewScopes[0].viewName, RUMSessionScope.Constants.backgroundViewName)
        XCTAssertEqual(scope.viewScopes[0].viewPath, RUMSessionScope.Constants.backgroundViewURL)
    }

    func testGivenAppInBackgroundAndBETDisabledAndInitialSession_whenCommandCanStartBothApplicationLaunchAndBackgroundViews_itDoesNotCreateAnyScope() {
        // Given
        let currentTime = Date()
        let scope: RUMSessionScope = .mockWith(
            isInitialSession: true, // initial session
            parent: parent,
            samplingRate: 100,
            startTime: currentTime,
            backgroundEventTrackingEnabled: false // BET disabled
        )
        XCTAssertTrue(scope.viewScopes.isEmpty, "No views tracked before")

        // When
        let command = RUMCommandMock(time: currentTime, canStartBackgroundView: true, canStartApplicationLaunchView: true)
        XCTAssertTrue(scope.process(command: command))

        // Then
        XCTAssertTrue(scope.viewScopes.isEmpty, "It should not start any view scope (event should be ignored)")
    }

    // MARK: - Sampling

    func testWhenSessionIsSampled_itDoesNotCreateViewScopes() {
        let scope: RUMSessionScope = .mockWith(parent: parent, samplingRate: 0, startTime: Date())
        XCTAssertEqual(scope.viewScopes.count, 0)
        XCTAssertTrue(
            scope.process(command: RUMStartViewCommand.mockWith(identity: mockView)),
            "Sampled session should be kept until it expires or reaches the timeout."
        )
        XCTAssertEqual(scope.viewScopes.count, 0)
    }

    // MARK: - Usage

    func testWhenNoActiveViewScopes_itLogsWarning() {
        // Given
        let scope: RUMSessionScope = .mockWith(parent: parent, samplingRate: 100, startTime: Date())
        XCTAssertEqual(scope.viewScopes.count, 0)

        let previousUserLogger = userLogger
        defer { userLogger = previousUserLogger }

        let logOutput = LogOutputMock()
        userLogger = .mockWith(logOutput: logOutput)

        let command = RUMCommandMock(time: Date(), canStartBackgroundView: false)

        // When
        _ = scope.process(command: command)

        // Then
        XCTAssertEqual(scope.viewScopes.count, 0)
        XCTAssertEqual(
            logOutput.recordedLog?.message,
            """
            \(String(describing: command)) was detected, but no view is active. To track views automatically, try calling the
            DatadogConfiguration.Builder.trackUIKitRUMViews() method. You can also track views manually using
            the RumMonitor.startView() and RumMonitor.stopView() methods.
            """
        )
    }
}
