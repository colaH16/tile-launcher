# 집중 모드 프로필 진단 dev84 구현·검증 기록

기준일: 2026-11-08 (Asia/Seoul). **최종 회귀 검증·빌드·Developer ID/CloudKit 서명·Apple 공증·독립 감사·@dev 게시를 완료했다. 현재 사용자 회사 Mac 업데이트·정상 재실행 답변 대기이며 실제 회사 재현·원인 수정 완료 보고가 아니다.**

## 요청과 현재 범위

R385 사용자는 회사 Mac에서 macOS 집중 모드를 Work/예배로 바꿔도 런처가 오마로 열린다고 보고했다. 런처의 직접 프로필 선택 실패로 가정하지 않았다. R386에서 ‘집중 모드 필터에 따라 프로필 자동 선택’이 켜져 있음을 확인해, 기존 조건부 요청에 따른 검증용 2.2.0(84)을 준비한다. 집 Mac은 기본 프로필만 있으므로 회사 상태를 재현한 것으로 주장하지 않는다. 1차 소스 조사는 [집중 모드 프로필 조사](focus-profile-investigation-20261108.md)를 따른다.

## 진단 목표와 제품 동작

현재 필터 조회 요청·콜백, Intent 수신, 로컬 프로필 ID 유효 여부, 자동 선택 설정, 새 표시/기존 화면 재사용 시 선택과 실제 표시의 관계를 제한된 메타데이터로 구분한다. 새로 여는 경로의 현재 ID 반영과 열린 presentation.profile 미갱신 경로를 실제 회사 현상과 구분한다. 진단을 이유로 제품의 프로필 선택 결과나 열린 화면 갱신 정책을 바꾸지 않는다. 회사 원인은 진단 결과 전에는 미확정이다.

실제 생산 구현과 privacy/정책 독립 검토는 기존 담당 에이전트들이 진행하며 이 문서 담당은 제품 파일을 수정하지 않는다. 합의한 관찰 전용 조회 정책은 진단 시작 시 한 번과 이후 show-entry 요청이며, 세션 전체 최대 12회·프로세스 전체 동시 한 건이다. 2초 timeout은 결과를 분류할 뿐 실제 OS 조회를 취소하거나 진행 중 슬롯을 해제하지 않는다. 이전 세션의 뒤늦은 완료는 새 로그에 섞지 않는다. 주기 폴링이나 제품 상태 대입을 추가하지 않는다. 실제 코드·API·로그 형식과 최종 회귀 검사를 대조했고 한도와 생산 정책을 유지했다.

## 빌드와 배포 정책

- 버전 2.2.0, 빌드 84. `TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS=0`, `TILE_LAUNCHER_PROFILE_DIAGNOSTICS=1`.
- `diagnostics=true`, `profile_diagnostics=true`, `menu_diagnostics=false`, `stable_eligible=false`, `production_publish_allowed=false`를 소스·최종 산출물 영수증에 함께 기록한다.
- 기본 실행은 기록하지 않으며 사용자가 ‘프로필 진단 시작’ 메뉴로 고른 세션만 기록한다. 별도 CLI 인자를 요구하지 않는다.
- 실제 helper `ProfileDiagnostics.swift`의 `ProfileDiagnosticsMenuController` 메뉴는 ‘프로필 진단 시작’, ‘프로필 진단 중지’, ‘프로필 진단 로그 폴더 열기’로 확인했다. 진단 중에는 시작을 비활성화하고 종료/한도 도달 뒤 중지는 비활성화한다. 안내는 메뉴바 아이콘 우클릭으로 접근하며 한도가 끝났으면 중지를 건너뛰고 폴더를 연다.
- 실제 helper는 `FileManager.default.temporaryDirectory/TileLauncher-ProfileDiagnostics/` 아래 새 폴더0700·파일0600을 만들고 `profile-diagnostics-XXXXXX` 고유 JSONL 파일(확장자 없음)을 사용한다. 최대600초/1MiB/200건(시작 포함)/pending32이며 기존 로그를 덮어쓰지 않는다. 중지는 신규 기록을 막고 수락한 쓰기를 최대1초 기다리며 폴더 열기는 앱의 메뉴에서 Finder를 연다. 이름·UUID·해시·항목 목록·원시 오류문은 직렬화하지 않으며 자동 전송이 없다. 권한·한도·중지·세션 재시작·지연 완료·동시 조회 gate의 합성 native 검증을 완료했다. 실제 회사 재현 성공이나 원인 확정은 아직 아니다.
- 기존 Developer ID/CloudKit 서명·공증 후 @dev에만 게시하는 계획이다. 인증 재등록이나 사용자 앱 강제 종료는 준비 절차에 포함하지 않는다.
- 정식 2.1.10과 기존 83 불변 자산은 보존한다. 84 진단 포함 앱을 정식 GitHub 또는 일반 cask로 자동 승격하지 않는다. 이후 공개는 v2.2.0 단일 릴리스에 기존 2.1.11 두 수정과 2.2.0 메뉴 경로 기능을 구분해 유지한다.

