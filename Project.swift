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
                    // HTTPS/TLS 등 표준(면제 대상) 암호화만 사용 → 수출 규정 준수
                    // 정보 누락 프롬프트 제거(App Store Connect 매 업로드마다 묻는 것 방지).
                    "ITSAppUsesNonExemptEncryption": false,
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
