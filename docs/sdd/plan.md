# Tile Launcher 구현 계획 (Plan) — 어떻게

- 작성: 2026-11-16 (Phase 3). 기준 코드: 2.3.0(86), GitHub `main` `e99cb78`
- 갱신: 2026-11-16 (Phase 5). 6절에 실행 후 닫힘 규칙을 넣고, 8절 TODO-001~003을 완료로 옮겼다.
- 무엇을·왜는 [spec.md](spec.md), 원칙은 [constitution.md](constitution.md), 근거와 대안은 [decisions.md](decisions.md)에 있다.
- **모든 항목에 출처를 붙였다.** 꼬리표 형식은 spec.md와 같다: `[u|a|d/h|s D-번호]`. decisions.md에 없는 사실 기록(현재 구조 설명)은 `[현황]`으로 표시했다. 이런 항목은 결정이 아니라 코드에서 읽은 사실이다.
- `d`(agent-default) 항목은 제약이 아니다. 더 나은 방법이 있으면 비교표를 들고 바꾸자고 제안해도 된다. `h` 항목은 출처와 상관없이 사용자에게 먼저 묻는다.

---

## 1. 기술 스택

| 항목 | 선택 | 출처 |
|---|---|---|
| 플랫폼 | macOS 전용 네이티브 앱 | [u/h D-001] |
| 언어 | Swift (tools 6.0, language mode v5) | [u/s D-002] |
| 빌드 | SwiftPM + 셸·Python 스크립트, `.xcodeproj` 없음 | [u/s D-002] |
| 최소 OS / 아키텍처 | macOS 26.0 / arm64 전용 | [u/s D-003] |
| UI | AppKit `NSPanel` + SwiftUI(`NSHostingView`) + `NSGlassEffectView` | [a/s D-024] |
| 외부 라이브러리 | 없음 | [d/s D-027] |
| 샌드박스 | 사용 안 함. entitlement는 `com.apple.security.automation.apple-events`만 | [u/h D-005] |
| 앱 형태 | `LSUIElement=true` 메뉴 막대 상주 (Dock 아이콘 없음) | [a/h D-004-2] |

## 2. OS 연동과 권한

| 항목 | 방법 | 출처 |
|---|---|---|
| 접근성 | 필수. 창 목록·메뉴 읽기·실행에 사용 | [a/s D-006] |
| 앱 관리 | 확인 화면만 제공, 필수 아님 | [a/s D-006] |
| 화면 녹화·전체 디스크 | 요구하지 않음 | [a/s D-006, u/h D-022-1] |
| Option 키 감지 | `NSEvent` 전역·로컬 모니터. 입력을 가로채지 않음 | [d/s D-007] |
| 다른 데스크탑 창 판별 | 비공개 함수 7개를 `dlsym`으로 선택적 사용(`_AXUIElementGetWindow`, `CGSCopySpacesForWindows`, `CGSCopyManagedDisplaySpaces`, `CGSMainConnectionID`, `_CGSDefaultConnection`, `CGSWindowIsOrderedIn`, `SLSWindowIsOrderedIn`). 없으면 공개 정보로만 판단 | [d/s D-008] |
| 로그인 자동 실행 | `SMAppService.mainApp`. 사용자가 끈 것은 되돌리지 않음 | [u/h D-013-1, d/s D-013-2] |
| 집중 모드 | 공개 `SetFocusFilterIntent` (`LauncherFocusIntent`). 유효한 Apple 서명이 필요 | [d/s D-059-2] |
| Handoff | Dock의 접근성 트리(비공개 구조)에서 Handoff 항목을 찾아 누름 | [d/s D-044-2] |
| 메뉴 실행 | 접근성 `AXPress`. 단축키를 흉내 내지 않음 | [d/s D-050-2] |

## 3. 구조

### 3.1 모듈

| 모듈 | 역할 | 출처 |
|---|---|---|
| `DeckCore` (라이브러리, 54파일) | UI 없는 로직: 배치 계산, 최근 순서, 메뉴 경로·수집 정책, 프로필 선택, 동기화 병합, 단축키 해석. XCTest 대상 | [d/s D-023] |
| `TileLauncher` (실행 파일) | AppKit/SwiftUI 화면, 접근성 호출, 오버레이 수명, 설정 창, CloudKit 전송 | [d/s D-023] |
| `main.swift` (87KB) | AppDelegate, 오버레이 생성·호출·닫기 흐름이 한 파일에 몰려 있음 | [d/s D-025] — 나누자는 제안 가능 |

