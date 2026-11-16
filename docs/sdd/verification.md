# Tile Launcher 검증 (Verification) — 무엇으로, 어떻게 확인하나

- 작성: 2026-11-16 (Phase 5). 기준 코드: GitHub `main` `88a65a2` 이후 작업 트리
- 요구는 [spec.md](spec.md), 구현은 [plan.md](plan.md), 결정의 근거는 [decisions.md](decisions.md)에 있다.
- **검증 방법은 이 문서가 원본이다(B).** 실제 확인 내용은 테스트 코드가 원본이고, 이 문서에는 규칙과 추적표만 둔다(C). [a/s D-089]
- 꼬리표 형식은 spec.md와 같다: `[u|a|d/h|s D-번호]`. 결정이 아니라 코드·문서에서 읽은 사실은 `[현황]`으로 표시했다.

---

## 1. 검증 전략

### 1.1 층별 도구

| 층 | 도구 | 무엇을 확인하나 | 화면 조작 | 출처 |
|---|---|---|---|---|
| 1. 단위 | XCTest `Tests/DeckCoreTests` | UI 없는 규칙: 닫힘 규칙, 배치 계산, 메뉴 수집·기록 정책, 프로필 선택, 동기화 병합 | 없음 | [a/s D-028-2, d/s D-023] |
| 2. 앱 내부 Debug 검증 | Debug 빌드의 `--check-*` 실행 인자 (예: `--check-option-hold-anchor`) | 앱 쪽 연결: 합성 키 입력·화면 밖 패널로 Option 홀드, 고정, ⌥+숫자, 빠른 재열기. 실제 앱 실행·창 전환은 가로챔(`interceptRun`) | 없음 (화면 밖) | [a/s D-028-2], 연결점 [u/s 2026-11-16 사용자 선택] |
| 3. 화면 밖 렌더 | `scripts/preview.sh` (`--render-previews`) | 모양: PNG로 그린 오버레이·설정 창 | 없음 | [a/s D-028-2] |
| 4. 스크립트 | Python `scripts/tests` | 릴리스 스크립트·노트 범위 | 없음 | [a/s D-028-2] |
| 5. 교차 리뷰 | 다른 모델(Claude ↔ Codex)이 읽기 전용으로 검토 | 빠진 경로·회귀·문서 불일치. 합의는 검증 완료가 아니다 | 없음 | [u/h D-071] |
| 6. 사용자 실기 | 시험 빌드(`@dev`)를 사용자가 직접 조작 | 실제 접근성(AX)·다른 앱·데스크탑(Space)·집중 모드·iCloud·입력 장치에 기대는 동작 | 사용자 본인 | [u/h D-070] |
| (선택) Computer Use | 에이전트가 화면을 조작 | 6을 대신할 때만. **매번 먼저 묻는다.** 사용자가 Mac을 쓰는 중이면 하지 않는다 | 있음 | [u/s D-028-1] |

### 1.2 변경할 때마다 기본으로 돌릴 것

clone(D-088)의 저장소 루트에서 실행한다. 이 Mac에서는 기본 개발 도구가 Command Line Tools라 XCTest를 못 찾으므로 `DEVELOPER_DIR`로 Xcode를 지정한다 [현황, 이 Mac]. 시스템의 `xcode-select`는 바꾸지 않는다 [현황, `scripts/build.sh` 주석].

```bash
export DEVELOPER_DIR=/Applications/Develop/Xcode-beta.app/Contents/Developer
./scripts/test.sh
```

`test.sh`는 XCTest(층 1)와 Python(층 4)을 함께 돌린다 [현황].

```bash
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
F=(--disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security)
swift build "${F[@]}" && "$(swift build "${F[@]}" --show-bin-path)/TileLauncher" --check-option-hold-anchor
swift build -c release "${F[@]}"
```

- Debug 검증(층 2)은 바꾼 영역의 `--check-*`를 고른다. 오버레이 호출·닫기·숫자는 `--check-option-hold-anchor`다 [현황]. 목록은 `main.swift` 끝의 `--check-` 분기에 있다.
- Release 컴파일은 Debug 전용 코드가 빠진 상태에서도 빌드되는지 본다. 정식 바이너리에 진단 문자열이 없는지는 릴리스 절차가 검사한다 [u/h D-029-1].
- 모양이 바뀌면 화면 밖 렌더(층 3)를 추가한다 [a/s D-028-2].
- 큰 변경은 교차 리뷰(층 5)를 한다 [u/h D-071].

### 1.3 자동으로 확인할지, 사용자 실기로 확인할지

