/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal enum HTTPResponseStatusCode: Int {
    /// The request has been accepted for processing.
    case accepted = 202
    /// The server cannot or will not process the request (client error).
    case badRequest = 400
    /// The request lacks valid authentication credentials.
    case unauthorized = 401
    /// The server understood the request but refuses to authorize it.
    case forbidden = 403
    /// The server would like to shut down the connection.
    case requestTimeout = 408
    /// The request entity is larger than limits defined by server.
    case payloadTooLarge = 413
    /// The client has sent too many requests in a given amount of time.
    case tooManyRequests = 429
    /// The server encountered an unexpected condition.
    case internalServerError = 500
    /// The server received an invalid response from another server.
    case badGateway = 502
    /// The server is not ready to handle the request probably because it is overloaded.
    case serviceUnavailable = 503
    /// The server (a gateway or proxy) did not receive a timely response from an upstream server.
    case gatewayTimeout = 504
    /// The server is unable to complete a request due to a lack of available storage space.
    case insufficientStorage = 507
    /// An unexpected status code.
    case unexpected = -999

    /// If it makes sense to retry the upload finished with this status code, e.g. if data upload failed due to `503` HTTP error, we should retry it later.
    var needsRetry: Bool {
        switch self {
        case .accepted, .badRequest, .unauthorized, .forbidden, .payloadTooLarge:
            // No retry - it's either success or a client error which won't be fixed in next upload.
            return false
        case .requestTimeout, .tooManyRequests, .internalServerError, .serviceUnavailable:
            // Retry - it's a temporary server or connection issue that might disappear on next attempt.
            return true
        case .badGateway, .gatewayTimeout, .insufficientStorage:
            // RUM-2745: SDK is expected to not lose data upon receiving these status codes
            return true
        case .unexpected:
            // This shouldn't happen, but if receiving an unexpected status code we do not retry.
            // This is safer than retrying as we don't know if the issue is coming from the client or server.
            return false
        }
    }
}

/// The status of a single upload attempt.
internal struct DataUploadStatus {
    /// If upload needs to be retried (`true`) because its associated data was not delivered but it may succeed
    /// in the next attempt (i.e. it failed due to device leaving signal range or a temporary server unavailability occurred).
    /// If set to `false` then data associated with the upload should be deleted as it does not need any more upload
    /// attempts (i.e. the upload succeeded or failed due to unrecoverable client error).
    let needsRetry: Bool

    // MARK: - Debug Info

    /// The actual HTTP status code received in response (`nil` if transport error).
    let responseCode: Int?

    /// Upload status description printed to the console if SDK `.debug` verbosity is enabled.
    let userDebugDescription: String

    let error: DataUploadError?

    let attempt: UInt
}

extension DataUploadStatus {
    // MARK: - Initialization

    init(httpResponse: HTTPURLResponse, ddRequestID: String?, attempt: UInt) {
        let statusCode = HTTPResponseStatusCode(rawValue: httpResponse.statusCode) ?? .unexpected

        self.init(
            needsRetry: statusCode.needsRetry,
            responseCode: httpResponse.statusCode,
            userDebugDescription: "[response code: \(httpResponse.statusCode) (\(statusCode)), request ID: \(ddRequestID ?? "(???)")",
            error: DataUploadError(status: httpResponse.statusCode),
            attempt: attempt
        )
    }

    init(networkError: Error, attempt: UInt) {
        self.init(
            needsRetry: true, // retry this upload as it failed due to network transport isse
            responseCode: nil,
            userDebugDescription: "[error: \(DDError(error: networkError).message)]", // e.g. "[error: A data connection is not currently allowed]"
            error: DataUploadError(networkError: networkError),
            attempt: attempt
        )
    }
}

// MARK: - Data Upload Errors

internal enum DataUploadError: Error, Equatable {
    case httpError(statusCode: HTTPResponseStatusCode)
    case networkError(error: NSError)
}

extension DataUploadError {
    init?(status code: Int) {
        guard let statusCode = HTTPResponseStatusCode(rawValue: code) else {
            return nil
        }

        switch statusCode {
        case .accepted:
            return nil
        default:
            self = .httpError(statusCode: statusCode)
        }
    }

    init?(networkError: Error) {
        let nsError = networkError as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return nil
        }

        self = .networkError(error: nsError)
    }
}
