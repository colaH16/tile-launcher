# Tile Launcher — 에이전트 지침

이 파일은 짧게 유지한다. 진행 상태·작업 로그를 여기에 쌓지 않는다. 결정은 `docs/sdd/decisions.md`, 변경 이력은 git 커밋과 `CHANGELOG.md`에 남긴다.

## 먼저 읽을 것

1. [docs/sdd/constitution.md](docs/sdd/constitution.md) — 바뀌지 않는 원칙 (user + hard)
2. [docs/sdd/working-agreement.md](docs/sdd/working-agreement.md) — 사용자와 함께 일하는 방식 (아래 "작업 약속"이 그 복사본)
3. [docs/sdd/spec.md](docs/sdd/spec.md) — 무엇을, 왜. 완료 조건(Given/When/Then)
4. [docs/sdd/plan.md](docs/sdd/plan.md) — 어떻게. 항목마다 출처 표시. 7절 빌드·배포·운영, 8절 할 일(TODO)
5. [docs/sdd/decisions.md](docs/sdd/decisions.md) — 결정 기록. 작업과 관련된 D-번호의 출처·강도를 확인한다

## 작업 약속

`docs/sdd/working-agreement.md`의 복사본이다. 바꿀 때는 그 파일을 먼저 고치고 여기도 같이 고친다. Claude Code는 `CLAUDE.md`의 `@AGENTS.md`로 이 파일을 불러온다.

- 한국어로 대화한다.
- 답할 때는 먼저 요약을 보여준다. (D-077)
- 물을 때는 답하는 데 필요한 정보(배경, 선택지, 영향)를 함께 준다. (D-078)
- 선택지가 있는 결정은 비교표(장단점, 성능, 부작용, 기능상 문제)를 먼저 보여주고, 결정은 사용자가 한다. 추천은 해도 되지만 혼자 정하고 진행하지 않는다. (D-080)
- 사용자가 정한 것, 수락한 제안, 에이전트의 제안·기본값, 검증 결과를 구분해서 적는다. 답이 없다고 승인으로 보지 않는다. (D-068)
- 결정이 생기면 그때 바로 `decisions.md`에 출처·강도와 함께 기록한다. 요청 로그는 쓰지 않는다. (D-067)
- 작업 전에 `decisions.md`에서 관련 결정의 출처·강도를 확인한다. hard는 바꾸기 전에 반드시 묻고, soft는 이유와 비교표를 들고 제안한 뒤 바꿀 수 있다. (D-081, D-082)
- 출처가 `agent-default`인 결정은 제약이 아니다. 더 나은 방법이 있으면 비교표와 함께 바꾸자고 제안한다. (D-083)
- 새 결정에는 반드시 출처를 적는다. 사용자가 요청하거나 고르지 않은 것을 `user`로 쓰지 않는다. (D-084)
- 사용자가 기존 결정을 바꾸자고 하면 바로 따르지 않는다. 기록된 근거와 비교해서 원래 방식이 낫다면 반대 의견을 말한다. (D-085)
- 동작을 바꾸는 변경은 `spec.md`를 먼저 고친 다음 코드를 고친다. (D-086)
- 한 단계씩 진행하고, 단계가 끝나면 사용자 지시를 기다린다. 기다릴 때는 누구를 기다리는지 말한다. (D-072)
- 작업 중 새 지시가 와도 하던 일과 충돌하지 않으면 멈추거나 바꾸지 않는다. (D-079)
- 큰 변경은 Claude와 Codex가 교차 리뷰한다. 공유 파일은 한쪽만 편집한다. (D-071)
- Computer Use처럼 화면을 조작하는 검사는 매번 먼저 묻는다. (D-028-1)
- 시험 빌드를 줄 때는 빌드 번호·변경점과 "어디를 어떻게 조작하면 어떤 결과가 정상인지"를 안내한다. (D-070)

## 현재 상태

- 최신 공개: v2.3.0(86), 2026-11-08. GitHub Release와 Homebrew 정식·`@dev`가 같은 공증 ZIP을 가리킨다. 다음 릴리스 노트 범위의 기준은 v2.3.0이다.
- TODO-001~003(Option 유지·고정 상태의 실행/닫힘 규칙)은 Phase 5(2026-11-16)에서 코드에 반영했다. 아직 빌드·배포하지 않았다. 다음은 버전(patch/minor, D-018) 결정 → 사용자 지시 시 `@dev` 빌드 → 사용자 실기 확인.
- 이 Mac에서는 iCloud 밖 clone(`~/dev/tile-launcher`)에서 작업·push하고, 끝나면 iCloud 레포에서 `git fetch`한다(D-088). iCloud 레포의 로컬 `main`·파일은 fetch로 바뀌지 않으므로 뒤처질 수 있다.

## 빌드·배포 요약

자세한 것은 plan.md 7절과 [docs/release-guide.md](docs/release-guide.md).

- iCloud 동기화 폴더(이 레포) 안에서 빌드하지 않는다. 개발 빌드는 `~/Library/Developer/TileLauncher/build`, 실험·미리보기는 `~/Downloads/tempbuild`. (D-020)
- `Foo 2.swift` 같은 iCloud 충돌 사본은 빌드에 넣지 않는다.
- 서명·공증·push·릴리스는 기존 Keychain 공증 프로필, SSH 키, `gh` 로그인을 재사용한다. (D-074)
- 정식(GitHub·`tile-launcher` cask)은 사용자가 직접 확인한 뒤에만 갱신한다. `tile-launcher@dev`는 그 전에 갱신해도 된다. (D-070)

## 지난 기록

- 2026-11-16까지의 요청 기록(`docs/request-log.md`, R01~R394), 요구사항(`docs/requirements.md`), 이전 AGENTS.md는 삭제했다. git `e99cb78`에서 볼 수 있다. decisions.md의 R번호는 그 기록을 가리킨다.
- 지난 인계 문서는 `docs/handoff/`에 있다.
