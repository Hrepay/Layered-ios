import ProjectDescription

let project = Project(
    name: "Layered",
    settings: .settings(
        base: [
            "DEVELOPMENT_TEAM": "BBVZV8T99P",
            "CODE_SIGN_STYLE": "Automatic",
            "OTHER_LDFLAGS": "-ObjC",
            "TARGETED_DEVICE_FAMILY": "1", // iPhone only
        ]
    ),
    targets: [
        .target(
            name: "Layered",
            destinations: [.iPhone],
            product: .app,
            bundleId: "io.github.hrepay.layered",
            deploymentTargets: .iOS("18.0"),
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                    "NSPhotoLibraryAddUsageDescription": "모임 기록에 첨부된 사진을 사진첩에 저장하려면 접근 권한이 필요합니다. 가족이 함께한 순간을 원본 그대로 기기에 보관할 수 있어요.",
                    "UISupportedInterfaceOrientations": [
                        "UIInterfaceOrientationPortrait",
                    ],
                    "ITSAppUsesNonExemptEncryption": false,
                ]
            ),
            sources: [
                "Layered/Sources/**",
            ],
            resources: [
                "Layered/Resources/**",
            ],
            entitlements: "Layered/Layered.entitlements",
            dependencies: [
                .external(name: "FirebaseAuth"),
                .external(name: "FirebaseFirestore"),
                .external(name: "FirebaseStorage"),
                .external(name: "FirebaseMessaging"),
            ]
        ),
        .target(
            name: "LayeredTests",
            destinations: [.iPhone],
            product: .unitTests,
            bundleId: "io.github.hrepay.layered.Tests",
            infoPlist: .default,
            buildableFolders: [
                "Layered/Tests"
            ],
            dependencies: [.target(name: "Layered")]
        ),
    ]
)
