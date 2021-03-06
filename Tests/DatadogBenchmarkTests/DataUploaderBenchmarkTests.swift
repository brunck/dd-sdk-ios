/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import HTTPServerMock
@testable import Datadog

struct ServerConnectionError: Error {
    let description: String
}

@available(iOS 13.0, *)
class DataUploaderBenchmarkTests: XCTestCase {
    private(set) var server: ServerMock! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory.create()
        server = try connectToServer()
    }

    override func tearDownWithError() throws {
        server = nil
        temporaryDirectory.delete()
        try super.tearDownWithError()
    }

    /// NOTE: In RUMM-610 we noticed that due to internal `NSCache` used by the `URLSession`
    /// requests memory was leaked after upload. This benchmark ensures that uploading data with
    /// `DataUploader` leaves no memory footprint (the memory peak after upload is less or equal `0kB`).
    func testUploadingDataToServer_leavesNoMemoryFootprint() throws {
        let dataUploader = DataUploader(
            urlProvider: mockUniqueUploadURLProvider(),
            httpClient: HTTPClient(),
            httpHeaders: HTTPHeaders(headers: [])
        )

        // `measure` runs 5 iterations
        measure(metrics: [XCTMemoryMetric()]) {
            // in each, 10 requests are done:
            (0..<10).forEach { _ in
                let data = Data(repeating: 0x41, count: 10 * 1_024 * 1_024)
                _ = dataUploader.upload(data: data)
            }
            // After all, the baseline asserts `0kB` or less grow in Physical Memory.
            // This makes sure that no request data is leaked (e.g. due to internal caching).
        }
    }

    /// Creates the `UploadURLProvider` giving an unique URL for each upload.
    /// URLs are differentiated by the value of `batch` query item.
    private func mockUniqueUploadURLProvider() -> UploadURLProvider {
        struct BatchTimeProvider: DateProvider {
            func currentDate() -> Date {
                Date(timeIntervalSince1970: .random(in: 0..<1_000_000))
            }
        }
        return UploadURLProvider(
            urlWithClientToken: server.obtainUniqueRecordingSession().recordingURL,
            queryItemProviders: [.batchTime(using: BatchTimeProvider())]
        )
    }

    // MARK: - `HTTPServerMock` connection

    func connectToServer() throws -> ServerMock {
        let testsBundle = Bundle(for: DataUploaderBenchmarkTests.self)
        guard let serverAddress = testsBundle.object(forInfoDictionaryKey: "MockServerAddress") as? String else {
            throw ServerConnectionError(description: "Cannot obtain `MockServerAddress` from `Info.plist`")
        }

        guard let serverURL = URL(string: "http://\(serverAddress)") else {
            throw ServerConnectionError(description: "`MockServerAddress` obtained from `Info.plist` is invalid.")
        }

        let serverProcessRunner = ServerProcessRunner(serverURL: serverURL)
        guard let serverProcess = serverProcessRunner.waitUntilServerIsReachable() else {
            throw ServerConnectionError(description: "Cannot connect to server. Is server running properly on \(serverURL.absoluteString)?")
        }

        print("🌍 Connected to mock server on \(serverURL.absoluteString)")

        let connectedServer = ServerMock(serverProcess: serverProcess)
        return connectedServer
    }
}