### 3.2 디렉터리

```
Package.swift
Sources/DeckCore/        순수 로직 (Layout, TileArrangement, MenuCommand, ProfileSelection, SettingsSync* …)
Sources/TileLauncher/    앱 (main.swift, Views, SettingsView, HoldMonitor, WindowTracker, MenuUsageMonitor …)
                         *Validation.swift = Debug 전용 검증 모드
Tests/DeckCoreTests/     XCTest
scripts/                 build.sh, release.py, test.sh, preview.sh, tests/(Python)
release/                 config.json(버전 원본), notes.md, notes-range.json, drafts/, history/
Resources/               Info.plist, AppIcon.icns, Brand/
tools/                   드래그 시험 앱, cloud-signing
docs/                    설계·운영 문서, reviews/(기록), validation.md(기록)
docs/sdd/                SDD 문서
```
[현황] `* 2.swift` 같은 iCloud 충돌 사본 53개가 섞여 있다. 빌드에 넣지 않고 보존만 한다.

### 3.3 상태와 동시성

| 항목 | 방법 | 출처 |
|---|---|---|
| UI 상태 | `@MainActor` 모델 | [d/s D-026] |
| 접근성 조회 | 앱별 `DispatchQueue` 직렬 큐. 메인 스레드에서 기다리지 않음 | [d/s D-026] |
| 시간 제한·재시도 | AX 요청 300ms, 조회 전체 2초, 앱 설정 탐지 최대 5회(완료 후 0.4/0.8/1.6/3.2초), 초기 메뉴 관찰 재시도 0.25/0.75/2/5/15초, 초기 메뉴 조회 1,800노드·깊이 12·약 3초 | [a/s D-016-2] |
| 모호하면 | 추측하지 않고 실행·저장을 건너뜀 | [d/h D-016-1] |
| 사전 준비 | Option 대기(0.25초) 중 오버레이를 미리 만들고 표시 직전에 내용만 갱신(`takePreparedOverlay`) | [u/h D-063] |
| 사전 로드 | 아이콘 읽기만 앞당김. 메뉴·창은 주기적으로 미리 조회하지 않음 | [a/s D-022-3] |

## 4. 데이터 모델

### 4.1 로컬 저장 (`UserDefaults`) — [d/s D-009]

| 키 | 내용 |
|---|---|
| `launcherProfiles` | `[LauncherProfile]` — `id`, `name`, `items: [PinnedItem]` |
| `defaultProfileID`, `manualProfileID`, `followFocus` | 기본 프로필, 수동 선택, 집중 모드 추종 |
| `pinnedItems` | 프로필 도입 전 등록 목록(이관용) |
| `menuCommands` | `[MenuCommand]` (아래) |
| `menuHistoryPreferences` | 최근/자주 기간(기본 30/90일) |
| `menuCapturePreferences` | 자동 수집 on/off, 앱별 중단, 메뉴별 제외 |
| `numberShortcuts` | `NumberShortcutAssignment` (`registeredFirst` / `windowsFirst`) |
| `optionTriggerEnabled`, `optionReopenPreferences` | Option 호출 켜기, 빠른 재열기(기본 0.6초) |
| `automaticWindowCount`, `manualWindowCount` | 최근 창 개수 |
| `appearanceTheme`, `tileColors` | 테마, 섹션별 색 |
| `showAppSettingsTile` | 앱 설정 타일 표시 |
| `settingsSyncCheckpoint` | 동기화 체크포인트 |

**`PinnedItem`** — `kind`(app/folder/trash), `path`(=id), `bundleID`, `name`, `openMode`(overlay/finder) [현황]

**`MenuCommand`** [현황]
- 식별: `id`(UUID), `appID`, `appName`, `path`(전체 메뉴 경로), `pathAliases`(언어별 경로), `axIdentifier`
- 사용: `isPinned`, `isAutomatic`, `useCount`(런처 실행), `observedCount`(메뉴 막대 선택), `lastUsed`, `recentUses`(최근 3개 시각)
- 표시: `symbol`(직접 고른 SF Symbol), `resourceIcon`, `resourceBinding`, `shortcut`
- 대체: `optionAction`(Option 대체 메뉴)
- 동기화: `syncResourceIdentity`

출처: 언어별 경로·식별자로 찾기 [a/h D-031-1, a/s D-031-2], 두 횟수를 따로 저장 [u/h D-049-2], 최근 시각 3개만 저장 [d/s D-049-3]

