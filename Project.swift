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
                    // 캘린더 동기화 토글 ON 시에만 사용. iOS 17+ 신규 키.
                    "NSCalendarsFullAccessUsageDescription": "가족 모임을 iOS 캘린더에도 등록하려면 권한이 필요합니다. 모임 시간·장소가 본인 캘린더에 자동으로 추가되고, 시간이 바뀌면 같이 갱신돼요.",
                    // iOS 17 미만 호환용 (Tuist deployment target 18.0이라 사실상 사용 안 되지만 안전망)
                    "NSCalendarsUsageDescription": "가족 모임을 iOS 캘린더에 등록·갱신하는 데 사용합니다.",
                    // 장소 검색의 "내 주변" 필터에서만 1회성으로 사용. 위치 추적·저장 없음.
                    "NSLocationWhenInUseUsageDescription": "내 주변 맛집·장소를 찾아드리기 위해 현재 위치가 필요합니다. 위치는 검색에만 쓰이고 저장되지 않아요.",
                    // HTTPS/TLS 등 표준(면제 대상) 암호화만 사용 → 수출 규정 준수
                    // 정보 누락 프롬프트 제거(App Store Connect 매 업로드마다 묻는 것 방지).
                    "ITSAppUsesNonExemptEncryption": false,
                    "UISupportedInterfaceOrientations": [
                        "UIInterfaceOrientationPortrait",
                    ],
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
