# R362 · 공증 진단 dev 2.1.11(78) 게시

2026-11-06, Asia/Seoul. 사용자 요청으로 검증한 Option 최초 좌표와 opt-in 메뉴 진단을 실제 시험 앱으로 빌드하고 Homebrew dev 채널에 게시했다. 회사 Mac은 dev 채널만 유지한다. 현재 Numbers의 Help 클릭 누락 원인은 실기 진단 전이며 근본 수정 완료로 주장하지 않는다.

## 최종 상태

R362 완료(2026-11-06): 공증된진단시험2.1.11(78)/소스08ca97d7을tile-launcher@dev에게시했다. AppleAccepted제출cc8ff881-6b39-4b43-97d3-d43bfa1d34a9·티켓/Gatekeeper·공개3자산익명재다운로드해시/서명·CloudKit·진단마커검증통과. dev자산8e255517/tap mainc8de3f81, ZIP SHA256e980c490d87fff37e9451f49b526b98ecddcc4b7d7f798feae872948e82a6470. Homebrew audit/style/fetch모두exit0. 일반cask2.1.10blob24662e5e와최신정식v2.1.10/기존dev자산은보존했다. 이Mac앱교체/시작·회사Mac설치는수행하지않았다. 현재사용자의회사Mac업데이트완료응답을기다리며그다음진단실행/세동작시험을안내한다. Numbers근본수정완료를뜻하지않는다.

## 빌드·서명·공증의 연결

- 정확한 소스 커밋: 08ca97d7a5ca4a6c4dcc3b537ed4374429753e29
- 이전 공개 소스 base: 17f3f61544a18f5e1675b3aadeb4a33848020b73
- 버전/build:2.1.11/78, arm64/macOS26+, Xcode27.2/27B52. 버그/위치보완과임시진단으로patch를올렸다.
- prepare는clean임시체크아웃의git archive입력으로실행했고환경변수TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS=1을해당명령에만적용했다. normalRelease에진단이기본포함되는것은아니다.
- build-summary에diagnostics=true/channel=dev/stable_eligible=false/production_publish_allowed=false를기록했다. 기존release도구는공증된진단본의정식게시를자동차단하지않으므로이번에는draft/publish/정식태그생성을호출하지않았다.
- Developer ID 팀VV2W9U5XT3, 기존AppID/CloudKit프로파일hash de739b1356e80967dd55f28f29290c0f9d88d2b59551dffddb55bdd8d88e5939를사용했다.
- 실제서명/타임스탬프와공증프로필사전조회성공을확인한뒤신규제출1건만수행했다. 제출ID cc8ff881-6b39-4b43-97d3-d43bfa1d34a9는Accepted. 첫InProgress후같은제출을조회했고중복업로드하지않았다.
- BuildID: 5658f71a896ad46ab5008fcefda730e0c38647e83e7419bbdc5d551780b5bd0c
- 서명된실행파일 SHA256: c9ff7f20b465af52780db4a7dddbe9466d4cb36240299b13b5d179fe39f92382
- 최종번들트리 SHA256: 2c13dc45b365f8deb7707e4a6f899e6d8e9073cb4754a1476beac201d3309c99
- 기존서명파일 9개는바이트동일하고Contents/CodeResources티켓만추가됐다. 재빌드·재서명으로시험코드를바꾸지않았다.

## 공개 자산과 검증

