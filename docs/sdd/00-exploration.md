# Phase 0 탐색 보고서 (역 SDD화)

- 작성: 2026-11-16, Claude Code (Opus 5.5)
- 범위: 읽기만 함. 앱 코드·기존 문서·git 상태는 바꾸지 않았다. 이 파일만 새로 만들었다.
- 이 문서의 모든 판단은 **에이전트의 관찰**이다. 결정의 출처(누가 정했나)는 여기서 확정하지 않는다.

---

## 1. 기술 스택과 구조

| 항목 | 관찰 내용 | 근거 |
|---|---|---|
| 언어 | Swift (tools 6.0, language mode v5) | `Package.swift` |
| 빌드 | SwiftPM. Xcode 프로젝트 파일 없음. 패키징·서명은 셸/Python 스크립트 | `scripts/build.sh`, `scripts/release.py` |
| 최소 OS | macOS 26.0 | `Package.swift` |
| 모듈 | `DeckCore`(UI 없는 로직, 54파일) + `TileLauncher`(AppKit/SwiftUI 실행 파일, `main.swift` 87KB 포함) | `Sources/` |
| 테스트 | XCTest `DeckCoreTests` + 앱 내부 `*Validation.swift`(Debug 진단) + Python 테스트 | `Tests/`, `scripts/tests/` |
| 조건부 컴파일 | `TILE_LAUNCHER_DIAGNOSTICS`(debug) 등 진단 플래그 | `Package.swift`, `scripts/build.sh` |
| 버전 원본 | `release/config.json` | AGENTS.md 버전 규칙 |
| 배포 | Developer ID 서명 + Apple 공증, GitHub Releases, Homebrew tap(정식/`@dev`) | `docs/release-guide.md`, CHANGELOG |
| 외부 의존성 | SwiftPM 외부 패키지 없음 | `Package.swift` |
| 기타 | CloudKit(iCloud) 설정 동기화, 접근성(AX) API, 일부 비공개 API(Space/CGS) 사용 흔적 | 파일명, AGENTS.md |

## 2. 기존 문서 목록 (총 약 2.6MB)

| 분류 | 파일 | 크기 | 메모 |
|---|---|---|---|
| 에이전트 지침 | `AGENTS.md` | 202KB | 지침 + 진행 상태 로그가 섞여 있음. 상단 대부분이 R343~R394 상태 기록 |
| 에이전트 지침(상위) | `../../AGENTS.md` (개인 PC) | - | ChatGPT 프로젝트 컨텍스트. 이 앱과 무관한 GPU/PUBG 내용. 범위 밖 |
| 요청 기록 | `docs/request-log.md` | 607KB | R01~R394. 첫머리에 "사용자 발언의 요약이며 원문 전사가 아님"이라고 명시 |
| 요구사항 | `docs/requirements.md` | 172KB | 현재 구현 기준. request-log와 짝 |
| 검증 기록 | `docs/validation.md` | 196KB | 빌드별 검증 결과 |
| 변경 이력 | `CHANGELOG.md` | 98KB | 버전별 |
| 설계·근거 | `docs/interaction-design.md`, `menu-observation-design.md`, `chrome-proposal.md`, `tile-meaning-comparison.md`, `overlay-height-comparison.md`, `application-launch-feedback.md` | 각 3~13KB | 결정 근거 후보가 가장 많은 곳 |
| OS 대응 | `docs/macos-upgrade-guide.md` | 96KB | 디자인·OS 업그레이드 절차 |
| 진단 | `docs/focus-diagnostics.md`, `space-transition-diagnostics.md`, `app-settings-diagnostics.md` | - | |
| 시험 안내 | `docs/1.9.6-test-guide.md`, `docs/app-settings-*-guide.md` (4개) | - | 일회성 시험 안내 |
| 운영·배포 | `docs/release-guide.md`, `docs/installation.md`, `release/` (notes, drafts, history 19개) | - | |
| 리뷰 | `docs/reviews/*.md` 64개 + `evidence/`(gitignore, Claude 리뷰 원문 다수) | - | 버전별 리뷰·진단 |
| 인계 | `HOME-HANDOFF-MENUBAR.md`, `HANDOFF-reverse-sdd.md` | - | 둘 다 untracked |
| 기타 | `README.md`, `Resources/Brand/README.md`, `tools/*/README.md` 4개 | - | |

## 3. git 히스토리

- 커밋 235개, 2026-10-12 ~ 2026-10-29. HEAD = `17f3f61` (2.1.10 기록).
- 작성자: `colaH16` 대부분, `Tile Launcher Local Build` 4개(10-28, 메뉴바 2.1.9 작업).
- 커밋 메시지는 대부분 "무엇을 했나"이고 "누가 왜 정했나"는 거의 없다. 다만 `Record approval ...`, `user-confirmed ...`, `user validation ...` 같은 메시지가 승인 흔적으로 쓸 만하다.
- 2.2.0 ~ 2.3.0(10-29 이후) 작업은 이 레포의 커밋에 없다. AGENTS.md에 따르면 `/private/tmp`의 별도 clean 소스에서 커밋(`9302353`, `e253637`, `7af3fdea`)한 뒤 이 폴더에는 파일만 반영했다.