### 4.2 파일 (`~/Library/Application Support`) — [d/s D-009]

| 위치 | 내용 | 출처 |
|---|---|---|
| 메뉴 아이콘 저장소 (`MenuIconStore`) | 앱별 파일. PDF 벡터는 그대로, 비트맵은 원래 해상도 | [d/s D-009, a/s D-051-3] |
| 동기화 저널 (`SettingsSyncCoordinator`) | 미전송 변경과 병합 상태 | [d/s D-010-2] |
| 인스턴스 잠금 (`InstanceCoordinator`) | 단일 인스턴스 판정 | [d/s D-014-2] |

### 4.3 메모리만

- 창 이력(최근 사용 순서), 아이콘 캐시, 앱 설정 탐지 성공 캐시(런처 종료까지) [현황, requirements R234]

### 4.4 iCloud (CloudKit)

| 항목 | 내용 | 출처 |
|---|---|---|
| 엔진 | 비공개 DB + `CKSyncEngine`, 레코드 타입 `TileSettings` | [d/s D-010-2] |
| 단위 | 메뉴를 속성(고정 여부, 아이콘 등)별로 나누고 속성마다 편집 시각을 저장 | [u/s D-012-3] |
| 충돌 | 실제 편집 시각 최신값. 삭제보다 늦은 편집이면 복원 | [u/h D-012-1, a/h D-012-2] |
| 대상 | 메뉴, 빠른 재열기, 숫자 조합, 최근 창 개수, 테마·색, 앱 설정 타일 표시 | [u/h D-011] |
| 로컬 유지 | 자동 수집 on/off, 사용 기록, 등록 앱, Dock, 프로필, 메뉴 식별자(`axIdentifier`) | [u/h D-011, a/s D-031-2] |
| 참여 | Mac별 토글, 기본 꺼짐. 오버레이는 네트워크를 기다리지 않음 | [a/s D-010-3, D-010-4] |

## 5. 외부 인터페이스

API나 네트워크 서비스는 없다. 외부에서 이 앱에 닿는 지점은 아래뿐이다.

| 종류 | 이름 | 용도 | 출처 |
|---|---|---|---|
| 실행 인자 | `--menu-capture-log`, `--menu-capture-structure` | 메뉴 수집 진단 로그 (진단 빌드에서만) | [d/s D-015-2] |
| 실행 인자 | `--diagnose-dock`, `--press-handoff` | Dock·Handoff 진단 (OS 업데이트 때 재검증) | [d/s D-044-2] |
| 실행 인자 | `--diagnose-window-inventory` | 창 목록 진단 | [현황] |
| 실행 인자 | `--settings`, `--show` | 설정 창 / 오버레이 열기 | [현황] |
| 실행 인자 | `--check-*`, `--render-*`, `--glass-compare` | Debug 검증·미리보기 렌더 | [a/s D-028-2] |
| 빌드 환경변수 | `TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS`, `TILE_LAUNCHER_PROFILE_DIAGNOSTICS` (0/1) | 진단 코드 넣기/빼기. 정식은 둘 다 0 | [u/h D-029-1, d/s D-029-2] |
| App Intent | `LauncherFocusIntent` (`SetFocusFilterIntent`) | 집중 모드 필터에서 프로필 지정 | [d/s D-059-2] |
| 로그 | 진단 JSONL: 임시 폴더, 0600 권한, 4~32MiB 상한, 메뉴 이름·창 제목·입력 미기록 | [d/s D-015-1, D-015-2] |

## 6. 주요 동작의 구현

