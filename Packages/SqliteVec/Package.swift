// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SqliteVec",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SqliteVec", targets: ["SqliteVec"]),
    ],
    targets: [
        .target(
            name: "CSqliteVec",
            cSettings: [
                .define("SQLITE_CORE"),
                .define("SQLITE_VEC_STATIC"),
            ]
        ),
        .target(
            name: "SqliteVec",
            dependencies: ["CSqliteVec"]
        ),
    ]
)
