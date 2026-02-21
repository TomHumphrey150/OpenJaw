import ProjectDescription

let project = Project(
    name: "Telocare",
    targets: [
        .target(
            name: "Telocare",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.Telocare",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                ]
            ),
            buildableFolders: [
                "Telocare/Sources",
                "Telocare/Resources",
            ],
            dependencies: []
        ),
        .target(
            name: "TelocareTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.TelocareTests",
            infoPlist: .default,
            buildableFolders: [
                "Telocare/Tests"
            ],
            dependencies: [.target(name: "Telocare")]
        ),
    ]
)
