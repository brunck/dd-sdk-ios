/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

@available(*, deprecated, renamed: "B3HTTPHeadersWriter")
public typealias OTelHTTPHeadersWriter = B3HTTPHeadersWriter

/// The `B3HTTPHeadersWriter` class facilitates the injection of trace propagation headers into network requests
/// targeted at a backend expecting [B3 propagation format](https://github.com/openzipkin/b3-propagation).
///
/// Usage:
///
///     var request = URLRequest(...)
///
///     let writer = B3HTTPHeadersWriter(injectEncoding: .single)
///     let span = Tracer.shared().startRootSpan(operationName: "network request")
///     Tracer.shared().inject(spanContext: span.context, writer: writer)
///
///     writer.traceHeaderFields.forEach { (field, value) in
///         request.setValue(value, forHTTPHeaderField: field)
///     }
///
///     // call span.finish() when the request completes
///
public class B3HTTPHeadersWriter: TracePropagationHeadersWriter {
    /// Enumerates B3 header encoding options.
    ///
    /// There are two encodings of B3 propagation:
    /// [Single Header](https://github.com/openzipkin/b3-propagation#single-header)
    /// and [Multiple Header](https://github.com/openzipkin/b3-propagation#multiple-headers).
    ///
    /// Multiple header encoding employs an `X-B3-` prefixed header per item in the trace context.
    /// Single header delimits the context into a single entry named `B3`.
    /// The single-header variant takes precedence over the multiple header one when extracting fields.
    public enum InjectEncoding {
        /// Encoding that employs `X-B3-*` prefixed headers per item in the trace context.
        ///
        /// See: [Multiple Header](https://github.com/openzipkin/b3-propagation#multiple-headers).
        case multiple
        /// Encoding that uses a single `B3` header to transport the trace context.
        ///
        /// See: [Single Header](https://github.com/openzipkin/b3-propagation#single-header)
        case single
    }

    /// A dictionary containing the required HTTP Headers for propagating trace information.
    ///
    /// Usage:
    ///
    ///     writer.traceHeaderFields.forEach { (field, value) in
    ///         request.setValue(value, forHTTPHeaderField: field)
    ///     }
    ///
    public private(set) var traceHeaderFields: [String: String] = [:]

    private let samplingStrategy: TraceSamplingStrategy

    /// Defines whether the trace context should be injected into all requests or only sampled ones.
    private let traceContextInjection: TraceContextInjection

    /// The telemetry header encoding used by the writer.
    private let injectEncoding: InjectEncoding

    /// Initializes the headers writer.
    ///
    /// - Parameter samplingRate: The sampling rate applied for headers injection.
    /// - Parameter injectEncoding: The B3 header encoding type, with `.single` as the default.
    @available(*, deprecated, message: "This will be removed in future versions of the SDK. Use `init(samplingStrategy: .custom(sampleRate:))` instead.")
    public convenience init(
        samplingRate: Float,
        injectEncoding: InjectEncoding = .single
    ) {
        self.init(sampleRate: samplingRate, injectEncoding: injectEncoding)
    }

    /// Initializes the headers writer.
    ///
    /// - Parameter sampleRate: The sampling rate applied for headers injection, with 20% as the default.
    /// - Parameter injectEncoding: The B3 header encoding type, with `.single` as the default.
    @available(*, deprecated, message: "This will be removed in future versions of the SDK. Use `init(samplingStrategy: .custom(sampleRate:))` instead.")
    public convenience init(
        sampleRate: Float = 20,
        injectEncoding: InjectEncoding = .single
    ) {
        self.init(
            samplingStrategy: .custom(sampleRate: sampleRate),
            injectEncoding: injectEncoding,
            traceContextInjection: .all
        )
    }

    /// Initializes the headers writer.
    ///
    /// - Parameter samplingStrategy: The strategy for sampling trace propagation headers.
    /// - Parameter injectEncoding: The B3 header encoding type, with `.single` as the default.
    /// - Parameter traceContextInjection: The trace context injection strategy, with `.all` as the default.
    public init(
        samplingStrategy: TraceSamplingStrategy,
        injectEncoding: InjectEncoding = .single,
        traceContextInjection: TraceContextInjection = .all
    ) {
        self.samplingStrategy = samplingStrategy
        self.injectEncoding = injectEncoding
        self.traceContextInjection = traceContextInjection
    }

    /// Writes the trace ID, span ID, and optional parent span ID into the trace propagation headers.
    ///
    /// - Parameter traceID: The trace ID.
    /// - Parameter spanID: The span ID.
    /// - Parameter parentSpanID: The parent span ID, if applicable.
    public func write(traceContext: TraceContext) {
        let sampler = samplingStrategy.sampler(for: traceContext)
        let sampled = sampler.sample()

        typealias Constants = B3HTTPHeaders.Constants

        switch (traceContextInjection, sampled) {
        case (.all, _), (.sampled, true):
            switch injectEncoding {
            case .multiple:
                traceHeaderFields = [
                    B3HTTPHeaders.Multiple.sampledField: sampled ? Constants.sampledValue : Constants.unsampledValue
                ]

                if sampled {
                    traceHeaderFields[B3HTTPHeaders.Multiple.traceIDField] = String(traceContext.traceID, representation: .hexadecimal32Chars)
                    traceHeaderFields[B3HTTPHeaders.Multiple.spanIDField] = String(traceContext.spanID, representation: .hexadecimal16Chars)
                    traceHeaderFields[B3HTTPHeaders.Multiple.parentSpanIDField] = traceContext.parentSpanID.map { String($0, representation: .hexadecimal16Chars) }
                }
            case .single:
                if sampled {
                    traceHeaderFields[B3HTTPHeaders.Single.b3Field] = [
                        String(traceContext.traceID, representation: .hexadecimal32Chars),
                        String(traceContext.spanID, representation: .hexadecimal16Chars),
                        sampled ? Constants.sampledValue : Constants.unsampledValue,
                        traceContext.parentSpanID.map { String($0, representation: .hexadecimal16Chars) }
                    ]
                    .compactMap { $0 }
                    .joined(separator: Constants.b3Separator)
                } else {
                    traceHeaderFields[B3HTTPHeaders.Single.b3Field] = Constants.unsampledValue
                }
            }
        case (.sampled, false):
            break
        }
    }
}
