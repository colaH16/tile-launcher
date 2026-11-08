# R368 · 하위 메뉴 읽기 세부 진단 dev80

2026-11-06, Asia/Seoul. 사용자가 회사 Numbers의 dev79 로그 분석 후 세부 진단 dev 앱 제작을 승인했다.2.1.11(80)은 원인별 제품 수정이 아닌 진단 보강본이다. 기존 수집 정책/조회/한도/재시도 없음·타입/개수 검사와 불완전 목록 거부는 유지한다. 이 Mac 앱·설정과 정식2.1.10도 유지한다.

## 구현과 교차 검토

실제 기존 Claude 세션이 메뉴 진단 flag 전용 MenuHelpChildrenRead helper, resolver의 ON 연결/첫 trace 보존, logger Values와 deferred 이벤트 연결을 구현했다. Codex 서브에이전트가 실제 helper에 가짜 count/copy/decode/type 공급자를 주입하는 native 검증기를 작성했고, 독립 리뷰가 dev79 원본0f67b7d0과 호출·단락평가·반환 판정을 대조했다. 루트는 새 필드의 실제 JSON 직렬화 검사를 보완했다. 실제 Claude가 검증기를 읽기 교차 검토했고 남은 차단 이견이 없다.

분류: countError, negativeCount, countUnavailable, copyNotAttempted, copyError, missingArray, arrayDecode, countMismatch, elementType. 기록은 기존 최종 incomplete 이벤트 하나에만 추가한다. API별 실제 AXError 정수, 유효한 reported/requested/returned 개수와 첫 비AX 항목 인덱스만 넣고 도달하지 않은 단계 필드는 생략한다. 정상 zero/unsupported leaf/성공 목록은 trace를 추가하지 않는다.

새 AX 조회나 재시도/파일 IO를 읽기 중에 추가하지 않는다. 개별25ms·요청2초·3000노드/자식100/깊이12·200기록/10분/1MiB 한도는 유지한다. 제목·검색어·객체·원시값·좌표·앱 이름은 새 기록에 포함하지 않는다. 런타임 로그를 끈 dev ON 빌드에도 helper/trace CPU 비용은 남으므로 완전히 같은 타이밍이나 영향0을 주장하지 않는다.

## 검증 완료

- 고정213입력과 현재 제품 소스 SHA256 일치.
- Swift 진단ON346/일반OFF338, Python30 모두 실패0.
- actual ON helper의 실패9분기 및 정상/zero/unsupported leaf/cap+1, 조회 순서·횟수·첫 실패 뒤 중단·미도달 필드nil 검사를 통과했다. 자체 PID의 AX handle과 메모리 CFArray만 사용했으며 AX 메시지나 사용자 앱 조회는 없다.
- 실제 ledger/취소·중복·검사 중 만료 native 검사, 기존 Option 위치/빠른복원 검사, 로그 고유0600/원본보존/비동기한도·새 오류 코드/enum/scalar 직렬화·인자 누락exit2가 통과했다.
- Release OFF에서 기존 메뉴 진단/validator와 새 MenuHelpChildrenRead/Validation·childrenFailure/childrenCopyError 문자열이 제거됐다.

실제 회사 Numbers의 세부 실패 분기는 아직 새 로그를 받기 전이다. 현재는 공증 배포 앱 준비 중이며 이후 Release ON·서명/티켓/공개 자산·Homebrew 검증 영수증을 추가한다.


## 서명된 배포 앱 준비·공증 대기

소스cac49e4999c2675a5e9277d5cd3ec8063ba53592의실제ReleaseON도native분기/ledger/로그/인자누락검사와일반debug제거를통과했다. 기존DeveloperID/CloudKit프로파일로서명했고원래9파일의지문과제출전ZIP지문을보존했다. 공증제출직전인증접근실패와Mac화면잠금이확인돼잠금해제응답을기다린다. 새공증제출/원격dev80게시없음;현재dev79유지.


## 최종 공증·게시

- 사용자 잠금해제후 기존프로필 접근 회복, 신규제출 a9aff0e3-cd3a-425c-aed5-c500a8e916d6 Accepted. 동일ID 조회로 티켓 첨부/검증을 완료했다.
- source cac49e4999c2675a5e9277d5cd3ec8063ba53592,213검증입력 일치. 원래서명9파일 hash/mode 동일, Contents/CodeResources만추가. 재빌드·재서명 없이 게시.
- ZIP 3,182,522bytes, SHA256850374a79e0e70ada11f04b159825094dbda3dddce1d2e90c2330da87e035d88.
- dev-builds 138065d014022989080d2e1d4ef4959129200e99, tile-launcher/2.1.11-80 신규10파일. 이전79/자산은불변.
- tap main ad272b98a39701814e3b3f5ede856c938a2349f2, devblob d41e79ccd11a93a61cabc1c21d4854ea18b5c0e4. CSV2.1.11,80·불변URL·SHA일치. 정식blob24662e5e와최신정식v2.1.10/앱main17f3f615보존.
- 공개3자산 인증없는재다운로드 hash/버전/BuildID/source/DeveloperID·CloudKit/번들트리·stapler·Gatekeeper통과. Homebrew audit/style/fetch exit0.
- 독립 로컬 감사가source.bundle prerequisite17f3/headcac49e49·실제patch와기본diff·9파일/티켓과ZIP3자산연결을대조했고차단결함없음.
- 이 Mac 앱을교체하거나재시작하지않았다. 최종관측설치79이며, 이번마무리에서기존78지문이유지됐다고확대하지않는다.

[공개 진단 안내](https://github.com/colaH16/homebrew-tap/blob/138065d014022989080d2e1d4ef4959129200e99/tile-launcher/2.1.11-80/diagnostic-guide.md).80도기본실행은진단로그꺼짐이다.정상종료후open -g로Caskroom2.1.11,80/Tile Launcher.app에--args --menu-capture-log를주어새실행한다.회사Numbers실패검색결과를1회클릭한새로그가다음관측대상이다.
