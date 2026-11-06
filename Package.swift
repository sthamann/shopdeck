// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Shopdeck", platforms: [.macOS(.v14)],
    products: [.executable(name: "Shopdeck", targets: ["Shopdeck"]), .executable(name: "shopdeck-mcp", targets: ["ShopdeckMCP"]), .executable(name: "shopdeck-keychain", targets: ["ShopdeckKeychain"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"), .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", exact: "2.4.1")],
    targets: [
        .target(name: "ShopdeckCore"),
        .executableTarget(name: "ShopdeckKeychain"),
        .executableTarget(name: "Shopdeck", dependencies: ["ShopdeckCore", .product(name:"Sparkle", package:"Sparkle"), .product(name:"MarkdownUI",package:"swift-markdown-ui")], resources: [.process("Resources")], linkerSettings:[.unsafeFlags(["-Xlinker","-rpath","-Xlinker","@executable_path/../Frameworks"])]),
        .executableTarget(name: "ShopdeckMCP", dependencies: ["ShopdeckCore"]),
        .testTarget(name: "ShopdeckCoreTests", dependencies: ["ShopdeckCore"])
    ], swiftLanguageModes: [.v5]
)
