/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import Datadog

@objcMembers
public class DDTrackingConsent: NSObject {
    internal let sdkConsent: TrackingConsent

    internal init(sdkConsent: TrackingConsent) {
        self.sdkConsent = sdkConsent
    }

    // MARK: - Public

    public static func granted() -> DDTrackingConsent { .init(sdkConsent: .granted) }
    public static func notGranted() -> DDTrackingConsent { .init(sdkConsent: .notGranted) }
    public static func pending() -> DDTrackingConsent { .init(sdkConsent: .pending) }
}

@objcMembers
public class DDAppContext: NSObject {
    internal let sdkAppContext: Datadog.AppContext

    // MARK: - Public

    public init(mainBundle: Bundle) {
        self.sdkAppContext = Datadog.AppContext(mainBundle: mainBundle)
    }

    override public init() {
        self.sdkAppContext = Datadog.AppContext()
    }
}

@objcMembers
public class DDDatadog: NSObject {
    // MARK: - Public

    @available(*, deprecated, message: """
    This method is deprecated and uses the `DDTrackingConsent.granted()` value as a default privacy consent.
    This means that the SDK will start recording and sending data immediately after initialisation without waiting for the user's consent to be given.

    Use `DDDatadog.initialize(appContext:trackingConsent:configuration:)` and set consent to `granted()` to preserve previous behaviour.
    """)
    public static func initialize(appContext: DDAppContext, configuration: DDConfiguration) {
        Datadog.initialize(
            appContext: appContext.sdkAppContext,
            configuration: configuration.sdkConfiguration
        )
    }

    public static func initialize(
        appContext: DDAppContext,
        trackingConsent: DDTrackingConsent,
        configuration: DDConfiguration
    ) {
        Datadog.initialize(
            appContext: appContext.sdkAppContext,
            trackingConsent: trackingConsent.sdkConsent,
            configuration: configuration.sdkConfiguration
        )
    }

    public static func setVerbosityLevel(_ verbosityLevel: DDSDKVerbosityLevel) {
        switch verbosityLevel {
        case .debug: Datadog.verbosityLevel = .debug
        case .info: Datadog.verbosityLevel = .info
        case .notice: Datadog.verbosityLevel = .notice
        case .warn: Datadog.verbosityLevel = .warn
        case .error: Datadog.verbosityLevel = .error
        case .critical: Datadog.verbosityLevel = .critical
        case .none: Datadog.verbosityLevel = nil
        }
    }

    public static func verbosityLevel() -> DDSDKVerbosityLevel {
        switch Datadog.verbosityLevel {
        case .debug: return .debug
        case .info: return .info
        case .notice: return .notice
        case .warn: return .warn
        case .error: return .error
        case .critical: return .critical
        case .none: return .none
        }
    }

    // swiftlint:disable identifier_name
    public static func setUserInfo(id: String? = nil, name: String? = nil, email: String? = nil) {
        Datadog.setUserInfo(id: id, name: name, email: email)
    }
    // swiftlint:enable identifier_name

    public static func setTrackingConsent(consent: DDTrackingConsent) {
        Datadog.set(trackingConsent: consent.sdkConsent)
    }
}
