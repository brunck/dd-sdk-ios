// swift-tools-version:5.2

import PackageDescription

let package = Package(
    name: "Datadog",
    platforms: [
        .iOS(.v11),
        .tvOS(.v11)
    ],
    products: [
        .library(
            name: "Datadog",
            targets: ["Datadog"]
        ),
        .library(
            name: "DatadogObjc",
            targets: ["DatadogObjc"]
        ),
        .library(
            name: "DatadogDynamic",
            type: .dynamic,
            targets: ["Datadog"]
        ),
        .library(
            name: "DatadogDynamicObjc",
            type: .dynamic,
            targets: ["DatadogObjc"]
        ),
        .library( // TODO: Remove in the next major version.
            name: "DatadogStatic",
            type: .static,
            targets: ["Datadog"]
        ),
        .library( // TODO: Remove in the next major version.
            name: "DatadogStaticObjc",
            type: .static,
            targets: ["DatadogObjc"]
        ),
        .library(
            name: "DatadogCrashReporting",
            targets: ["DatadogCrashReporting"]
        ),
    ],
    dependencies: [
        .package(name: "PLCrashReporter", url: "https://github.com/microsoft/plcrashreporter.git", from: "1.10.0"),
    ],
    targets: [
        .target(
            name: "Datadog",
            dependencies: [
                "_Datadog_Private",
            ],
            swiftSettings: [.define("SPM_BUILD")]
        ),
        .target(
            name: "DatadogObjc",
            dependencies: [
                "Datadog",
            ]
        ),
        .target(
            name: "_Datadog_Private"
        ),
        .target(
            name: "DatadogCrashReporting",
            dependencies: [
                "Datadog",
                .product(name: "CrashReporter", package: "PLCrashReporter"),
            ]
        )
    ]
)
