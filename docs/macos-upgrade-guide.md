# macOS 업그레이드 및 Apple 디자인 지침 대응

작성: 2026-10-12 (Asia/Seoul)

사용자 요구: Apple 지침은 OS와 함께 변할 수 있으므로, 미래 업그레이드 때 최신 자료를 다시 확인하여 앱을 갱신할 수 있게 기록합니다. **이 문서도 고정된 디자인 규격이 아니라 재검토 절차입니다.**

최신 변경: R75–R77에서 모양 탭·세 섹션 색 선택·작업 화면을 건드리지 않는 사전 검사를 추가했습니다. R65–R73의 두 테마·활성 앱 추종·최종 아이콘 및 R61–R64의 3.3줄·임시 프로필 순환·Option 명령은 유지합니다. 아래 과거 시점의 기록은 현재 requirements.md와 함께 읽습니다.

## R75–R77 · 섹션별 색상과 사전 검사

- 설정 탭은 일반/모양/메뉴/등록 항목·프로필 순서다. 작은 설정 창에서 네 탭 제목, 각 색 선택기·복원 버튼·타일 샘플을 확인한다. ColorPicker의 플랫폼 색 공간 변환과 alpha 비지원, 한 섹션 변경 시 다른 색/프로필/메뉴 보존, 재실행, 테마 왕복을 검사한다.
- 세 섹션 기본 타일은 서로 다르며 같은 섹션의 정사각/가로형에는 같은 기본색을 적용한다. 강조는 메뉴 고정·현재 데스크탑 의미를 유지한다. 기본값은 테마에 맞게 달라지고 사용자가 고른 기준 색은 두 테마에 걸쳐 유지한다.
- 기본/극단/중간 명도 색에서 본문·보조 글자·숫자 배지·선택 테두리와 핀 표시를 검사한다. 현재 순수 RGB 대비 검사에는 216개 RGB 표본과 두 테마/명암/강조 조합이 포함되며 본문·보조 텍스트에 4.5 이상을 확인한다. 이를 반투명 합성·누름/hover·접근성 설정까지 포함한 전체 UI의 실측 대비 보장으로 확대하지 않는다.
- Xcode 업데이트 시 `PreviewFixtures.swift`의 Canvas와 `scripts/preview.sh`를 먼저 실행한다. 테스트/렌더링은 별도 샘플 suite를 사용하고 사용자 설정·실행 프로세스·인스턴스 소유자 기록을 변경하지 않아야 한다. 미리보기에서 키 감지/AX 관찰/상태 아이템/권한 요청을 시작하지 않는지 확인한다.
- 화면에 표시하지 않는 NSHostingView 렌더링은 실제 DeckView의 색/기하를 검사한다. 창을 order/makeKey 하지 않으며 데스크탑 이미지를 캡처하지 않는다. ImageRenderer는 AppKit 컨트롤과 스크롤 콘텐츠를 빠뜨릴 수 있어 전체 화면 검사에 사용하지 않는다. 네이티브 ColorPicker/라디오 컨트롤도 화면 밖 PNG에 완전히 나타나지 않을 수 있으므로 Canvas 또는 이후 실제 UI 검증과 구분한다.
- 실제 WindowServer의 Glass 합성, 전역 Option, Space 이동, 드래그/프레임 성능은 가짜 데이터나 이미지로 판정하지 않는다. 사용자의 작업을 방해하는 반복 자동 입력보다 먼저 위 검사를 마치고 필요한 실제 검사의 시점을 조율한다.
- 2026-10-13 확인한 [Xcode 미리보기](https://developer.apple.com/documentation/xcode/adding-previews-to-your-interface-files), [ImageRenderer 범위](https://developer.apple.com/documentation/swiftui/imagerenderer), [AXObserverAddNotification 실패 종류](https://developer.apple.com/documentation/applicationservices/1462089-axobserveraddnotification)를 다음 SDK에서 다시 확인한다. SDK의 AXMenuItemSelected 알림 존재만으로 모든 앱의 메뉴 실행/성공 수집을 보장하지 않는다. 현재 제품은 런처 내부에서 성공한 등록 메뉴만 기록하며 외부 메뉴 자동 관찰은 별도 기능 검토 사항이다.

## R65–R73 · 두 테마·활성 앱 추종·브랜드

- 설정에서 유리·파스텔과 클래식·직각을 왕복하고 재실행 후 선택을 확인한다. 사용자 등록/프로필/순서/단축키는 바뀌면 안 된다. Square 비교 앱을 다시 배포하거나 별도 권한 대상으로 만들지 않는다.
- 유리 테마는 고정 메뉴 노랑/현재 데스크탑 창 파랑, 클래식은 초록/파랑이다. 밝은 강조색 위의 짙은 글자, 어두운 클래식 위의 밝은 글자, 작은 앱 이름/숫자 배지/선택 테두리를 라이트·다크·대비 증가·투명도 줄이기에서 확인한다. 색뿐 아니라 핀·현재 데스크탑 안내도 유지한다.
- 배경색 레이어 0.72, 유리 타일 0.96, 클래식 타일 1.0은 앱 조정값이며 OS 합성 결과의 실측 alpha가 아니다. 전체 뷰 opacity로 글자를 흐리게 만들지 않는다. Glass 배경/상단 버튼과 타일의 역할을 나누고 타일마다 추가 블러를 넣지 않는다.
- 프로필은 등록 항목 제목 옆에 한 번만 둔다. 26pt 선택기와 선반 높이 40pt 부대 영역은 현재 구현값이다. 작은 패널·긴 프로필 이름·35개 이상 항목에서 마지막 행이 가려지는지 확인한다.
- 고정 후 앱 전환·같은 앱의 창 전환·제목 변경·창 닫힘·Space 이동 시 상단 문맥/저장된 메뉴/최근 순서/현재 데스크탑 색을 확인한다. 같은 패널·위치·고정·임시 프로필·폴더 탐색 경로는 유지해야 한다. 일반 Option 호출은 목록을 고정한다.
- Option 유지·숫자 선택/실행 대기·마우스 누름/드래그 중에는 순서 갱신을 미룬다. 해제 후 최신 문맥을 반영하고 클릭 순간 캡처한 앱/창/메뉴가 다른 대상으로 바뀌지 않아야 한다. Tile Launcher 자체 활성화는 외부 앱 문맥을 대체하지 않는다.
- 0.12초 알림 묶음과 동일 스냅샷 발행 억제를 확인한다. 전체 메뉴를 상시 열거하지 않는다. 창 이동 관련 동일 속성 반복 설정을 줄였지만 지연 원인은 확정하지 않았다. 동일 화면·창 수·테마·드래그 경로에서 Instruments로 실제 드래그 구간을 잡아 CPU/합성/프레임 지연을 비교한다. 드래그와 겹치지 않은 sample 기록을 성능 근거로 사용하지 않는다.
- 최종 심벌은 계단형 바탕에서 사각 타일이 빠져나오는 형태다. 앱은 컬러 ICNS, 메뉴 막대는 검정/투명 18pt template를 사용한다. 밝고 어두운 메뉴 막대·선택 상태·Retina/다른 배율에서 두 요소 사이의 간격과 인식성을 확인한다. 18pt는 앱 선택값이며 Apple의 고정 크기 규정이 아니다.
- 2026-10-12 확인한 [App icons HIG](https://developer.apple.com/design/human-interface-guidelines/app-icons), [Icon Composer 제작 지침](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer), [NSImage.isTemplate](https://developer.apple.com/documentation/appkit/nsimage/istemplate)를 새 SDK에서 다시 확인한다. 현재는 전통적 다중 해상도 ICNS이며 계층형 Liquid Glass 아이콘을 구현했다고 설명하지 않는다. Icon Composer로 이행할 때 최신 템플릿·시스템 마스크·외관 변형을 기준으로 자산을 다시 검증한다.
- 원본/프롬프트/선택 기록을 Resources/Brand에 보존한다. 재패키징 후 ICNS 표현과 CFBundleIconFile, 실제 설치 번들의 아이콘/코드 서명을 확인한다. Finder 캐시나 기존 프로세스가 옛 아이콘을 보일 수 있으므로 실행 빌드 ID와 메뉴 심벌도 확인하되 전역 아이콘 캐시를 임의로 초기화하지 않는다.

## R61–R64 · 프로필 제스처와 부분 행

- [scrollingDeltaX](https://developer.apple.com/documentation/appkit/nsevent/scrollingdeltax), [기기 방향 반전](https://developer.apple.com/documentation/appkit/nsevent/isdirectioninvertedfromdevice), [momentumPhase](https://developer.apple.com/documentation/appkit/nsevent/momentumphase)의 당시 문서와 SDK 선언을 다시 확인한다. 2026-10-12 확인 기준 이벤트는 사용자 스크롤 설정에 따라 델타가 반전되므로 물리적 왼쪽/오른쪽 쓸기에 맞춰 보정한다.
- 자연스러운 스크롤 켜기/끄기, 트랙패드/Magic Mouse/가로 휠, 짧은 쓸기/긴 쓸기/되돌림/관성/취소를 실기로 확인한다. 한 제스처 한 단계만 전환하며 세로/대각선 흔들림을 프로필 변경으로 오해하지 않는다. 현재 48pt 문턱과 일반 휠 0.3초 묶음은 조정 가능한 앱 값이다.
- 프로필 0/1/2/여러 개·양끝 순환·재정렬/저장/재실행을 확인한다. 임시 전환은 Focus나 수동 프로필 값을 저장하지 않아야 하며 재호출 시 자동/수동 원래 구성을 따라야 한다. 고정 여부·드래그한 위치·앱 문맥·최근 창 순서·번호는 전환 전후 같아야 한다. 등록 숫자는 새 프로필 항목을 가리키고 이전 실행 대기는 취소한다.
- ⌥A/S와 ⌥D/F, ⌥W와 ⌥,를 실제 키보드에서 고정 전/후·Option 해제/유지·한영 입력기로 검사한다. ⌘W/⌘,·Esc와 설정의 텍스트 입력은 그대로 동작하고 다른 앱의 입력을 전역에서 소비하지 않는다.
- 3.3줄은 세 줄 높이와 세 간격 뒤에 네 번째 타일의 30%가 보인다는 뜻이다. 끝까지 스크롤해 마지막 창을 선택할 수 있어야 한다. 메뉴와 최근 창의 높이/타일 비율을 같이 검사하며 3줄에서 목록을 잘라내지 않는다.
- 실제 AppKit 글꼴·아이콘 높이와 반올림을 포함하여 선반의 마지막 행이 몇 포인트 부족으로 사라지지 않는지 검사한다. 512×420 최소/일반 최대, 등록 0/14/35/200개, 여러 프로필을 넘기는 동안 크기 유지와 작은 화면의 축소를 확인한다. 순수 기하 테스트와 실제 네이티브 캡처를 구분한다.
- R64의 비교 시안은 웹 색/모서리/유리 근사다. 사용자 채택 전에는 앱의 재질·배경 농도를 바꾸지 않는다. 채택 후에도 닫기 위치·기본 명령·Focus 권한 등 macOS 조작 경험은 유지한다.

## 변하지 않아야 할 제품 의도

- Option 호출, 큰 클릭 영역, 타일형 공간 배치.
- 현재 앱 메뉴, 집중 모드별 등록 앱·폴더, 모든 앱의 최근 창. R52의 최근 창 한 목록과 연속 앱에 따른 크기 변화를 유지하며 별도 최근 앱은 표시하지 않음.
- 모든 앱의 창을 개별 항목으로 다루며 최근 창에 더 많은 공간 제공.
- 최근 창은 최소 6개 용량·최대 3.3줄 표시, 크기에 따른 자동 용량 및 수동 최대 개수 지원. 자동 목록에 고정 최대 개수를 새로 도입하지 않음.
- 오버레이는 화면 면적의 약 절반을 목표로 하고 화면 밖으로 나가지 않음. 스크롤 방향·커서 기준 위치의 최종 선택은 최신 요구사항과 `interaction-design.md`의 상태를 확인함.
- R19에 따라 세로 높이감은 유지하고 가로를 좁히며 최소·최대 크기를 적용. 면적 약 50%를 강제하기 위해 높이를 늘리지 않음. 구체적인 수치는 최신 요구사항의 확정 여부를 확인함.
- R20에 따라 오버레이 자체의 종횡비에도 허용 범위를 둠. 32:9·4:3 등 화면 비율을 패널에 그대로 복제하지 않고, 최소/최대 크기 및 화면 경계와 함께 계산함. 구체적인 비율 수치는 미확정.
- macOS의 조작 경험과 네이티브 배경/버튼을 유지하며, 타일 외관은 사용자가 선택한 두 테마를 제공함.
- 창 제어는 왼쪽, 제목/설명은 중앙, 설정은 오른쪽 유리 버튼, 프로필은 등록 선반 제목 옆. OS에서 익힌 닫기·뒤로 가기·메뉴·키보드·포커스 동작을 우선함. R32의 핀 → 닫기 전환은 사용자가 요청한 제품 동작임.

OS 변경에 맞춰 재질·곡률·컨트롤·타이포그래피를 조정하더라도 이 의미를 임의로 바꾸지 않습니다.

## 업그레이드 때 다시 볼 공식 출발점

링크가 이동하거나 문서가 수정되면 Apple Developer 사이트에서 이름으로 찾아 현재 주소를 기록합니다. 블로그·과거 캡처만으로 판단하지 않습니다.

| 영역 | 공식 자료 | 확인할 내용 |
|---|---|---|
| 전체 디자인 | [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/) | macOS 권장 관례, 시각 계층, 입력·접근성 |
| 재질 | [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) | 유리·배경·콘텐츠의 구분, 가독성, 적절한 적용 범위 |
| Liquid Glass 채택 | [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) | 새 SDK의 기본 변화, 표준 컨트롤, 마이그레이션 권장 사항 |
| 곡면과 그룹 | [Get to know the new design system — WWDC25](https://developer.apple.com/videos/play/wwdc2025/356/) | 동심 곡면, 내부 여백, 캡슐·고정·컨테이너 종속 형태. 이후 발표가 있으면 함께 비교 |
| 글래스 원리 | [Meet Liquid Glass — WWDC25](https://developer.apple.com/videos/play/wwdc2025/219/) | 재질의 역할, 계층, 상호작용. 최신 후속 지침 우선 |
| 네이티브 재질 API | [NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview) | 지원 OS, 권장 사용법, 컨테이너·상호작용 및 대체 API |
| SwiftUI 재질 API | [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views) | glassEffect, 모양·상호작용, GlassEffectContainer의 묶음 렌더링 및 결합 범위 |
| 화면의 사용 가능 영역 | [NSScreen.visibleFrame](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe) | 현재 UI 설정에서 표시 가능한 영역. 화면 전환·배율·Dock·메뉴 막대 변화 시 새로 조회 |
| 호출 시 커서 위치 | [NSEvent.mouseLocation](https://developer.apple.com/documentation/appkit/nsevent/mouselocation) | 전역 화면 좌표와 표시 대상 모니터, 다중 모니터 좌표 변환 |
| 창 표시 | [NSWindow.CollectionBehavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct) | 전체 화면, Spaces, Stage Manager 및 패널 동작 |
| 창·도구 모음 관례 | [Windows](https://developer.apple.com/design/human-interface-guidelines/windows), [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars) | 왼쪽 창 제어·탐색, 제목 중심, 네이티브 컨트롤/포커스와 도움말 |
| Dock 설정 읽기 | [CFPreferencesCopyAppValue](https://developer.apple.com/documentation/corefoundation/cfpreferencescopyappvalue(_:_:)) | 읽기 API와 Dock 저장 스키마의 구분, 저장 순서·폴더 경로·기존 설정 보존 |
| 접근성 제어 | [AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement_h) | 메뉴·창 노출, 권한, 시간 제한, 오류 처리 |
| 이벤트 구독 | [AXObserverAddNotification](https://developer.apple.com/documentation/applicationservices/1462089-axobserveraddnotification) | 지원하지 않는 알림, 등록·해제, 이벤트 누락에 대한 보완 |
| 집중 모드 | [App Intents — Focus](https://developer.apple.com/documentation/appintents/focus) | 집중 모드 필터·앱 설정 전달·해제·재시작 동작 |
| 배포 제약 | [Protecting user data with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox) | 앱 간 제어 제한과 App Store 배포 가능성 변화 |
| 로그인 시 자동 실행 | [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice) | mainApp 등록/해제, 승인 대기·거부·시스템 설정 변경, 앱 이동/서명 갱신 후 상태 |
| Finder에 폴더 열기 | [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace) | 지정 앱으로 일반 폴더 URL 전달, 전달 실패 처리 |
| Finder 통합 휴지통 열기 | [OpenConfiguration.appleEvent](https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/appleevent) | Finder의 `trash` 객체를 open 이벤트로 전달, Dock과 목록 비교, 추가 권한/전달 실패 여부 |
| 릴리스 변경 | [Apple Release Notes](https://developer.apple.com/documentation/technologies/release-notes) | AppKit, SwiftUI, App Intents, 접근성·입력 관련 변경 및 알려진 문제 |

## 디자인 갱신 원칙

1. 지원 대상 macOS의 실제 Spotlight·제어 센터·메뉴·선택 상태를 확인합니다. 비교한 OS 빌드, 외관 모드, 참고 화면을 기록합니다.
2. Apple이 제공하는 현재 네이티브 재질·표준 컨트롤을 먼저 평가합니다. 지원하는 SDK의 기본 동작 위에 불필요한 커스텀 배경·테두리를 덧씌우지 않습니다.
3. 곡률은 숫자 하나로 통일하지 않습니다. 바깥 곡면, 안쪽 여백, 내부 요소의 형태가 조화를 이루도록 당시 지침과 컨테이너 관계를 적용합니다. 모든 요소를 무조건 캡슐로 만들지도 않습니다.
4. 큰 고정 메뉴 버튼의 클릭 영역과 타일 배치는 유지하되, 재질·경계선·강조는 역할에 맞게 줄입니다. 중요한 구분은 배치와 그룹으로 전달합니다.
5. 실제 앱 아이콘과 지원되는 시스템 심벌을 사용합니다. 시안에서 임시로 만든 로고·곡선·그라데이션은 제품 규격으로 복사하지 않습니다.
6. Light/Dark, 대비 증가, 투명도 줄이기, 동작 줄이기, VoiceOver 및 키보드 포커스를 확인합니다. 반사·굴절이 제목이나 메뉴 이름을 가리지 않아야 합니다.
7. 웹 시안의 CSS로 Apple의 실제 렌더링이 정확하게 재현되었다고 가정하지 않습니다. 최종 외관은 네이티브 프로토타입에서 확인합니다.
8. Liquid Glass는 배경의 색과 내용을 받아 표현되므로 단색·사진 바탕화면, 밝고 어두운 다른 앱 창 위에서 모두 확인합니다. 효과 뒤를 불필요한 불투명 배경이 덮지 않는지, 컨테이너와 콘텐츠 구성이 공식 API 계약에 맞는지 검증합니다. API 적용만으로 곡률·여백·재질 선택이 자동 완성된다고 가정하지 않습니다.
9. 여러 효과를 사용하는 경우 공식 글래스 컨테이너의 묶음 처리를 평가하되, 서로 분리되어야 할 버튼의 재질이 원치 않게 합쳐지지 않는지도 확인합니다. 웹 시안의 ‘유리 불투명도 55%’를 네이티브 재질의 고정 숫자나 지원 API로 간주하지 않습니다.

2026-10-12 검토 근거: WWDC25 전사문은 고정 곡률·캡슐·컨테이너에 맞춘 곡면을 구분하고, 반복 장식보다 그룹과 배치에 의한 계층을 설명합니다. 로컬 SDK에는 `NSGlassEffectView`가 macOS 26 이상 API로 선언되어 있습니다. **미래 SDK에서도 같은 사용법·가용성을 유지한다고 가정하지 말고 다시 확인합니다.**

같은 날 추가 확인: Apple 공식 SwiftUI 문서는 Liquid Glass의 배경 흐림·주변 색과 빛의 반영, `glassEffect` 및 `GlassEffectContainer` 사용을 설명합니다. 로컬 `NSGlassEffectView.h`에서 뷰·컨테이너는 macOS 26 이상, `effectIsInteractive`는 macOS 27 이상으로 선언되어 있습니다. 클래스의 최소 버전과 개별 속성의 최소 버전을 구별해야 합니다. 웹 문서 일부는 JavaScript 안내만 반환하여 공식 문서의 검색 인덱스와 로컬 SDK로 보완했으며, 실제 앱 렌더링은 아직 검증하지 않았습니다.

## 업그레이드 작업 순서

1. **기준선 기록:** 현재 지원 OS, 새 OS/빌드, Xcode/SDK, 빌드 설정, 기존 기능·성능 기준선을 적습니다. 베타 결과는 정식 버전 결과와 구별합니다.
2. **문서 재확인:** 위 공식 문서와 최신 WWDC·릴리스 노트를 확인합니다. URL, 확인일, 변경 내용, 앱에 미치는 영향을 기록합니다. 열리지 않은 문서는 확인 완료로 처리하지 않습니다.
3. **영향 분류:** 디자인 자동 변경, 추가 코드가 필요한 변경, 폐기 API, 권한·배포 변경을 분리합니다. 사용자 요구의 변경이 필요한지는 별도로 판단합니다.
4. **작은 네이티브 검증:** 패널·입력·앱/창 전환·메뉴 실행·집중 모드 각각의 핵심 흐름을 새 SDK에서 검증합니다.
5. **구현:** 현재 Apple 컴포넌트를 활용하고 이전 지원 OS가 남아 있다면 가용성 분기와 검증된 대체 동작을 둡니다. 최소 지원 OS를 올릴 필요가 생기면 이유와 영향 범위를 사용자에게 설명합니다.
6. **회귀·성능 확인:** 아래 시나리오를 확인하고 실제 수치를 기록합니다. 미확인 기능은 통과로 표시하지 않습니다.
7. **문서 갱신:** 요청 기록에 변경 이유, 요구사항에 현재 동작, 이 문서에 새 근거와 검증 환경을 반영합니다. 배포했다면 릴리스 노트에 사용자에게 보이는 변화를 적습니다.

## 필수 회귀 시나리오

- 핀 → 같은 자리 닫기 전환, Option 해제 후 유지, `⌘⇧5`와 캡처 영역 선택 중 유지, 바깥 클릭/앱 전환 후 유지, `×`·Esc 닫기와 다음 호출 초기화. 고정 중 Option을 누른 채 대상을 선택하면 해제 뒤 실행되는지 확인.
- 실제 Dock의 고정 앱·폴더 순서와 가져온 결과 비교. Finder/통합 휴지통, 한글/공백/퍼센트 인코딩, 옮기거나 삭제한 앱, 분리된 볼륨, 빈 목록, 지원하지 않는 타일, 중복/재실행을 확인. 기존 이름·폴더 방식·Dock 밖 항목을 잃지 않고 Dock 원본이 바뀌지 않아야 함.
- `persistent-apps`/`persistent-others`와 `_CFURLString` 저장 형식은 CFPreferences 공개 API의 보장 사항이 아님. 새 macOS에서 실제 데이터를 확인하고 변경 시 파서를 갱신함. 가져오기는 버튼을 눌렀을 때만 수행하며 실패 시 수동 추가를 안내함.
- 최소·최대 패널 및 긴 앱/창 이름에서 중앙 제목과 좌우 버튼이 겹치지 않는지, 폴더 탐색에서도 왼쪽 닫기와 뒤로 가기를 구분할 수 있는지 확인. 오른쪽 캡슐은 네이티브 glassEffect를 사용하며 라이트/다크·투명도 줄이기를 확인.
- AppKit 메뉴 responder를 통한 `⌘W` 닫기·`⌘,` 설정·`⌘H` 가리기·`⌘Q` 종료가 앱 자신의 창에서 작동하고, 다른 앱에 포커스가 있으면 해당 앱의 입력을 침범하지 않는지 확인.
- Option 단독 누름/해제, 다른 보조키와의 조합, Option 드래그, 한국어·영어 입력, 빠른 반복 호출. 호출이 기존 작업을 방해하지 않는지 확인.
- 패널 표시로 원래 앱·창의 문맥이나 선택 상태가 바뀌지 않는지 확인. 메뉴 실행 시 보조키 잔류와 다른 앱으로의 잘못된 실행 방지.
- `requirements.md`에 기록된 최근 목록의 세 가지 예시. 현재 앱 내부의 창 전환과 서로 다른 앱 사이의 전환 모두 확인.
- 같은 제목의 서로 다른 창, 제목 변경, 창 닫기, 앱 재실행, 최소화, 여러 모니터·Spaces·전체 화면·Stage Manager.
- 접근성/입력 관련 권한 거부·철회·재허용, 절전 복귀, 이벤트 구독 복구. 지원하지 않는 앱의 조회 때문에 전체 UI가 멈추지 않는지 확인.
- Excel의 실제 이미지 관련 명령, 선택 상태에 따른 비활성 메뉴, 앱 언어 변경, 메뉴 경로 변경, 응답 지연. 시간 초과 후 실행 여부가 불명확하면 명령을 자동으로 중복 실행하지 않음.
- 집중 모드의 변경·해제·미설정, 앱 재시작, 수동 프로필 선택. 자동 연동 실패 시 적용 중인 구성이 잘못 표시되지 않는지 확인.
- 라이트/다크 및 시스템 접근성 옵션, 작은 화면과 고해상도 디스플레이. 글자·포커스 표시·클릭 영역의 가독성.
- 화면 배율·사용 가능 영역 변경, 모니터 간 이동/재호출, 최근 창 영역의 열 경계 전후 크기. 자동 모드가 2줄·최소 6개 용량을 유지하며 공간에 따라 8·10·12개 이상으로 늘어나는지 확인. 작은 화면에서 최소 크기를 지킬 수 없는 경우의 대체 탐색은 별도 기록.
- 수동 개수 6·7·12 및 화면 수용량보다 큰 값, 실제 창 수보다 큰 값, 잘못된 입력. 대상 창 0·1·5개일 때 없는 창을 채우지 않는지 확인. 최신 요구사항에 정해진 초과 항목 탐색과 정렬이 일치하는지 확인.
- 스크롤 방향과 채우기 순서를 함께 확인. 행 우선+세로 또는 열 우선+가로 모두 3열 × 2줄의 첫 화면에 1~6번째가 보이는지, 최신 4~6번째가 다른 방향으로 가려지지 않는지 검증. 시각 순서와 키보드·VoiceOver 탐색도 일치시킴.
- 세로 방식을 채택했다면 최근 창 영역만 스크롤되고 다른 영역은 고정되는지, 재호출 시 최신 창부터 보이는지 확인. 일반 마우스·트랙패드·관성 스크롤과 입력 방향을 검증.
- 커서 기준 호출을 채택했다면 중앙·네 모서리·가장자리·메뉴 막대·Dock 인접 위치와 다중 모니터 경계에서 경계 보정 확인. 음수 화면 원점과 혼합 배율에서 위치만 보정되고 타일 순서·크기가 흔들리지 않는지 확인. 패널 표시 직후 커서 이동으로 패널이 따라오거나 아래 항목이 자동 실행되지 않아야 함.
- 약 절반이라는 면적 목표를 너비와 높이 각각 절반으로 잘못 적용하지 않았는지 확인. 작은 작업 영역에서 최소 6개·가독성·화면 내 배치가 충돌하면 실제 결과와 대체 동작을 기록. 디스플레이 분리 시에도 화면 밖으로 유실되지 않도록 처리.
- 최소·최대 크기 경계, 초광폭 화면, 가용 영역이 최소값보다 작은 화면에서 패널 크기와 최근 창 수용량을 확인. 가로를 줄일 때 기존 세로 높이감과 클릭 영역이 유지되는지, 화면 면적 50%를 강제로 맞추며 패널이 길어지지 않는지 검증. 웹 시안의 CSS px와 macOS 포인트를 혼용하지 않음.
- 32:9·21:9·16:9·16:10·4:3 및 세로 모니터에서 패널의 자체 종횡비와 최소/최대 크기를 동시에 확인. 같은 가용 높이에서 가로 여유만 늘 때 패널이 불필요하게 길어지지 않아야 함. 배율·접근성 글자 크기와 작은 작업 영역의 예외를 분리하여 기록하고, 화면 모서리 위치 보정이 종횡비를 바꾸지 않는지 확인.
- 단색·사진 바탕화면과 다른 앱 창 위에서 실제 Liquid Glass 재질을 검증. 투명도 줄이기 상태에서 효과가 약해져도 필수 정보와 조작이 유지되는지 확인.

## 성능 검증과 기록

- 아이콘·타일 표시 정보는 재사용하고, 최근 이력은 이벤트 기반으로 갱신하는 방향을 유지합니다. 모든 앱의 메뉴 전체를 주기적으로 스캔하는 방식은 채택 근거 없이 도입하지 않습니다.
- 메뉴 이름·경로의 캐시와 실행 가능 상태를 구분합니다. 이벤트를 지원하지 않는 앱은 호출 시 보완 조회 등 제한된 방법으로 대응합니다.
- 조회는 UI 표시를 막지 않도록 구성하고 시간 제한·취소·실패 처리를 검증합니다. 캐시와 관찰 대상에는 수명 및 정리 정책이 필요합니다.
- 유휴 CPU/에너지, 호출부터 첫 표시까지의 지연, 창 전환 반복 중 CPU, 최대 메모리, 창·앱을 닫은 뒤 메모리 회수 상태를 측정합니다.
- 적은 창과 많은 창(예: 5·20·50개), 장시간 실행, 빠른 전환을 비교합니다. 창 수는 검사 입력이지 성능 보장이 아닙니다.
- 기본적으로 실시간 창 캡처 없이 아이콘·제목으로 검증합니다. 썸네일을 추가한다면 캡처 권한·갱신 주기·숨김 상태의 작업 중단을 별도 평가합니다.
- Liquid Glass 비용은 실제 네이티브 구현에서 측정합니다. 웹 시안의 블러 횟수나 계산상 아이콘 바이트 수를 앱 전체 성능으로 설명하지 않습니다.
- 도구는 현재 Xcode의 Instruments 등을 사용하되 도구명보다 재현 가능한 입력·측정 조건·비교 수치를 남기는 것을 우선합니다.

## 업그레이드 기록 양식

```markdown
### YYYY-MM-DD · macOS/SDK 대응
- 대상 OS 및 빌드 / Xcode 및 SDK:
- 기존·변경 후 최소 지원 OS:
- 확인한 공식 문서, URL, 확인일:
- Apple 지침/API에서 달라진 내용:
- 제품에 반영한 내용과 유지한 UX:
- 사용자 요청 또는 미정 결정:
- 회귀 시나리오 결과 및 미확인 항목:
- 성능 측정 환경과 전후 수치:
- 호환성·권한·배포 영향 및 남은 작업:
```

## 2026-10-12 · 첫 빌드에서 생긴 검증 기준

- 최신 기본값은 requirements.md 상단, 실제 통과/미확인 항목은 validation.md를 확인한다. R21에서 세로 스크롤·커서 중심이 선택되었으며 기존 미정 표기는 과거 논의다.
- 폴더 타일을 추가했다. NSOpenPanel·파일 접근 권한·추가 날짜 메타데이터·패키지 앱/폴더 구별을 업그레이드 시 확인한다. R29부터 휴지통은 Finder 전용이며 오버레이 탐색으로 되돌리지 않는다. 전체 디스크 접근 권한을 임의로 켜거나 Finder의 외장 볼륨 휴지통 표시까지 검증 없이 보장하지 않는다.
- 등록 항목 순서를 저장하며, 후속 고정 메뉴에도 동일하게 수동 순서 변경을 제공한다.
- `--render-check` 자체 콘텐츠 이미지는 실제 Glass 배경 합성 검증을 대체하지 않는다. 배경 위 외관은 반드시 직접 확인한다.
- File Provider가 앱 패키지에 메타데이터를 붙이는 작업 폴더에서는 실행용 출력 경로를 동기화 폴더 밖에 둔다. Xcode 베타 결과와 정식 OS 결과는 계속 구분한다.
- 로그인 항목 켜기/끄기, 승인 대기, 시스템 설정에서 직접 해제 후 앱 복귀, 실제 로그아웃/로그인, 앱 이동·업데이트 시 경로/서명 변경을 확인한다. 앱 시작 때 자동으로 재등록하여 사용자의 해제를 덮어쓰지 않는다.
- 앱 반복 열기·동시 시작·복사본·실행 파일 직접 실행에서 한 인스턴스만 유지되는지, 정상 종료와 충돌 후 재실행 가능한지 확인한다. 잠금 파일을 삭제하면 잠금이 분리될 수 있으므로 프로세스 종료 시 파일을 지우지 않는다.
- 일반 폴더별 여는 방식의 저장/재실행·기존 등록 데이터 마이그레이션, 휴지통의 Finder 고정 안내와 선택 불가, 외장 저장소 연결/해제 후 Finder 휴지통 실행을 확인한다.
- R31의 휴지통은 경로가 아닌 Finder 애플리케이션의 `trash` 객체다. 새 OS의 `/System/Library/CoreServices/Finder.app/Contents/Resources/Finder.sdef`에서 읽기 전용 `trash` 속성(`trsh`)과 `open` 이벤트(`aevt`/`odoc`)를 재확인한다. 현재 Apple 문서의 `NSWorkspace.OpenConfiguration.appleEvent` 지원과 오류 처리도 확인한다.
- ‘Bin/휴지통’이라는 창 제목만으로 성공을 판정하지 않는다. Dock에서 연 통합 휴지통과 타일에서 연 창의 목록·개수·경로 막대를 비교한다. 일반 Finder 창이 앞에 있는 경우와 통합 휴지통이 이미 열린 경우를 모두 확인하고, 다른 볼륨 연결/해제 후 다시 비교한다. 삭제나 비우기를 검증 수단으로 사용하지 않는다.
- 통합 휴지통 요청이 실패할 때 `~/.Trash` 또는 볼륨별 `.Trashes`로 자동 대체하지 않는다. 실패를 표시하며 권한 확대나 직접 수집이 필요해지면 제품 동작 변경으로 검토한다. 현재 개발 빌드 검증을 향후 서명·공증·다른 OS의 동작 보장으로 간주하지 않는다.

## R38–R39 · 앱 교체와 오버레이 키 입력 회귀 점검

- 같은 빌드 재실행은 기존 PID 유지, 다른 빌드 재실행은 기존 PID 종료와 새 PID 생존을 함께 확인한다. 버전 숫자가 낮은 앱을 나중에 실행해도 전환되어야 한다. 복사본·동시 실행·로그인 시작과 수동 시작의 경합도 확인한다.
- 기존 프로세스가 시작한 뒤 같은 경로의 앱 패키지를 교체하고 Finder에서 다시 연다. 런타임 버전은 시작 시 기록된 값으로 유지되고, 새 빌드가 한 번만 시작되어야 한다. 종료 거부·시간 초과·손상된 소유자 기록·충돌 후 재실행도 확인한다. 잠금 파일 자체를 지우지 않는다.
- `NSRunningApplication.terminate()`의 true는 종료 완료가 아니다. 실제 종료와 잠금 해제를 확인한다. R40에서 앱 시작 단계의 `isTerminated` 반영 지연을 재현했으므로 종료 대기를 그 속성만으로 판단하지 않는다. `launchDate`는 LaunchServices 경유 실행에서만 제공되므로 직접 실행도 지원하려면 커널의 PID/시작 시각 확인 경로를 검증한다. 새 SDK의 libproc 공개 헤더와 배포 환경에서 컴파일/실행을 확인한다.
- 표시 전 `⌥⌘` 조합은 호출하지 않아야 한다. Option 단독으로 표시된 뒤 Command만 추가해도 닫히지 않고, Option을 유지한 `⌘,`로 설정이 즉시 열려야 한다. `⌥X`로 고정 후 Option을 놓아도 유지하고 Esc/`⌘W`는 닫아야 한다. 빠른 반복·한국어/영어 입력기·좌우 Option을 확인한다.
- 비활성화 NSPanel이 키 입력을 받으면서 원래 앱/창의 스냅샷 문맥을 유지하는지 확인한다. 로컬 모니터가 처리한 키는 nil을 반환하여 중복 전달하지 않는다. 다른 앱으로 포커스를 옮기면 해당 앱의 키 입력을 가로채지 않아야 한다.
- 2026-10-12 확인한 공식 자료: [앱 종료 요청](https://developer.apple.com/documentation/appkit/nsrunningapplication/terminate()), [launchDate](https://developer.apple.com/documentation/appkit/nsrunningapplication/launchdate), [새 인스턴스 실행](https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/createsnewapplicationinstance), [로컬/전역 이벤트 모니터](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html), [비활성화 패널](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel). 다음 OS 대응 시 당시 문서를 다시 확인한다.

## R42·R44·R45 · 고정 오버레이 이동과 헤더 컨트롤

- 고정 전에는 헤더를 드래그해도 이동하지 않고, 버튼/⌥X로 고정하면 제목·설명과 상단의 모든 여백을 잡아 이동할 수 있어야 한다(R44). 위쪽·왼쪽·오른쪽 가장자리, 버튼 사이, 폴더 진입/복귀 전후를 확인한다. 이동 후 Option 해제로 닫히지 않고 Esc/⌘W/닫기 버튼과 설정 열기가 유지되는지 확인한다.
- 실제 타일, 폴더 뒤로, 왼쪽 닫기, 오른쪽 설정 위의 마우스 입력을 드래그 영역이 가로채지 않는지 확인한다. 비활성 상태의 고정 창도 첫 클릭으로 드래그할 수 있어야 한다.
- 기본/작은 배치, 폴더 안 헤더, 다른 배율·음수 원점의 모니터로 드래그, 화면 가장자리와 Space 전환을 확인한다. 이동 중 화면 크기·배율 재계산을 임의로 추가하지 않고 다음 호출의 커서 중심 배치가 유지되는지 검사한다.
- [performDrag(with:)](https://developer.apple.com/documentation/appkit/nswindow/performdrag(with:))는 원래 mouse-down 이벤트를 넘기고 Window Server에 이동을 맡긴다. 로컬 SDK 문서상 즉시 반환하며 mouse-up이 오지 않을 수 있으므로 반환/마우스 해제를 드래그 완료로 간주하지 않는다. [isMovable](https://developer.apple.com/documentation/appkit/nswindow/ismovable) 및 최신 [Windows HIG](https://developer.apple.com/design/human-interface-guidelines/windows)를 함께 재확인한다.
- 드래그에서 제외할 컨트롤 영역은 고정 너비 추정 대신 SwiftUI anchor preference에서 구한다. NSView의 flipped 좌표계와 hitTest의 상위 뷰 좌표 변환을 함께 검증한다. 폴더 진입으로 뒤로 버튼이 생기거나 사라질 때 영역이 즉시 맞아야 한다.
- 뒤로 가기·핀/닫기의 원형 글래스, 대비/투명도 줄이기, 첫 클릭, 툴팁, VoiceOver, 네이티브 눌림 상태를 비교한다. 2026-10-12 [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)의 모양 및 interactive 설정을 확인함. 추후 표준 버튼 스타일/컨테이너로 옮기면 모양과 실제 클릭 영역을 재검증한다.
- R43·R46에서 검토한 메뉴는 R52로 네이티브 구현을 승인했다. 업그레이드 시 앱별 메뉴 ID 중복 제거, 로컬 실행 빈도, 작은/큰 타일과 고정 색/핀 표시, 수동 고정 순서, 열린 동안 자동 재배치 방지, 빈 데이터·권한 오류·긴 메뉴 이름을 검증한다. 고정/자주/최근을 별도 영역으로 다시 나누거나 전체 메뉴 사용 추적을 보장하지 않는다.

## R52–R53 · 혼합 타일·숫자·메뉴·Focus 회귀 점검

- Terminal/Terminal/Safari/Terminal, 앱별 창 하나, 같은 앱 창만 많은 경우를 확인한다. 순서를 빈칸 채우기로 바꾸지 않으며 큰 타일도 개별 창을 전환해야 한다. 메뉴와 창 공통 높이, 큰 메뉴 둘의 가로 배치, 긴 제목/한국어 줄바꿈, 등록 아이콘 36개 이상을 확인한다.
- 자동 배치는 가로형/정사각형 혼합을 두 줄 뷰포트에 담고 나머지는 스크롤한다(R57). 목록을 첫 두 줄에서 잘라내지 않는다. 최소 여섯 가로형 용량, 수동 6/7/12/큰 값, 빈 목록, 줄 끝 공백, 작은 배치와 비율 경계를 점검한다. 코드의 1.45 목표는 Apple 고정 지침이 아니다.
- ⌥숫자 등록/⌥⌘숫자 창 기본값과 반대 설정, 1–9/0·키패드·양쪽 Option·한영 입력·키 반복·보조키 해제 순서를 확인한다. 숫자 선택 변경/취소, 고정한 패널, 폴더 진입, 다른 앱 포커스에서 입력 비점유도 검사한다. 열린 동안 자동 MRU/Focus 변경이 번호의 대상을 바꾸면 안 된다.
- 메뉴는 설정에서만 열거하고 실행 직전 경로/활성/AXPress를 확인한다. 미노출/동적 메뉴, 중복 이름, 앱 종료, 문서 선택, 언어 변경, 응답 시간 초과 후 중복 실행 방지, 실패 통계 미반영, 3회 확대와 핀/순서 저장을 확인한다. 실제 Excel 명령을 대상으로 최종 검증하되 사용자 문서를 임의로 바꾸는 테스트는 피한다.
- Focus는 `SetFocusFilterIntent`/`AppEntity`/`current`의 당시 SDK 선언과 [Focus 필터 공식 설명](https://developer.apple.com/videos/play/wwdc2022/10121/), [Focus 문서](https://developer.apple.com/documentation/appintents/focus)를 재확인한다. 사용자 구성 필터, 해제, 미설정, 앱 재시작/깨우기, 삭제된 프로필, 수동 선택과 자동 복귀를 실기로 검증한다. 모든 집중 모드 이름을 읽는 기능으로 설명하지 않는다.
- SwiftPM 릴리스 앱은 `scripts/extract-intents.py`가 Xcode의 `appintentsmetadataprocessor`로 `Contents/Resources/Metadata.appintents`를 패키징한다. Xcode 업데이트 시 `.swiftconstvalues` 경로·프로세서 옵션·추출된 LauncherFocusIntent/프로필 엔터티를 검사한다. 메타데이터 존재만으로 시스템 설정 등록/실제 Focus 전환 성공을 판정하지 않는다.
- 기존 pinnedItems → 기본 프로필 이전에서 ID·순서·폴더 방식과 사용자 데이터를 보존한다. 앱 복사본이 여러 경로에 있으면 실제 실행 경로/버전과 로그인 항목을 확인하고 검증 중 허용한 접근성 대상과 일치시키며, 권한을 임의로 확대하지 않는다.

- R55: 실행 잠금이 없는 초기 앱을 먼저 띄운 뒤 새 앱을 실행하는 마이그레이션을 회귀 검사한다. 잠금을 획득했다고 다른 앱이 없다고 가정하지 않는다. 같은 최신 빌드 재열기 때도 기록된 소유자 외의 초기 복사본을 정상 종료하는지 확인한다. 과거 바이너리를 나중에 직접 실행하는 상황은 구분해서 기록한다.

## R56–R57 · 하단 선반과 여러 데스크탑

- 등록 0/1/16/36/200개, 512×420 및 정상 최소/최대 패널에서 확인한다. 선반은 푸터 위에 붙고 넘치는 등록 항목만 스크롤한다. 메뉴/최근 창의 높이와 비율을 유지하며 여백 30%는 조정 가능한 앱 규칙이다. 화면 경계 보정과 포인터 아래 타일의 의도치 않은 실행을 함께 점검한다.
- 공개 [AXWindows](https://developer.apple.com/documentation/applicationservices/kaxwindowsattribute)와 [CGWindowListCopyWindowInfo](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo) 문서/SDK 선언을 다시 확인한다. AX의 일시 누락이나 시간 초과를 창 닫힘으로 해석하지 않는다. CG 정보는 .optionAll/.excludeDesktopElements를 사용하며 화면 이미지를 캡처하지 않는다.
- DesktopWindows.swift의 내부 함수는 **공개 지원 계약이 아니다**. CGSMainConnectionID/_CGSDefaultConnection, CGSCopyManagedDisplaySpaces, CGSCopySpacesForWindows, CGSManagedDisplaySetCurrentSpace, _AXUIElementGetWindow의 존재뿐 아니라 ABI·소유권·반환 구조·권한과 실제 동작을 새 OS에서 확인한다. 런타임 심볼 확인만으로 호환 보장을 선언하지 않는다.
- 구현 참고 1차 자료: [Mozilla Cocoa 구현](https://searchfox.org/firefox-main/source/widget/cocoa/nsCocoaWindow.mm), [CGS Space 선언](https://github.com/NUIKit/CGSInternal/blob/master/CGSSpace.h), [AX 창 ID 연결 구현](https://github.com/sentialx/node-window-manager/blob/master/lib/macos.mm). 이 자료는 Apple의 지원 약속이 아니다. App Store 배포를 검토할 때 내부 API 사용 여부를 별도로 해결한다.
- 내부 API가 없거나 Space 배열이 비면 화면에 있다는 확실한 공개 정보만 현재로 판단한다. 화면 밖이라는 이유만으로 다른 데스크탑이라 하지 않는다(최소화/가리기 포함). 다중 모니터·각 모니터 별도 Space·모든 데스크탑 배정·전체 화면·Stage Manager를 각각 검사한다.
- 다른 Space에서 앱을 연 뒤 런처를 시작하는 경우와, 런처 시작 후 Space를 오가는 경우를 둘 다 검사한다. 캐시된 AX와 새 CG 창의 ID/PID를 정확히 연결하고 제목 변경·동명/같은 위치 창·종료/재실행·닫힘 알림 지연을 확인한다. 앱 내부 레이어 0 보조 창이 잘못 포함되지 않는지도 검사한다.
- CG 제목은 화면 녹화 허용 없이 없을 수 있다([Apple DTS 설명](https://developer.apple.com/forums/thread/794253)). AX 제목을 우선하며 모르면 대체 제목을 쓰고 추가 권한을 유도하지 않는다. 창 제목·개인 앱 목록·스크린샷은 저장소에 넣지 않는다.
- 창 선택 시에만 대상 Space 이동을 요청한다. 창 자체를 다른 Space로 이동하거나 Mission Control 설정을 바꾸지 않는다. 이동 후 같은 창 ID의 AX를 다시 찾아 선택하며 실패 시 다른 창을 대신 선택하지 않는다. Space 전환/AX 재조회는 비동기이므로 반환값만으로 사용자에게 보이는 전환 성공을 판정하지 않는다.
- 고정 오버레이에서 Space 이동 후 모든 현재 창의 배경색이 갱신되면서 타일 순서·크기·번호는 유지되는지 확인한다. 현재 창 하나만 강조하지 않는다. 자동 모드 전체 목록과 수동 최대 개수, 두 줄 밖 스크롤을 실기로 확인한다.

## R58–R60 · 빈 프로필·고정 후 기본 명령·작은 등록 타일

- 빈 프로필 추가는 등록 항목 0개로 시작하고 현재 구성 복제는 항목/순서/폴더 방식을 보존해야 한다. 두 동작 모두 새 ID로 생성·선택되며 원본은 바뀌지 않아야 한다. 공백 이름 거부, 저장/재실행, 복제본 편집의 독립성, 수동 선택과 Focus 전환을 검사한다. 설정 최소 폭에서 이름 입력란과 두 버튼이 잘리지 않는지 직접 확인한다.
- Option을 누르는 일반 패널은 원래 앱 문맥을 유지한다. 핀 버튼/⌥X로 고정하는 순간에는 앱 활성화와 key window를 요청한다. 상태 값만 고정으로 바꾸지 않는다. 비활성화 패널의 styleMask를 실행 중 임의 전환하지 않고 당시 AppKit 동작/공식 문서를 확인한다.
- Command 조합은 일반 keyDown 모니터와 별도의 key-equivalent 경로로 처리될 수 있다. NSPanel.performKeyEquivalent와 로컬 이벤트 모니터가 같은 단축키 판단을 사용하며 처리한 명령은 한 번만 실행해야 한다. 실제 Option 유지→오버레이→⌥X→Option 해제→⌘W, 다시 호출/고정→⌘,를 확인한다. 핀 버튼으로 고정한 경우와 Option을 계속 누른 조합도 검사한다.
- 다른 앱을 클릭한 뒤에는 해당 앱의 ⌘W/⌘,를 가로채지 않아야 한다. 키 창 여부, 키 반복 억제, 숫자로 대기 중인 선택의 취소, 메뉴/프로필 변경 후 다시 고정하는 경로를 확인한다. 합성 NSEvent 및 단위 테스트와 실제 키보드 검증을 구분한다.
- 등록 타일의 최소 60pt 정사각형·32pt 아이콘·8pt 간격·12pt 연속 곡선은 현재 앱의 조정값이며 Apple 규격이 아니다. 512–1,040pt 폭/열 수 전환점에서 그리드와 선반 높이가 같은 기하를 사용하는지, 0/1/14/35/200개와 긴 이름·숫자 배지가 잘리지 않는지 확인한다. 다크/라이트·대비 증가·투명도 줄이기·포커스/VoiceOver를 검증하고 개별 타일마다 불필요한 유리 합성이나 블러를 추가하지 않는다.
- 2026-10-12 참고한 Apple 공식 자료: [키 이벤트와 key equivalents](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingKeyEvents/HandlingKeyEvents.html), [앱 활성화 요청](https://developer.apple.com/documentation/appkit/nsapplication/activate()), [key window](https://developer.apple.com/documentation/appkit/nsapplication/keywindow). 이벤트 설명은 보관 문서이므로 다음 업그레이드 시 최신 SDK 선언·공식 자료와 실제 동작을 함께 재확인한다.