## 4. 출처 판단용 세션 기록

이 앱의 주 개발 에이전트는 **Codex(GPT-6)**였다. Claude는 리뷰어·부분 구현자로 참여했다. 그래서 Codex 기록이 핵심 증거다.

| 기록 | 위치 | 기간 | 사용자 발화 | 증거 등급 |
|---|---|---|---|---|
| Codex 메인 스레드 | `~/.codex/sessions/2026/10/12/rollout-…ef84fe97ea6c*.jsonl.zst` (2개 파일) | 10-12 ~ 10-28 | 약 573건(시스템 주입 제외) | **1차** (사용자 원문) |
| Codex 기타 user 스레드 | `…/2026/10/18/…01a14f26…` | 10-18 | 3건 | 1차, 이 앱과 무관(원격 세션 요청) |
| Codex guardian_review | 같은 cwd의 111개 세션 | 10-12 ~ 11-08 | (없음) | **제외**. "user" 역할이지만 실제로는 에이전트가 만든 검토 입력 |
| Claude Desktop 세션 `0b4cd296` | `~/.claude/projects/-Users-cola-…-macos-tile-launcher/` | 10-15 | 25건 | 1차 |
| Claude Remote Control `2ccb2d5a`, `36fa9eb8` | 같은 폴더 | 10-18 ~ 10-27 | 46건 | 혼합. 첫 프롬프트는 Codex가 작성, 이후 사용자 직접 입력이 섞였을 수 있어 건별 확인 필요 |
| Claude `sdk-cli` 세션 6개 | 같은 폴더 | 10-18 | 각 1건 | **2차**. Codex가 Claude에게 보낸 프롬프트. "User explicitly…"라고 쓰여 있어도 사용자 원문이 아님 |
| `docs/request-log.md` | 레포 | 10-12 ~ 11-08 | R01~R394 | **2차**. 에이전트가 쓴 요약 |

형식 메모:
- Codex: `.jsonl.zst`(zstd 압축). `session_meta.thread_source`가 `user`인 스레드만 사용자 대화. 사용자 발화는 `response_item / message / role=user` 중 `<environment_context>` 등 주입 블록을 뺀 것.
- Claude: `type=user` 중 `tool_result`가 아닌 것. `entrypoint`로 `claude-desktop`/`cli`(사람)와 `sdk-cli`(다른 에이전트가 호출) 구분.

**빈 구간과 보충**: 10-28 ~ 11-08 (R344~R394: 메뉴바 좌클릭 2.1.9, 커서 중심 배치 2.1.10, 메뉴 경로 UI 2.2.0, 기본 프로필 2.3.0 등)의 Codex 사용자 스레드는 이 Mac(회사)에 없었다. 사용자 결정(2026-11-16, "가져올게")에 따라 집 Mac 기록을 받아 레포 밖 `~/Downloads/sdd-evidence/`에 풀었다.

| 기록 (집 Mac) | 기간 | 사용자 발화 | 비고 |
|---|---|---|---|
| Codex `01a18022` (HOME-HANDOFF에서 시작한 메인 스레드) | 10-28 ~ 11-08 | 101건 | 1차. 빈 구간을 덮음 |
| Codex `01a144cf` | 10-16 ~ 10-17 | 51건 | 1차. 집에서 한 드래그·공증 작업 |
| Codex `01a1ae69`, `01a1ae88`, `01a1ae9b`, `01a1af24` | 11-06 | 24건 | 1차. @dev 채널 등 곁가지 스레드 |
| Codex 기타 3개 (브랜드, Spark 메일, SilverBullet) | - | - | 이 앱과 무관. 제외 |
| Codex guardian_review 74개 | - | - | 제외 |
| Claude `24d0061b` | 10-28 ~ 11-08 | 63건 | 혼합(`cli` + `sdk-cli`). 대부분 Codex가 보낸 프롬프트라 건별 확인 필요 |

이제 10-12 ~ 11-08 전 구간에 1차 증거(사용자 원문)가 있다. request-log는 원문과 대조하는 보조 자료로 쓴다.

### 추출 가능성 표본 (키워드 검색)

| 결정 후보 | 사용자 원문에서 찾은 것 | 잠정 관찰 |
|---|---|---|
| 버전 규칙(패치/마이너, 서명 시 1.0.0) | 10-13 "버그 고친것만 패치버전, 기능추가나 기능 변경은 마이너 버전 … 개발자 서명 완료 되면 1.0.0" | 사용자 원문 있음 |
| 배포 채널(App Store 보류, brew) | 10-12 "기능 제한 없으면 앱스토어에도 … 나중에 brew로", 10-27 "brew tap 만들어서" | 사용자 원문 있음 |
| 언어·프레임워크(Swift/AppKit/SwiftUI) | 10-12 "xcode가 없긴 한데. 설치할까? 필요해?" 정도. Swift·SwiftUI·AppKit을 고른 발화는 없음 | 사용자가 고른 흔적 없음 |
| iCloud 빌드 전달 중단 | 10-27 "이제 icloud엔 올리지 마" | 사용자 원문 있음 |

