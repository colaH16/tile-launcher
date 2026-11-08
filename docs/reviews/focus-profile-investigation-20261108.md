# macOS Focus 전환 후 런처 프로필 조사

조사일: 2026-11-08 (Asia/Seoul)

## 요약과 현재 상태

사용자는 회사 Mac에서 macOS 집중 모드를 바꿔도 같은 런처 프로필이 열린다고 보고했다. 런처 내부에서 프로필을 직접 선택하는 기능이 실패했다는 보고는 아니다. 재현에 필요한 프로필은 회사 Mac에 있으며, 집 Mac에서 같은 사용자 구성을 재현하거나 회사 설정을 읽지는 않았다.

루트 에이전트와 기존 Codex 서브에이전트의 독립 소스 조사는 **열린 오버레이에 Focus 변경을 적용하는 연결이 빠져 있다**는 결론에 일치했다. 다만 이것이 회사에서 보고한 현상의 실제 원인인지는 아직 확정하지 않았다. 자동 추종 설정, Focus ID 전달과 유효성, 완전히 닫은 뒤 새 호출인지에 따라 원인이 달라진다.

현재 루트가 회사 Mac의 자동 선택 토글 상태에 대한 사용자 답을 기다리고 있다. 이번 단계에서는 소스와 기존 검사 범위를 읽었으며 제품 코드·설정·버전·빌드·설치·배포를 변경하지 않았다. 이 문서만 새로 기록했다. 사용자는 원인을 계속 알 수 없을 경우 검증용 빌드를 조건부로 요청했다. 그 요청을 무시하고 모든 다음 작업에 새로운 승인이 반드시 필요하다고 해석하지 않는다. 현재는 회사 상태를 좁히는 조사 단계다.

## 확인한 소스 경로

| 경로 | 확인 내용 |
| --- | --- |
| `Sources/TileLauncher/FocusProfileIntent.swift:30–35` | Focus `perform()`은 선택 ID를 프로세스 내 알림으로 전달한다. 회사에서 실제로 전달됐는지는 미관측이다. |
| `Sources/TileLauncher/main.swift:168–170` | 알림 수신자는 `settings.focusProfileID`만 변경한다. 표시 프로필 갱신은 호출하지 않는다. |
| `Sources/TileLauncher/Models.swift:219–236` | 자동 추종이 켜져 있고 Focus ID가 현재 프로필에 존재할 때만 Focus 프로필을 선택한다. 그 외에는 수동 선택, 없으면 첫 프로필로 돌아간다. 직접 선택은 자동 추종을 끈다. |
| `Sources/TileLauncher/Models.swift:351–354` | 수동 선택과 자동 추종 여부는 저장값에서 복원한다. 자동 추종 기본값은 `true`다. |
| `Sources/TileLauncher/Views.swift:205–206` | 등록 항목과 프로필 이름은 `presentation.profile`이 있으면 이를 우선한다. |
| `Sources/TileLauncher/main.swift:1054` | 숫자 선택 대상 역시 표시 프로필의 항목을 우선한다. 제목만 이전 값인 문제가 아니다. |
| `Sources/TileLauncher/main.swift:633–639`, `Models.swift:148–165` | 일반 콘텐츠 갱신은 기존 snapshot의 등록 항목·프로필 ID·이름을 보존하고, 크기도 기존 표시 프로필을 기준으로 계산한다. |
| `Sources/TileLauncher/Views.swift:294–298` | 뷰의 변경 감시는 메뉴 편집 상태 초기화와 크기 갱신이며, Focus 프로필 적용 경로가 아니다. |
| `Sources/TileLauncher/IconReadAhead.swift:27–34` | 프로필 관련 설정 구독은 이미지 사전 준비만 수행한다. |
| `Sources/TileLauncher/SettingsEditingSession.swift:39–45` | 설정 변경 구독은 편집본 동기화이며 오버레이 표시 프로필을 바꾸지 않는다. |

전체 `objectWillChange`/설정 구독과 표시 프로필 할당 경로를 대조했으며, 위 누락을 보완하는 다른 제품 경로는 찾지 못했다. SwiftUI가 설정 변경으로 다시 그려져도 `presentation.profile` 우선 규칙은 그대로다.

## 확정된 결함과 아직 가능한 원인

### 열린 오버레이의 표시 프로필 유지 — 소스상 확인