| 동작이 기대는 것 | 확인 방법 | 출처 |
|---|---|---|
| 순수 규칙·계산 (DeckCore) | 층 1 자동 | [a/s D-028-2] |
| 앱 안의 연결(입력 → 실행 → 닫힘)이지만 실제 앱·창을 건드리지 않고 가짜로 돌릴 수 있음 | 층 2 자동 | [a/s D-028-2] |
| 실제 다른 앱의 접근성(AX) 메뉴, 실제 창 전환·데스크탑 이동, 집중 모드, iCloud 동기화, 실제 키보드·트랙패드 | 층 6 사용자 실기 (+ 가능한 부분은 층 1·2) | [u/h D-070] |
| 자동으로 바꿀 수 있는데 안 한 것 | 추적표에 `미작성`으로 남긴다. "실기로 충분하다"고 넘기지 않는다 | [a/s D-089] |

화면 조작 없이 할 수 있는 검증(층 1~4)을 먼저 하고, 그다음에 사용자 실기를 요청한다 [u/s D-028-1].

### 1.4 새 테스트를 쓸 때의 규칙 (C)

- 자동 테스트(XCTest 함수, Debug 검증 함수)는 확인하는 spec 시나리오의 **AC 번호를 바로 위 `///` 주석에 적는다.** 하나가 여러 AC를 확인하면 모두 적는다. [a/s D-089]
  ```swift
  /// AC-004 AC-006 AC-007 AC-008 — spec 2절 닫히는 규칙
  func testRunKeepsHeldOverlayAndClosesPinnedOne() {
  ```
- 문서 → 코드: 아래 추적표의 테스트 이름으로 찾는다. 코드 → 문서: `grep -rn "AC-0" Tests Sources`로 찾는다.
- spec에 시나리오를 추가하면 다음 번호를 붙이고(번호는 다시 쓰지 않는다) 추적표에 행을 추가한다. 동작을 바꾸면 spec을 먼저 고친다 [a/h D-086].
- 2026-11-16 기준 AC 주석은 TODO-001~003 관련 테스트에만 달려 있다 [현황]. 나머지는 그 영역을 고칠 때 단다.

---

## 2. 추적표 (spec 시나리오 → 검증)

상태: `통과`(자동 테스트가 시나리오 전체를 확인, 마지막 실행에서 통과) / `부분`(자동 테스트가 규칙 일부만 확인, 나머지는 실기) / `실기`(사용자 확인만 가능) / `미작성`(자동으로 할 수 있는데 테스트가 없음).

- **TODO-001~003 행(★)** 은 Phase 5에서 Claude가 테스트를 쓰고 AC 주석을 단 것이다. 2026-11-16 `swift test` 351/351, `--check-option-hold-anchor` 통과.
- **나머지 행은 [현황]** 이다. 기존 테스트 이름을 보고 Claude가 대응시킨 것이라, 시나리오를 정확히 덮는지는 그 영역을 고칠 때 다시 확인한다.