→ 원문 근거가 있는 결정과 없는 결정이 실제로 갈린다. 다만 출처는 Phase 2에서 사용자가 확정한다.

## 5. 작업 전에 알아야 할 문제

1. **iCloud 파일 내려받기 지연**: 레포가 iCloud Drive(Desktop 동기화)에 있고 문서·소스 대부분이 `dataless`(내려받지 않은 상태)다. 파일 읽기와 `git status`가 수십 초씩 걸리거나 `read error … Operation canceled`로 실패한다. 이미 메모리에 있는 원칙(빌드는 `~/Downloads/tempbuild`)과 같은 이유다.
2. **iCloud 충돌 사본**: `Foo 2.swift`, `test_release 2.py`, `release/history/v0.16.3 2.md`, 확장자 없는 `release/history/v0.16.3` 등 사본이 많다(untracked 108개 중 상당수). AGENTS.md는 이를 "보존만, 빌드 혼입 금지"로 다룬다. 이번 작업에서도 건드리지 않는다.
3. **작업 트리 ≠ 로컬 HEAD**: 앱 코드 23개 파일이 수정된 상태(` M`)이고 새 파일도 다수(`??`)다. 원인은 로컬 git이 GitHub보다 뒤처진 것이다(6절). 그래서 로컬 HEAD 기준 `git diff`로는 미수정 여부를 확인할 수 없고, 6절의 기준선(`e99cb78`)을 쓴다.
4. **오래된 `.git/index.lock`** (11-06, 0바이트): git 쓰기 작업이 막힐 수 있다. 이번 Phase에서는 기록만 하고 건드리지 않았다.
5. **AGENTS.md 자체가 이번 작업의 대상**: "사용자 최신 진행 지침 (2026-11-08)" 절은 사용자가 말했다고 기록돼 있지만, 문서는 에이전트가 썼다. 이 절의 지침(서브에이전트 최대 활용 등)이 바로 "에이전트가 쓴 문서를 다음 에이전트가 사용자 규칙으로 오인"하는 구조의 예다. Phase 1에서 이 절도 결정 항목으로 뽑는다.

## 6. Phase 0에서 사용자가 정한 것 (2026-11-16)

| # | 결정 | 사용자 선택 | 결과 |
|---|---|---|---|
| 1 | 집 Mac Codex 기록(10-28 ~ 11-08)을 가져올지 | 가져온다 | 4절 보충 표. 원본 tar는 사용자 요청으로 바탕화면에서 휴지통으로 옮김 |
| 2 | "앱 코드 미수정" 확인 기준선 | GitHub 기록을 가져와 기준으로 삼는다 (비교안: 해시 목록 / 로컬 커밋 / fetch) | 아래 |

### 기준선: `e99cb78` (GitHub `main`, 2.3.0 공개 기록 커밋)

- `git fetch origin --tags`만 실행. 로컬 `main`(`17f3f61`)과 작업 트리 파일은 바꾸지 않았다. 원격 추적 기록(`origin/main`)과 태그 v2.1.7·v2.1.8·v2.1.9·v2.3.0이 추가됐다.
- 로컬 `main`은 GitHub보다 커밋 11개 뒤처져 있다(`08ca97d` 2.1.11 시험판 ~ `e99cb78`). 이 11개 커밋도 Phase 1의 결정 흔적 자료로 쓴다. 로컬 `main`을 동기화할지는 SDD 작업과 별개로 나중에 정할 일이다.
- 대상 경로 `Sources Tests Package.swift LICENSE scripts release Resources tools`의 디스크 파일을 `e99cb78`과 blob 해시로 비교했다(`git hash-object`, 쓰기 없음).
  - 추적 파일 246개 중 245개 일치, 디스크에만 있거나 없는 파일 0개. iCloud 충돌 사본 53개는 비교에서 제외.
  - 다른 파일 1개: `release/drafts/2.3.0/README.md`. 로컬이 R394 이전 초안이다. 앱 코드가 아니라 릴리스 초안 문서다.
  - 결론: **앱 코드(`Sources`, `Tests`, `Package.swift`, `scripts`, `Resources`, `tools`)는 `e99cb78`과 동일하다.**
- Phase 3이 끝나면 같은 비교를 다시 돌려, 위 1개 파일 외에 차이가 없으면 "앱 코드 미수정"으로 판정한다.

## 부록: 증거 추출본

세션 기록에서 뽑은 사용자 발화 추출본은 Claude 세션의 임시 폴더에만 있었고 레포에는 넣지 않았다(개인 대화 포함). 다시 필요하면 `~/.codex/sessions`, `~/.claude/projects`, 집 Mac 기록 사본(`~/Downloads/sdd-evidence/`)에서 같은 방법(4절 "형식 메모")으로 뽑는다.
