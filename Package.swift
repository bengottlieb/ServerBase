// swift-tools-version: 6.4

import PackageDescription

// The Swift half of ServerBase: the client side of the crash reports and support chat the server half (`package.json`,
// `server/`) receives. Nothing here names an app, a server or a bundle id; each app passes those in.
let package = Package(
	name: "ServerBase",
	platforms: [
		.iOS(.v18),
		.macOS(.v15),
	],
	products: [
		.library(name: "CrashReporting", targets: ["CrashReporting"]),
		// The crash-reporter extension links only this: it must stay small (6 MB) and extension-safe.
		.library(name: "CrashReporterEngine", targets: ["CrashReporterEngine"]),
		.library(name: "SupportChat", targets: ["SupportChat"]),
	],
	dependencies: [
		.package(url: "https://github.com/ios-tooling/NewsHelicopter", from: "0.1.0"),
		.package(url: "https://github.com/ios-tooling/Chronicle", from: "0.0.34"),
		.package(url: "https://github.com/ios-tooling/FeedbackKit", from: "0.2.2"),
	],
	targets: [
		// Where the app and its extension meet; Foundation only, shared by both products.
		.target(name: "CrashReportCore"),
		.target(
			name: "CrashReporting",
			dependencies: [
				"CrashReportCore",
				.product(name: "NewsHelicopter", package: "NewsHelicopter"),
				.product(name: "Chronicle", package: "Chronicle"),
			]
		),
		// Extension-safe API only. Not enforced with -application-extension: SwiftPM refuses unsafe flags in remote packages.
		.target(
			name: "CrashReporterEngine",
			dependencies: ["CrashReportCore", .product(name: "NewsHelicopterExtension", package: "NewsHelicopter")]
		),
		.target(name: "SupportChat", dependencies: [.product(name: "CustomerFeedbackKit", package: "FeedbackKit")]),
		.testTarget(name: "CrashReportingTests", dependencies: ["CrashReporting"]),
		.testTarget(name: "CrashReporterEngineTests", dependencies: ["CrashReporterEngine"]),
		.testTarget(name: "SupportChatTests", dependencies: ["SupportChat"]),
	]
)