## 검증·산출물 상태

최종 소스는 cdf17e95a992decd4bc1a8f244a7874692ba3e21(부모 fc5edd63)이다. frozen source의 문서·코드는 검증 이후 추가 편집하지 않는다. 실제 결과는 외부 source/signed/final 영수증과 이 원본 workspace 보고서에 연결한다. 원본 정식 노트 초안은 유지하고 활성 84 노트는 진단 시험으로 구분한다.

### 검증 시도와 조정

1. 첫 시도(`/private/tmp/tile-launcher-r386-validation-20261108`)는 컴파일 후 기존 MenuDiagnosticsBuildTests의 부모 PROFILE1 환경 상속으로 Xswiftc 개수 기대 세 assertion이 실패했다. 테스트가 두 플래그 환경을 명시하고 조합을 검사하도록 보완했다.
2. 두 번째(`/private/tmp/tile-launcher-r386-validation-20261108-attempt2`)는 pending1 합성 fixture의 writer 배출/Task 순서 가정으로 native 검사에 실패했다. fixture의 명시적 writer 동기화 한 줄을 추가했고 생산 guard는 보존했다. 예약 시점 이벤트 이름을 observerRequested로 명확히 했으며 정책 변경은 없다.
3. 최종 attempt3(`/private/tmp/tile-launcher-r386-validation-20261108-attempt3`)은319입력/25단계를 완료하고 sourceUnchanged=true, status=passed다. PROFILE ON/MENU OFF344, 양쪽 OFF344, 양쪽 ON352 Swift 검사와 Python30, native 프로필/Option/Help/caption, Release OFF 진단·Debug 제거가 통과했다. Usage 입력 누락의 기대 exit2도 정상 결과로 검증했다. 앞선 실패 기록은 삭제하지 않았다.

출처: 외부 source-receipt.json의 validation 및 attempt3의 receipt.json/source-manifest.json/logs. 원본 미러는223파일(기존221+새2)의 사전 기준본 일치와 사후 bytes/mode 일치를 확인했고 외부 workspace-mirror-receipt.json에 보존했다.

### 빌드·서명·공증 진행

실제 Release PROFILE1/MENU0 빌드·기존 Developer ID/CloudKit 서명·verify와 아홉 파일 지문/참조 보관을 완료했다. 서명본과 source.bundle·검증 증거를 영구 Library 릴리스 영역에 보존했다. 실제 출하 앱이나 macOS Focus 진단 CLI는 실행하지 않았다.

공증 직전 기존 tile-launcher-notary 접근 첫 시도는 exit69로 중단돼 그때 Apple 제출은0건이었다. 당시 screen_locked=true/keychain_unlocked=true를 구분했다. 사용자가 화면 잠금을 해제했다고 답해 coordinator의 notarize만 동일 서명 체크포인트에서 재개 중이다. 재빌드·재서명·새 인증 등록은 하지 않는다. 현재 사용자 추가 응답 대기가 아니다. Apple Accepted·티켓·최종 외부 감사·익명3자산·Brew·@dev 게시 결과는 완료 뒤 갱신한다.


## 공증·최종 독립 감사 완료