오버레이를 연 뒤 Focus 알림으로 유효한 새 ID가 들어오면 `settings.activeProfile`은 달라질 수 있지만, 이미 설정된 `presentation.profile`은 그대로다. 따라서 열린 고정 오버레이의 프로필 이름·등록 목록·숫자 선택 대상은 이전 프로필을 유지할 수 있다.

이미 보이는 오버레이에 `show`를 다시 호출하는 경우도 새 호출과 다르다. `main.swift:415–419`는 수동 호출이면 고정/앞으로 가져오기만 하고 반환하므로 프로필을 새로 선택하지 않는다.

### 자동 추종이 꺼진 상태 — 현재 제품의 정상 수동 우선순위

`followFocus == false`이면 Focus ID가 새로 전달돼도 수동 프로필을 유지하는 것이 현재 명시된 동작이다. 이 상태 자체를 Focus 전달 실패나 오버레이 결함으로 단정하지 않는다. 런처의 직접 프로필 선택은 `selectProfile`을 통해 자동 추종을 끄고 그 값을 저장한다.

설정 창의 자동 선택 토글은 등록 항목·프로필 **편집본**에 연결돼 있다(`SettingsView.swift:40–42, 80`). 편집본에서 바꾸기만 한 상태와 저장해 실제 설정에 반영한 상태를 구분해야 한다(`SettingsEditingSession.swift:199–202`).

### Focus ID 없음·현재 프로필과 불일치 — 가능한 fallback

자동 추종이 켜져도 Focus ID가 없거나 현재 Mac의 프로필 목록에 없으면 수동 프로필로 돌아간다. 프로필은 Mac별로 저장하고 새 프로필 ID는 UUID로 생성한다(`LauncherProfile.swift:7–14`, `README.md:25`). 이름이 같다는 이유로 ID도 같다고 가정하지 않는다. 회사에서 이 조건이 발생했는지는 확인하지 않았다.

### 늦은 `current` 조회 — 소스상 가능한 경쟁 조건

`refreshFocus`는 앱 시작, 깨우기, 오버레이에서 자동 선택을 누를 때 호출된다(`main.swift:171, 206, 1001`). 일반 `show`에서는 조회하지 않는다. `main.swift:985–990`의 비동기 조회 결과에는 요청 세대나 최신 알림과의 순서 검증이 없다. 늦게 끝난 과거 조회나 오류의 `nil` 처리가 더 최근 `perform` 알림의 ID를 덮을 가능성이 있다. 회사에서 이 경쟁이 실제 발생했다는 증거는 없다.

`profileChangeRevision` 검사는 자동 선택 완료 후 화면을 다시 표시하는 부분에만 적용된다(`main.swift:1000–1005`). 그보다 앞선 `settings.focusProfileID` 대입을 막지는 않는다. 임시 순환 뒤 늦은 응답이 현재 화면을 덮는 것은 막을 수 있어도, 다음 호출에 쓰일 active 설정까지 보호하는 장치는 아니다.

## 새 호출·사전 준비·임시 순환의 구분

- **완전히 숨긴 뒤 새로 열기:** `hide`가 표시 프로필과 사전 준비를 지우고(`main.swift:653–674`), 새 snapshot과 `present`가 현재 `settings.activeProfile`을 사용한다(`492–493, 559`). Focus ID 전달과 설정이 정상이라면 새 호출은 새 프로필을 보여야 한다.
- **이미 보이는 창 다시 열기:** 위의 `show` 조기 반환 때문에 표시 프로필을 재선택하지 않는다.
- **Option 표시 대기 중 Focus ID 변경:** 준비된 프로필 ID와 현재 active ID가 다르면 `takePreparedOverlay`의 `439` 검사에서 재사용을 거부하고 새로 만든다. 따라서 ID가 실제로 바뀐 경우의 사전 준비 캐시만으로 지속적인 이전 프로필 표시를 설명하기는 어렵다.
- **빠른 재열기:** 이전 위치/크기를 복원하지만 snapshot과 표시 프로필은 현재 active 선택으로 새로 만든다. 프로필 자체를 빠른 재열기 캐시에서 복원하지 않는다.
- **가로 쓸기·프로필 순환:** `cycleProfile`은 저장된 수동 선택이나 Focus를 바꾸지 않는 이번 표시의 임시 선택이다(`main.swift:1036–1040`). 이 요구는 유지해야 한다. 일반 콘텐츠 갱신마다 active 프로필로 무조건 초기화하는 수정은 임시 선택을 깨뜨린다.