- dev-builds 불변 커밋: 8e255517e9d4ecc3b175a4ced784dca24f71e644
- 새 폴더:tile-launcher/2.1.11-78. 이전75/76/77자산을덮어쓰지않았다.
- cask/README갱신 커밋: c8de3f81dc94804127ec29dba327c295a17e02d3
- dev cask blob: fbb6094a390e97e0f7867bff02393cfd57cb79ac
- 최종 ZIP SHA256: e980c490d87fff37e9451f49b526b98ecddcc4b7d7f798feae872948e82a6470
- release-metadata.json SHA256: 9a83810a5df278dace2cd3bd65dd2d4ec9248eac949bc9751a8cc1eb29995153
- SHA256SUMS.txt SHA256: 83840cde1da8ef0c3fc8bfe14b1e4e476738f9bdcc27cf98beaacf46dbd94bdb
- 원본세자산을익명으로재다운로드해해시일치확인. 재추출앱의DeveloperID/런타임·timestamp/CloudKit프로파일·버전/소스/BuildID/번들트리·진단인자마커·stapler·Gatekeeper를확인했다.
- Homebrew audit/style/fetch모두exit0. 일반cask blob24662e5e2edbd1e5e5a2d08f7862b4005741bca1과GitHub최신정식v2.1.10(ID427433440/게시2026-10-29T03:30:13Z)는불변이다.
- 앱저장소의원격main/정식태그/릴리스는갱신하지않았다. 진단소스는복구가능한bundle/patch와publicbase커밋으로연결했다. 이Mac의설치앱·프로세스·설정과회사Mac설치는변경하지않았다.

## 회사 Mac의 전체 시험 흐름

업데이트 → 정상종료후진단인자로새실행 → Numbers3케이스와Option위치확인 → 정상종료후로그분석이다. 사용자의단계별방식에따라대화에서는지금할업데이트단계만안내하고완료응답을기다린다.

- 첫단계:brew update 다음 brew upgrade --cask colah16/tap/tile-launcher@dev. 같은채널의기존appdir/설정을유지한다.
- 진단로그는업데이트만으로자동시작하지않는다. 다음단계에서앱정상종료후Caskroom의새버전앱symlink에--menu-capture-log를넘겨새프로세스로실행한다. 강제종료/--zap/설정초기화없음.
- 같은Numbers명령의일반메뉴클릭/Help결과클릭/HelpEnter를비교한다. 이미등록된항목은존재만으로보지않고최근순서/관찰횟수또는record로그결과를확인한다. Option감지뒤커서이동도별도확인한다.
- 고유로그는DARWIN_USER_TEMP_DIR의tile-launcher-menu-capture-*에있고최대10분/1MiB/200기록·pending한도가있다. 로그없음을미실행으로단정하지않는다. 검색어/메뉴제목/문서·창내용/키문자열/원시좌표를기록하지않고자동전송하지않는다.
- 공개[진단시험안내](https://github.com/colaH16/homebrew-tap/blob/8e255517e9d4ecc3b175a4ced784dca24f71e644/tile-launcher/2.1.11-78/diagnostic-guide.md)에전체명령을보관했다. 다음단계안내때이명령을검증해사용한다.

원본 산출물/소스bundle/서명·공증·공개다운로드·Homebrew검증 영수증은 로컬지속보관폴더와ignored evidence에보존한다. 인증비밀값/키는저장하지않는다.


## R363 사용자 시험 진행

R363 회사Mac실기/진단켜기안내(2026-11-06): 사용자가Option누름시점위치가정상이라고확인했고메뉴는여전히누락되며진단을어디서켜는지물었다. 위치변경의사용자실기성공을기록한다. 메뉴근본수정은아직이며시험본의진단은설정스위치가아닌--menu-capture-log실행인자로만켜진다. 현재사용자에게앱메뉴정상종료후Homebrew Caskroom의78번앱을진단인자로새실행하는한단계만안내하고완료응답을기다린다. 이Mac앱은조작하지않는다.

진단시작완료는미확인이며현재그응답을기다린다. 위치수정의실기확인과메뉴문제의근본수정완료를구분한다.


### R363 진단 실행 응답과 시험 단계

R363 진단 실행 완료 응답(2026-11-06): 사용자가 안내한 진단 모드 실행을 마쳤다고 보고했다. 이는사용자실행보고이며이쪽에서실제프로세스인자/로그생성을독립확인한것은아니다. 다음사용자단계는Numbers의같은실행가능한하위명령(예:PDF…)으로일반메뉴클릭→Help검색결과클릭→Help검색Enter를비교하는것이다. 부모인Export To자체처럼하위메뉴만여는항목은선택하지않는다. 내보내기완료/문서변경은필요없고대화상자는취소해도된다. 세동작완료응답을기다린뒤로그확인단계를안내한다.