같은 서명본이 Apple Accepted aa268ff8-b08c-4b05-a2f7-371489fb7799를 받았다. ZIP3,146,574bytes/SHA2566fdcb1a29ec9ffb4e0f3cabf316f5ba12c988234b62c31f662df3ab7f562b164, binary SHA75420b803a9f5b8b405d8a0eac2332d6dd73daf915ef11da085207d567d92c6c, BuildID16702eca9b46e0cb9a65e7dc2562db60c0eda570bed3dc776a5f766dd09a5bc3이다. 제출 전 ZIPbca9b779fc5680eebc7b736040a317054c84c5f5346d40c24df8b8392d0a0b96와 최종 티켓 부착 ZIP을 구분했다.

원래9파일의 SHA/mode는 모두 동일하며 Contents/CodeResources만 추가됐다. saved-reference/pre-staple 원본 tree595e2e28222384ae9325ddef99aa612f5432ef801b9095bfe9ccc4cf6f081f20, 최종tree412417340fe369b291ff9dfb96e9979a11eee17c606da793e3a78bb15f14c797가 각 영수증/manifest와 일치한다. ZIP app 파일/바이트는 최종 product app과 같고 독립 codesign strict/deep·stapler validate는 exit0이었다. 실제 앱 또는 진단 CLI를 실행하지 않았다.

출하 binary는 MENU8개/Debug6개 marker가 모두 없고 ProfileDiagnostics 및 메뉴3문구는 존재한다. source/summary/metadata/plist/config/프로필과 policy가 일치했다. 기록 API의 Encodable 값은 고정 enum·Bool·counter·시간·일치 여부이며 ID 문자열은 메모리 비교에만 사용한다. 이름·프로필 UUID·해시·앱/항목 목록·raw 오류문을 인코딩하는 필드가 없음을 소스와 native 기록 검증 범위에서 확인했다. 사용자 진단 결과는 아직 받지 않았으며 모든 개인정보 위험이 없다는 포괄적 보증으로 확대하지 않는다. 시험 노트는 원인 수정 완료가 아닌 메뉴 opt-in 진단으로 명시하고 안내의3메뉴/파일prefix/한도는 실제 코드와 일치한다.

스테이징9276cebe0dd40e969686927f26c03e2216090cc8는 부모86bdacd7 뒤 새84폴더10파일만 추가했다. 세 자산·source receipt·final summary·노트·안내가 실제 출력과 같고, source.patch는 base17f3→cdf17e95의 정확한 diff다. source.bundle은 base17f3을 요구하고 headcdf17e95를 포함하며 verify가 통과했다. 영구 Library 영역에 prepared/source.bundle/양 영수증/final summary와 새 검증 schema의 receipt/source-manifest/25개 logs·profile 합성 fixture가 보존됐다.

현재 root가 자산 원격 게시·익명3다운로드·cask 갱신을 진행한다. 이 보고서의 지금 단계는 최종 앱 감사 완료이며 @dev 게시 완료 영수증은 아직 연결하지 않았다. frozen clean source는 계속 동결한다.


## @dev 게시 완료와 다음 사용자 단계

root가 실제 게시와 Homebrew 검증을 마쳤다. 자산9276cebe0dd40e969686927f26c03e2216090cc8 / tapmainc8fe2470a03b23227b6f59815d82fb2c3421ae9d / devblobba1ecaef8dbc27f1fd5cf843e2020dce67a776c8이다. 공개3자산의 익명 해시·앱 tree·서명·CloudKit profile·티켓·Gatekeeper 검증과 brew tap-refresh/audit/style/fetch가 모두 exit0이었다. 근거는 `/private/tmp/tile-launcher-r386-publication-20261108/work/publication-receipt.json` 및 `brew-receipt.json`이다. 정식v2.1.10/ID427433440·앱main17f3·정식cask24662e5e는 그대로다.

현재 개발·Claude·공증·게시 작업이나 잠금/로그인 답변 대기가 아니다. 회사 Mac에서 앱 정상 종료 → brew update/upgrade @dev → 새 실행을 마쳤다는 답변을 기다린다. 완료 답변 뒤 별도 단계로 우클릭 메뉴 진단 시작과 집중 모드 재현을 안내한다. 기본 기록은 꺼져 있으며 CLI 옵션 없이 메뉴 opt-in을 사용한다. 선택/열린 화면 갱신 정책 변경은 없고 실제 회사 Focus 재현 성공·원인은 아직 확인하지 않았다. 진단84는 정식 승격하지 않는다. frozen source319입력은 계속 보존한다.
