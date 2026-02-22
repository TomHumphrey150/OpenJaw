import ProjectDescription

let strictBaseSettings: SettingsDictionary = [
    "GCC_TREAT_WARNINGS_AS_ERRORS": "YES",
    "SWIFT_TREAT_WARNINGS_AS_ERRORS": "YES",
    "CODE_SIGN_STYLE": "Automatic",
    "DEVELOPMENT_TEAM": "3CNMWUW4KY",
]

let appBaseSettings = strictBaseSettings.merging(
    [
        "SWIFT_OBJC_BRIDGING_HEADER": "Telocare/Sources/Health/MuseSDK-Bridging-Header.h",
        "HEADER_SEARCH_PATHS[sdk=iphoneos*]": "$(inherited) $(SRCROOT)/Vendor/MuseSDK/Muse.framework/Headers",
        "FRAMEWORK_SEARCH_PATHS[sdk=iphoneos*]": "$(inherited) $(SRCROOT)/Vendor/MuseSDK",
        "OTHER_LDFLAGS[sdk=iphoneos*]": "$(inherited) -framework Muse -framework CoreBluetooth -framework ExternalAccessory",
    ],
    uniquingKeysWith: { _, new in new }
)

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

let appSettings = Settings.settings(
    configurations: [
        .debug(
            name: "Debug",
            settings: appBaseSettings,
            xcconfig: .relativeToRoot("Configs/Debug.xcconfig")
        ),
        .release(
            name: "Release",
            settings: appBaseSettings,
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
                    "MUSE_LICENSE_BASE64": "$(MUSE_LICENSE_BASE64)",
                    "NSHealthShareUsageDescription": "Telocare reads selected Apple Health data to auto-update your intervention dose progress.",
                    "NSHealthUpdateUsageDescription": "Telocare requests Health access setup for read-only intervention syncing.",
                    "NSBluetoothAlwaysUsageDescription": "Telocare uses Bluetooth to discover and connect to your Muse headband for overnight wellness sessions.",
                    "NSBluetoothPeripheralUsageDescription": "Telocare uses Bluetooth to communicate with your Muse headband during recording.",
                ]
            ),
            buildableFolders: [
                "Telocare/Sources",
                "Telocare/Resources",
            ],
            entitlements: .file(path: .relativeToRoot("Telocare/Telocare.entitlements")),
            dependencies: [
                .external(name: "CocoaLumberjackSwift"),
                .external(name: "Supabase")
            ],
            settings: appSettings
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