실제 수정 설계에서는 현재 표시가 기본 선택을 따르는지, 사용자가 이번 표시만 임시로 바꿨는지를 구분하고 입력/실행 중 갱신 정책과 함께 검토해야 한다. 이번 문서에서 구현 방식을 확정하거나 코드를 바꾸지는 않았다.

## 기존 검사 범위와 미검증 사항

`PreviewFixtures.swift:183–205`의 `verifyFocusSelection()`은 합성 설정에서 다음 선택 규칙을 검사한다.

- 자동 추종이 꺼졌을 때 수동 프로필 유지.
- 자동 추종이 켜졌을 때 유효한 Focus ID 선택.
- Focus ID가 비었거나 삭제된 경우 수동 fallback.
- 수동 ID도 없을 때 기본 프로필 fallback.

`ProfileNavigationTests`는 저장 순서 순환, 임시 프로필 사용과 reset, 스와이프 판정을 검사한다. `OverlayPresentationTests`는 고정·닫힘·실행 피드백 상태를 다룬다. 이 검사들이 실제 macOS Focus 전달, 열린 제품 오버레이의 Focus 변경 반영, 서로 다른 시점의 비동기 `current` 응답을 검증했다는 뜻은 아니다.

과거 `docs/focus-diagnostics.md`의 사용자 성공은 Developer ID 서명 후 Focus 필터 로딩/사용 성공 보고다. 모든 자동 전환·해제·재시작 조합을 직접 확인한 결과로 확대하지 않는다. 이번 조사에서는 기존 검사를 새로 실행하거나 회사 Mac의 Focus를 조작하지 않았다.

## 회사 Mac에서 필요한 최소 구분

먼저 사용자가 답하는 자동 추종 설정 상태와, 완전히 닫은 뒤 새로 열었는지를 구분한다. 여전히 원인이 불명확하여 조건부 검증용 빌드가 필요하면 다음 **Boolean/고정된 이벤트 종류**만으로 상태를 좁힐 수 있다.

- 실제 저장된 자동 추종 여부.
- Focus ID 존재 여부와 현재 프로필 목록의 membership 여부.
- 오버레이 표시 여부, 표시 프로필과 active 프로필의 일치 여부.
- 임시 순환 선택 여부.
- `perform` 수신, `current` 조회 시작/성공/오류, 새 표시/이미 보이는 표시 요청의 구분과 필요한 순서 정보.

프로필 이름·UUID 원문·등록 항목 목록·앱/폴더 경로를 수집할 필요는 없다. 이름이나 ID의 실제 값을 출력하지 않고 존재·membership·동일성만 검사한다. 공개 로그를 요구하거나 회사 데이터 전체를 집 Mac으로 옮기는 방식은 필요하지 않다. 최소 구분 결과에 따라 수동 설정 상태, 전달/식별자 문제, 열린 표시 갱신 누락, 비동기 순서 문제를 나눈다.

## 2.2.0(83) 경로 UI와 관련성

83의 기록된 생산 변경은 저장된 메뉴 경로를 표시하는 `MenuTileCaption.swift`와 `Views.swift`의 메뉴 타일 caption이며, main 진입 추가는 DEBUG 렌더 검증이다. `docs/reviews/menu-path-caption-implementation-2.2.0-20261106.md:18–20`과 당시 독립 리뷰는 등록 프로필·Focus 선택 동작을 변경 범위로 포함하지 않는다.

현재 조사에서 경로 UI가 Focus 프로필 문제를 일으켰다는 직접 증거는 없다. 이를 설치 시점만으로 83의 회귀라고 단정하지 않는다. 이번 환경에는 당시 82 임시 소스 폴더가 없어 새 바이트 비교는 수행하지 않았으며, 회사에서 실제 발생한 최초 버전도 미확정이다.

## 공식 자료와 해석 범위

- [Apple: Focus](https://developer.apple.com/documentation/appintents/focus/)
- [Apple: Defining your app’s Focus filter](https://developer.apple.com/documentation/appintents/defining-your-app-s-focus-filter)
- [Apple WWDC22: Meet Focus filters](https://developer.apple.com/videos/play/wwdc2022/10121/)

루트의 공식 자료 교차 확인에서는 활성 Focus가 바뀔 때 `perform`으로 앱의 동작/표시를 갱신하고, 시작이나 필요한 시점에 `current`를 조회하는 흐름을 확인했다. 앱의 `perform` 경로가 ID 변경에서 끝나고 표시 프로필을 갱신하지 않는 소스 결함과 일치한다. 공식 자료는 회사 Mac에서 실제 알림이 전달됐다는 증거를 대신하지 않는다.