| 동작 | 구현 | 출처 |
|---|---|---|
| 호출 | `HoldMonitor`: 좌/우 Option 단독 250ms, 다른 키면 취소 | [a/s D-032-2] |
| 실행 후 닫힘 | 모든 실행은 `performImmediately(_:_:)` 한 곳을 지난다. 종류는 셋: `.run`(앱·창·메뉴·앱 설정·Handoff·파일 — 고정이면 닫고 아니면 유지), `.leave`(Finder 폴더·휴지통·권한 — 항상 닫음), `.quit`(창 없는 앱 종료 — 유지하고 고정). 판정은 `OverlayPresentation.closesAfterAction(_:)`(DeckCore, 단위 테스트 대상) | [u/h D-034-3, D-066-1, u/s D-043-2], 방법은 [d/s Phase 5 구현] |
| ⌥+숫자 | `selectNumber`가 클릭과 같은 `select(...)`를 바로 부른다. Option을 뗄 때 실행하던 대기칸(`pendingAction`, `presentation.selection`)은 없앴다. 오버레이가 남으면 0.45초 실행 표시(`showExecution`)를 보여준다 | [u/h D-036-2], 대기칸 삭제 [u/s 2026-11-16 사용자 선택], 표시 방법 [d/s] |
| 빠른 재열기 | `OptionReopenMemory.record`: Option을 떼서(`.release`) 닫힌 Option 호출 오버레이면 실행 여부와 상관없이 위치를 기억 | [u/h D-037-1] |
| 위치 | `PanelLayout.calculate` → `fittingContent` → `centered(on:)`. Option을 누른 순간 좌표를 저장해 사용. 화면 여백 24pt | [u/h D-033-2, D-033-3] |
| 크기 | 기준 패널 1120×840(최소 512×420), 간격 8pt. `preferredScale = 1.4`는 타일에만, 간격은 1.3배에서 멈춤 | [a/s D-045-3, u/h D-045-2] |
| 최근 창 | `WindowTracker` + `DesktopWindows`: AX 창 목록과 WindowServer 창 ID를 연결, Space 판별 | [d/s D-008] |
| 최근 창 배치 | `TileArrangement`: 데스크탑 위치로 크기, 앱 첫 등장으로 색 | [a/h D-042-1] |
| 메뉴 수집 | `MenuUsageMonitor`: 전경 앱 하나에만 AX 옵저버. 메뉴 항목 위 마우스 해제·Enter만 기록. Help 결과는 해제 확정 뒤 별도 큐에서 실제 메뉴 경로로 연결(`MenuHelpDeferredResolver`) | [d/s D-047-2] |
| 메뉴 실행 | 선택 당시 앱 ID를 대조한 뒤 활성화하고 `AXPress` | [d/h D-050-1, d/s D-050-2] |
| Option 대체 메뉴 | 열린 메뉴의 AX 관계(AXPrimary)로만 짝을 지음 | [d/s D-053-3] |
| 앱 설정 타일 | ⌘,·설정 이름 매칭, 3경로 경쟁, 최대 5회 | [a/s D-054-4] |
| Handoff | 오버레이 표시 중, 이전 조회 완료 후 0.4초 뒤 다시 조회 | [d/s D-044-2] |
| 드래그 | 배경은 0px 문턱, 타일은 7물리픽셀 문턱으로 `setFrameOrigin` 직접 이동. 입력 도중 창 속성을 바꾸지 않음 | [d/s D-065-4, u/s D-065-3] |
| 피드백 | 원본 위에 반사·테두리·눌림 강조, 실제 모양(원형·Option 코너) 마스크. 입력 영역(사각)과 분리 | [d/s D-061-3] |
| 색 | 기본 메뉴 클래식 초록/유리 노랑, 최근 창 파랑, 등록 보라. 흰색 혼합 클래식 0.50 / 유리 0.76 | [d/s D-060-3] |
| 설정 편집 | 탭별 편집본(draft) 후 저장 시 병합 (`SettingsDraftMerge`) | [d/s D-030] |
| 단일 인스턴스 | 정상 종료 요청, 15초 대기, 강제 종료 안 함 | [d/s D-014-2] |
| Dock 가져오기 | Finder → 고정 앱 → 폴더 → 휴지통. 최근 앱·웹 링크·문서 제외. Dock 수정 안 함 | [d/s D-056-3] |

## 7. 빌드·테스트·배포·운영

협업 방식(대화·결정·진행·확인)은 [working-agreement.md](working-agreement.md)에, 검증 방법·추적표는 [verification.md](verification.md)에 있다.

