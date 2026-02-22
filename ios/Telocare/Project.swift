import ProjectDescription

let strictBaseSettings: SettingsDictionary = [
    "GCC_TREAT_WARNINGS_AS_ERRORS": "YES",
    "SWIFT_TREAT_WARNINGS_AS_ERRORS": "YES",
    "CODE_SIGN_STYLE": "Automatic",
    "DEVELOPMENT_TEAM": "3CNMWUW4KY",
]

let strictSettings = Settings.settings(
    configurations: [
        .debug(
            name: "Debug",
            settings: strictBaseSettings,
            xcconfig: .relativeToRoot("Configs/Debug.xcconfig")
        ),
        .release(
            name: "Release",
            settings: strictBaseSettings,
            xcconfig: .relativeToRoot("Configs/Release.xcconfig")
        ),
    ],
    defaultSettings: .recommended
)

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
                    "SUPABASE_URL": "$(SUPABASE_URL)",
                    "SUPABASE_PUBLISHABLE_KEY": "$(SUPABASE_PUBLISHABLE_KEY)",
                    "TELOCARE_SKIN": "$(TELOCARE_SKIN)",
                    "NSHealthShareUsageDescription": "Telocare reads selected Apple Health data to auto-update your intervention dose progress.",
                    "NSHealthUpdateUsageDescription": "Telocare requests Health access setup for read-only intervention syncing.",
                ]
            ),
            buildableFolders: [
                "Telocare/Sources",
                "Telocare/Resources",
            ],
            entitlements: .file(path: .relativeToRoot("Telocare/Telocare.entitlements")),
            dependencies: [
                .external(name: "Supabase")
            ],
            settings: strictSettings
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
            dependencies: [.target(name: "Telocare")],
            settings: strictSettings
        ),
        .target(
            name: "TelocareUITests",
            destinations: .iOS,
            product: .uiTests,
            bundleId: "dev.tuist.TelocareUITests",
            infoPlist: .default,
            buildableFolders: [
                "Telocare/UITests"
            ],
            dependencies: [.target(name: "Telocare")],
            settings: strictSettings
        ),
    ]
)