| AC | 시나리오 | 자동 테스트 (층) | 수동 확인 | 상태 |
|---|---|---|---|---|
| AC-001 | Option 홀드로 열고 떼면 닫힌다 | `AppDelegate.verifyOptionHoldDismissalForPreview` (2), `OverlayPresentationTests.testClosingAndReopeningRestoresHoldBehavior` (1) | 실제 250ms 홀드로 열림 | 부분 |
| AC-002 | 대기 중 커서가 움직여도 처음 누른 자리에 연다 | `HoldAnchorValidation.verify`, `AppDelegate.verifyOptionAnchorPlacementForPreview` (2) | - | 통과 |
| AC-003 ★ | ⌥+숫자는 누르는 즉시 실행한다 | `AppDelegate.verifyNumberExecutionForPreview` (2) | 실제 앱이 그 순간 뜨는지 | 통과 (실기 남음) |
| AC-004 ★ | 고정 상태에서 실행하면 닫힌다 | `OverlayPresentationTests.testRunKeepsHeldOverlayAndClosesPinnedOne` (1), `AppDelegate.verifyClickExecutionForPreview` (2) | 최근 창 타일 클릭으로 전환·닫힘 | 부분 (클릭 → 창 전환 연결은 실기) |
| AC-005 ★ | 고정 상태에서 ⌥+숫자도 즉시 실행하고 닫힌다 | `AppDelegate.verifyNumberExecutionForPreview` (2) | - | 통과 |
| AC-006 ★ | Option을 누르고 있어도 Finder 폴더·휴지통 열기는 닫힌다 | `OverlayPresentationTests.testRunKeepsHeldOverlayAndClosesPinnedOne` (1), `AppDelegate.verifyClickExecutionForPreview` (2) | Finder 폴더 타일 클릭 | 부분 (타일 → `.leave` 연결은 코드 리뷰) |
| AC-007 ★ | 고정 상태에서도 창 없는 앱 종료는 오버레이를 닫지 않는다 | `AppDelegate.verifyClickExecutionForPreview` (2) | 실제 앱 두 개 연속 종료 | 통과 (실기 남음) |
| AC-008 ★ | Option을 누르는 동안 메뉴를 실행해도 닫히지 않는다 | `OverlayPresentationTests.testRunKeepsHeldOverlayAndClosesPinnedOne` (1) | 메뉴 타일 클릭 → 실행·유지 → Option 떼면 닫힘 | 부분 (`performMenu` 연결과 AX 실행은 실기) |
| AC-009 | 메뉴 막대 좌클릭은 고정 오버레이를 연다 | `AppDelegate.verifyStatusItemPinningForPreview` (2) | - | 통과 |
| AC-010 | 실수로 Option을 뗐다가 바로 다시 누르면 같은 자리에 연다 | `OptionReopenTests.testRepressRestoresExactPriorLocationThroughSixHundredMilliseconds` (1), `PreviewExport.verifyQuickOptionReopen` (2) | - | 통과 |
| AC-011 ★ | 실행한 뒤 Option을 떼서 닫혀도 같은 자리에 다시 연다 | `OptionReopenTests.testReleaseAfterRunningAnItemStillRestoresLocation` (1), `AppDelegate.verifyNumberExecutionForPreview` (2) | - | 통과 |
| AC-012 | 타일 위 짧은 움직임은 클릭, 긴 움직임은 드래그 | `OverlayDragMotionTests.testSevenPhysicalPixelsPreserveOriginalGrabAtBothScales` (1) | 실제 트랙패드로 5px·20px | 부분 |
| AC-013 | 프로필을 바꾸면 높이가 바뀐다 | `DesktopLayoutTests.testProfileRefittingShrinksAndGrowsWithoutRecentAreaGapOrLosingDraggedPosition` (1) | - | 통과 |
| AC-014 | 다른 데스크탑의 창도 보인다 | `DesktopLayoutTests.testCurrentIncludesActiveDesktopOnEachDisplay` (1) | 실제 데스크탑 두 개 | 부분 |
| AC-015 | 메뉴로 실행한 명령이 수집된다 | `MenuCaptureTests.testOnePhysicalSelectionIsCountedOnceEvenWithDuplicateNotifications` 외 (1) | 실제 앱 메뉴 클릭 | 부분 |
| AC-016 | Help 검색 결과 클릭도 수집된다 | `MenuHelpSearchRowTests.testNonPressableHelpRowsCaptureBothITermCommandsOnMouseRelease` (1), `--check-menu-help-deferred` (2) | 실제 Help 검색 | 부분 |
| AC-017 | 한 달에 한 번 쓰는 메뉴가 사라지지 않는다 | `MenuHistoryTests.testOldMenusRetainFivePerAppAndSixthExpiresOnlyWhenBothConditionsFail` (1) | - | 통과 |
| AC-018 | 다른 앱으로 잘못 실행하지 않는다 | 없음. 앱 ID 대조는 `main.swift` `select(menu:)`에 있음 | 고정 후 앞 앱 바꾸고 메뉴 클릭 | 미작성 |
| AC-019 | 집중 모드 필터가 없으면 기본 프로필 | `ProfileSelectionTests.testAutomaticFallbackAndManualSelectionAreIndependentRoles` (1), `--check-focus-profile-policy` (2) | 실제 집중 모드 켜고 끄기 | 부분 |
| AC-020 | 넘긴 프로필은 다음 호출에 유지되지 않는다 | `ProfileNavigationTests.testTemporaryProfileResetsWithoutUnpinningOrTouchingWindowOrderDuringUse` (1) | - | 통과 |
| AC-021 | 오프라인 편집도 실제 시각으로 합친다 | `SettingsSyncModelTests.testLaterOfflineEditRestoresDeletedMenuWithoutLosingOtherFields` (1) | 두 Mac 실제 동기화 | 부분 |
| AC-022 | 저장/취소 탭은 저장 전까지 반영되지 않는다 | `SettingsDraftMergeTests.testAppearanceKeepsUntouchedColorsAndAppliesOnlyEditedFields` (1) | 설정 → 모양에서 색 바꾸고 저장 전·후 오버레이 | 부분 |

---

## 3. 사용자 실기 확인 양식

시험 빌드를 줄 때 이 양식을 채워서 안내한다. 바뀐 부분과 영향받는 부분만 고르고, 매번 모든 기능을 확인시키지 않는다. 사용자는 코드가 아니라 UI로 확인한다. [u/h D-070]

```markdown
### 시험 빌드 <버전>(<빌드 번호>) — <채널: @dev 등>

변경점
- <사용자 말로 한 줄씩. 관련 AC 번호>

확인 (어디를 · 어떻게 조작하면 · 어떤 결과가 정상)
| # | AC | 어디서 | 어떻게 | 정상이면 |
|---|---|---|---|---|
| 1 | AC-003 | 아무 앱 위 | Option을 누른 채 2 | 2번 앱이 바로 뜨고 오버레이는 남는다 |

결과 (사용자 답을 그대로 기록. 답이 없으면 통과로 보지 않는다 [u/h D-068])
| # | 결과 | 메모 |
|---|---|---|
```

- 결과를 받으면 추적표의 `수동 확인` 칸에 해당하는 행의 상태를 고친다. [a/s D-089]
- 정식 배포는 사용자가 실기 확인을 마친 뒤에만 한다 [u/h D-070].