| 항목 | 방법 | 출처 |
|---|---|---|
| 빌드 위치 | iCloud 밖: 개발 `~/Library/Developer/TileLauncher/build`, Claude 실험 `~/Downloads/tempbuild` | [u/h D-020-1, d/s D-020-2] |
| 배포 빌드 | 깨끗한 Git 커밋을 독립 디렉터리로 꺼내 빌드 | [d/s D-020-2] |
| 테스트 | XCTest(`DeckCoreTests`), Debug 검증 모드(`--check-*`), 화면 밖 PNG 렌더, Python(`scripts/tests`) | [a/s D-028-2] |
| ⌥+숫자 Debug 검증 | `--check-option-hold-anchor`의 `verifyNumberExecutionForPreview`: Debug 빌드에서만 있는 `interceptRun`이 앱 실행·창 전환 대신 실행 횟수를 세고, 실제 `selectNumber` 경로를 지난다. 정식 빌드에는 없다 | 연결점 추가 [u/s 2026-11-16 사용자 선택(Codex 리뷰 ③ A안)], 방법 [d/s] |
| 화면 조작 검증 | working-agreement.md 4절 참고 | [u/s D-028-1] |
| 서명·공증 | Developer ID + Apple 공증, Keychain 프로필 재사용 | [u/h D-017-2, u/s D-074] |
| 채널 | GitHub Releases + `colah16/tap`의 `tile-launcher`(정식) / `tile-launcher@dev`(시험) | [u/h D-017-1, D-017-3] |
| 배포 게이트 | 정식은 사용자 확인 후, @dev는 확인 전에도 가능 | [u/h D-070] |
| @dev 자산 | tap `colaH16/homebrew-tap`의 `dev-builds` 브랜치에 `tile-launcher/<버전>-<빌드>/` 폴더를 새로 추가하고(기존 폴더 불변), `tile-launcher@dev` cask는 그 커밋의 raw URL을 가리킨다 | [현황] |
| Homebrew 신뢰 | Homebrew 7부터 개인 tap은 `brew trust colah16/tap`이 있어야 불러온다(사용자가 각 Mac에서 직접). 에이전트 검증은 임시 `XDG_CONFIG_HOME`으로 하고 사용자 설정을 바꾸지 않는다 | [현황], 방법 [d/s] |
| 버전 | `release/config.json`이 원본, 빌드 번호는 산출물마다 증가. patch/minor 규칙 | [u/h D-018-1, d/s D-018-2, D-018-3] |
| 노트 | 직전 공개 이후 누적, `notes-range.json`으로 검사 | [u/h D-019-1, d/s D-019-2] |
| 진단 코드 | 정식 빌드는 진단 플래그 0, 바이너리에 진단 문자열이 없는지 검사 | [u/h D-029-1, d/s D-029-2] |
| 배포 절차 문서 | `docs/release-guide.md` | [현황] |
| iCloud 충돌 사본 | `Foo 2.swift`, `test_release 2.py` 같은 사본(현재 53개)은 빌드에 넣지 않는다. 지우거나 정리할지는 사용자에게 묻는다 | [현황] |
| macOS 업그레이드 | `docs/macos-upgrade-guide.md` 절차로 Apple 지침, 비공개 함수(D-008), Dock 접근성 구조(D-044-2)를 다시 확인 | [u/h D-069] |

## 8. 알려진 차이·할 일 (TODO)

spec.md의 요구를 현재 코드가 따르지 않는 곳이다. **지금은 없다.**

### 완료 (Phase 5, 2026-11-16)

| ID | 요구 | 2.3.0까지 | 고친 방법 |
|---|---|---|---|
| TODO-001 | ⌥+숫자는 누르는 즉시 실행 [u/h D-036-2] | 숫자를 누르면 `pendingAction`에 넣고, Option을 뗄 때 `finishOptionSelection`에서 실행 | `selectNumber`가 바로 실행. 대기칸 삭제 |
| TODO-002 | 고정 상태에서 실행하면 닫힘, 창 없는 앱 종료는 예외 [u/h D-034-3] | `performImmediately(.dismissUnlessPinned)`라서 고정 중엔 안 닫힘 | `.run`은 고정이면 닫음. 종료는 `.quit` |
| TODO-003 | Option을 누르는 동안 메뉴를 실행해도 유지 [u/h D-066-1] | `performMenu`가 `.dismissUnlessPinned`라서 Option 유지 중에도 닫힘 | `performMenu`를 `.run`으로 |

세 TODO는 하나의 규칙으로 정리됐다: **Option을 누르고 있으면 즉시 실행하고 유지, 고정 상태면 즉시 실행하고 닫힘(앱 종료만 예외).** 함께 정한 것(2026-11-16 사용자 선택): Option 유지 중 Handoff·폴더 탐색 속 파일은 유지, Finder 폴더·휴지통은 닫힘. 빠른 재열기는 실행 뒤에도 켠다. 권한 요청 버튼은 spec대로 고정 상태에서도 닫는다(2.3.0은 고정 중 유지).

## 9. 열린 질문

| 항목 | 내용 |
|---|---|
| D-025 | `main.swift` 87KB 한 파일. agent-default/soft라 나누자는 제안은 가능 (지금은 제안하지 않음) |
| 설정 창 구조 | 탭 순서·권한 위치(requirements R76, R116)는 decisions에 항목이 없다. 필요하면 추가 |
