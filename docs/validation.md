# 네이티브 빌드 검증

## R170–R172 · 1.4.1 고정 여백·1.3배·등록39개

- R173 환경 정정: 실제 시험 모니터는 사용자 설명상2560×1080·HiDPI 미사용이다. 이전1440×900은 재현용 샘플이지 사용자 해상도가 아니다. `/tmp/tile-173-height-check`에서 실제 f124946/0be3ad9의 Layout/DeckContentLayout/DeckSpacing/TileArrangement를 별도 Swift 프로그램으로 컴파일했다.2560폭·가용 높이1080/1056/1020/1000/980/960에서 이전 버전의 등록 완전 행 수는2/1/1/1/1/1, 수정본은 모두3이다.1056 조건의 이전 미사용 높이는88.592pt/수정본0.136pt다. native visibleFrame 실측/사용자 화면 재현과는 구별하며 코드 계산 대조다. 앱·ZIP은 다시 만들지 않았다.

- 이전1.4.0 코드에 화면 없는 실제 NSScrollView 진단을 붙여 재현했다.1440×900 샘플의 배율1.242857/등록39개에서 document264pt인데 viewport84pt였다. 남은 높이를 정수 행 수로 내린 결과 등록 영역 아래가 빈 공간으로 남았다.2560×1440에서는298/297pt로 마지막1pt도 부족했다. 사용자 Mac의 실제 해상도를 읽은 것은 아니다. 로그/렌더는 `/tmp/tile-141-before.log`, `/tmp/tile-141-before`다.
- 기본/상한1.3배, 고정24pt 바깥/열 간 여백·제목 아래12pt·확대하지 않는 상단 높이와 물리 높이 공유를 적용했다. 최근 영역3.3줄 상한과 등록 최대3줄을 함께 배정하며 작은 화면에서 최근 최소2줄을 남긴다. 부분 행 높이를 버리지 않고 등록 목록에 쓴다. 좁은 구성/아주 작은 화면은 제한된 스크롤을 보존한다.
- 격리 `/tmp/tile-141-validation`에서 XCTest149개/Python23개 통과(`/tmp/tile-141-tests.log`).39개/다양한 화면·음수 원점/프로필 축소 후 복구/분수 높이 잔여 공간과 실제 고정 여백·격자 폭 보존을 검사했다.
- 네이티브 등록39개 렌더에서2560×1440 및1920×1080은 패널1456×999pt, viewport279/document278pt다.1440×900은 패널1392×851.36pt, viewport266/document265pt다. 세 경우 모두 처음부터39개 세 줄이 보이고 footer 위 미사용 공간은0–4.6pt다. 최초 꾸밈 샘플의 중복 path ID를 발견해39개 모두 고유 ID로 바꾸고 검사를 추가했다. 화면/사용자 앱/설정을 조작하지 않았다.
- 상단 버튼의 실제 드래그 제외 영역,149개 정책 검사, 전체 기존 오버레이/설정/큰 이력 렌더를 확인했다. 근거는 `/tmp/tile-141-previews.log` 및 registered-39-1440/1920/2560.png다. 실제 사용자 Mac의 합성/터치·키 입력 검증과 구별한다.
- 소스0be3ad9bca93150d0f76d2930246cf6c42a6f292의 독립 release 빌드·Developer ID Application Team VV2W9U5XT3 서명·실제 서명 실행 파일의 전체 비표시 검사/렌더·이후 번들 검증을 통과했다. `/tmp/tile-141-prepare.log`, `tile-141-sign.log`, `tile-141-verify.log`, `tile-141-signed-previews.log`에 기록했다. Glass 호스트의 비표시 동적 글자색과 사용자 화면 합성 색은 구별하며 목록 검증은 실제 document/viewport/위치와 고유39개 ID를 기준으로 한다.
- 원본 `/Users/cola/Library/Developer/TileLauncher/releases/v1.4.1`의 번들 SHA256은611506c5db4d2f7df63c0e5ed80e73662278fc01c891d8c827d7d522ec530e50다. ZIP2,313,630바이트, SHA2565f51feaedfc1810b8fed339089f36537eb1bc05c8051fe71d2ef88740dec176c를 저장소 상위 `Tile-Launcher-1.4.1-arm64-unnotarized.zip`에 복사·해시 확인했다. 이전 ZIP은 보존했다.
- 공증 제출·개발 Mac 앱 교체/재실행·GitHub 바이너리 공개는 하지 않았다. 설치본 Info.plist1.2.0을 읽기로 확인했다. 소스/전달 기록만 main에 푸시하며 iCloud 서버 업로드·다른 Mac 수신은 확인하지 않았다.

## R164–R169 · 1.4.0 실행 대기·설정 맞춤·Space 경로

- 동기화 폴더의 빌드 메타데이터 문제를 피하려고 동일 소스를 메타데이터 없이 `/tmp/tile-140-validation`에 복사했다. Xcode의 기본 SwiftBuild로 XCTest147개/Python 배포 검사23개를 통과했다(`/tmp/tile-140-tests.log`). 앱 실행 시작/완료/시간 초과·종료·오류와 포커스 확인·피드백 취소 정책을 포함한다.
- 실제 ApplicationLaunchMonitor에 가짜 opener/시계를 넣고 사용자 앱을 실행하지 않은 채 중복 차단, 다른 앱 접근,3초 시작 미확인, 오래된 콜백, 오류 후 재시도, 네이티브 실행 상태 전달을 검사했다. 처음에는 화면 없는 preview 프로세스도 finishedLaunching일 것이라고 잘못 가정해 검사94가 실패했다. NSApp.run을 하지 않는 실행 경로임을 확인하고 실제 상태를 따르는지 검사하도록 바로잡았다. 완료/60초 상한은 별도 정책 테스트로 확인했다.
- `/tmp/tile-140-previews`의 실제 설정 NSWindow 렌더에서 기본 콘텐츠580×918pt, 일반 document885pt/viewport886pt를 확인했다. 기본 크기에서 일반/모양은 내용이 넘치면 실패하는 검사를 통과했다. 수동 리사이즈·재열기 크기·작은 화면 제한도 검사했다. settings-native-general/appearance/menus/registered.png의 상단 시작선·좌우 여백, 일반 권한/버전, 메뉴 하단 추가·가변 목록을 직접 확인했다. 비표시 네이티브 선택 탭의 재질은 검게 나올 수 있어 실제 합성 색 검증과 구별한다.
- 짧은 설명은 크기 세 줄·색 두 줄로 항상 보인다. 펼침/스크롤을 기본 해결책으로 쓰지 않는다. 앱 실행 대기/숫자 선택 피드백, 두 테마·명암·큰/작은 화면·기존 프로필 및 최근 창 fixture를 렌더했다. `/tmp/tile-140-previews.log`와 application-launch-feedback.png/keyboard-execution-feedback.png를 확인했다.
- 실행 코드에서 직접 Space 쓰기 함수와 SLS 별칭이 제거됐는지 확인한다. 관련 외부 재현 기록과 사용자 증상은 일치하지만 개발 Mac에서 사용자 현상을 직접 재현하지 않았다. 실제 다른 Space 이동/앱별 AX 지원은 사용자 시험과 구별하며 자세한 근거는 space-transition-diagnostics.md에 있다.
- 소스 `f124946b07cec3b67ed301f6bbf48ae3871f7a3f`에서 독립 release 빌드, Developer ID Application Team VV2W9U5XT3 서명·강화된 런타임·타임스탬프·최종 ZIP 재추출 검증을 통과했다. 실제 서명 실행 파일의 비표시 검사/전체 렌더와 이후 번들 검증도 통과했다. 로그는 `/tmp/tile-140-prepare.log`, `tile-140-sign.log`, `tile-140-verify.log`, `tile-140-signed-previews.log`다. 최종 일반 화면에 버전1.4.0·빌드24가 끝까지 보인다.
- 원본은 `/Users/cola/Library/Developer/TileLauncher/releases/v1.4.0`, 번들 SHA256은 `b07f171c7e7123f34624eb8564462a81b8b8bc5ac22b2a7824a86bc124e0dd5d`다. ZIP2,308,256바이트, SHA256 `228e6e711406909f2d9f67040d4d2095a3cacce173edcfc20f3246f8d4bf52d3`를 저장소 상위 `Tile-Launcher-1.4.0-arm64-unnotarized.zip`에 임시 파일로 복사·해시 확인 후 이름을 확정했다. 기존 ZIP을 덮어쓰지 않았다.
- 공증 제출은 생략했다. 개발 Mac 설치본의 Info.plist는1.2.0이며 교체/재실행하지 않았다. GitHub 바이너리 공개도 하지 않았다. iCloud 서버 업로드 완료·다른 Mac의 수신/설치는 확인하지 않았다. 소스와 전달 기록만 기존 승인에 따라 main에 커밋·푸시한다.

## R163 · 1.3.0 위치 크기·첫 등장 색·시험 ZIP

- 동일 작업 소스를 파일 메타데이터 없이 `/tmp/tile-130-validation`에 복사해 Xcode 기본 SwiftBuild로 컴파일했다. 기존 동기화 폴더의 xctest 링크는 Swift 드라이버가 getxattr에서 대기하여 중단했으며, 임시 폴더에서는 완료됐다. 사용자 앱/시스템 빌드 서비스/동기화 설정을 변경하지 않았다.
- XCTest133개/Python23개 통과: `/tmp/tile-130-tests-isolated.log`. 새 정책 검사는 모니터 위치/음수 좌표/여러 모니터에 걸친 창·위치 미확인·비연속 반복·창 없는 앱 예외와 1.4배 실제 geometry를 다룬다. 최초 무한 CGRect 경계 검사가 실패해 isInfinite를 명시적으로 제외하고 전체 검사를 다시 통과했다.
- 실제 공유 DeckView의 화면 없는 렌더·기본/유리 테마·명암·프로필0/18/36/200·최근100개 끝 스크롤·작은 화면과 헤더 버튼 제외 영역을 통과했다. `/tmp/tile-130-previews.log`, `/tmp/tile-130-previews`. 기존 export의 delivered-121 파일명에도 이번1.3.0 코드가 들어 있으므로 과거 산출물과 혼동하지 않는다. 대표/반복 Finder의4×2 진한색/파스텔, 다른 모니터의2×2, 숨겨진 실제 창1×1과 회색 앱, 왼쪽 아래 제목을 PNG로 확인했다.
- 전체 DeckView의 scaleEffect를 없애고 실제 폰트/프레임/간격으로 그린다. 네이티브 헤더 앵커와 드래그 hitTest 검사를 통과했다. 이 결과는 사용자의 다른 Mac에서 실제 텍스트 선명도/키 입력·다중 모니터를 확인한 결과와 구별한다.
- 소스b3e4227cb9b8e13ef7503abccc4242f5abcbbcee의 독립 release 빌드·Developer ID Application Team VV2W9U5XT3 서명·강화된 런타임·타임스탬프·번들/ZIP 재추출 검증을 통과했다. 배포 실행 파일로 전체 비표시 렌더와 좌표 검사를 다시 통과했다. `/tmp/tile-130-prepare.log`, `tile-130-sign.log`, `tile-130-verify.log`, `tile-130-signed-previews.log`.
- 원본 `/Users/cola/Library/Developer/TileLauncher/releases/v1.3.0`의 앱 번들 SHA256은 `1c5031e3c0706b901b8e410c0bd321d812154b7bc3459933a637d0078b3f01a5`다. ZIP은2,250,992바이트, SHA256 `cbb5dd794a50c2d19981d3786649df1152cf2c1c8a25d24e12fd528d58ad7898`이며 저장소 상위 `Tile-Launcher-1.3.0-arm64-unnotarized.zip`에 원본 그대로 복사하고 해시를 확인했다. 기존1.2.1 ZIP은 덮어쓰지 않았다.
- 사용자 요청대로 공증 제출/티켓·공증용 Gatekeeper 통과 선언/개발 Mac 설치/GitHub 바이너리 공개를 하지 않았다. 개발 Mac Info.plist의 설치1.2.0(21)을 재확인했다. iCloud 서버 업로드 완료와 다른 Mac 수신/설치는 확인하지 않았다.

## R158 · 사용자 보고: 1.2.1 텍스트 번짐 미해결

- 사용자가 실제 앱에서 글자가 번진다고 보고했다. 소스의 DeckView.body는 논리 contentSize로 배치한 뒤 scaleEffect(scale)를 적용하며, 실제 폰트/타일 치수를 개별 확대하는 레이아웃이 아님을 확인했다. 기존 좌표·테스트·비표시 렌더 통과는 실기 선명도 통과를 의미하지 않는다.
- GroupedRecentWindows.sizes와 windowTile/DesktopWindows 색 경로, 메뉴/등록 스타일을 대조해 현재 규칙을 설명했다. 이번에는 실제 사용자 화면이나 래스터화 시점을 조사하지 않았고 코드/빌드/설치/ZIP을 변경하지 않았다. 번짐 해결을 선언하지 않는다.

## R157 · 저장소 상위 ZIP 복사

- git rev-parse --show-toplevel과 manifest의version1.2.1/signing developer-id를 확인했다. Git 저장소 부모에 Tile-Launcher-1.2.1-arm64-unnotarized.zip을 원본 그대로 복사했다. 크기2,224,935바이트, 복사 전후 SHA256은25d1c8769c8135d199beb74492b75b88a47a310edce5a0879e9367d1d7f63ffb로 원본 manifest와 같다.
- 복사 목적지는 사용자가 지정한 iCloud 동기화용 폴더이며 실제 서버 업로드나 다른 기기 수신은 검사하지 않았다. ZIP 내용 재압축·서명 변경·버전 증가·앱 설치/실행·공증 재시도·키체인 변경은 하지 않았다. 설치1.2.0/공개1.1.5는 그대로다.

## R156 · 1.2.1 실제 확대 UI와 배포 검증

- 서명 산출물: 소스fe12c66afea5c15ed0b15048dc61173eb5e888df의격리빌드/Developer ID서명/실제서명실행파일렌더통과. /tmp/tile-121-prepare.log, tile-121-sign.log, tile-121-signed-previews.log. 서명번들SHA256은290739b70c121c79bdab3b11ab25339da3754afef32a113946de0a57f83ce550, 미공증ZIP은25d1c8769c8135d199beb74492b75b88a47a310edce5a0879e9367d1d7f63ffb다. 공증 후최종해시는별도로기록한다.
- 공증은저장된tile-launcher-notary항목을찾지못해진행하지못했다. 기본경로와명시적login.keychain-db의notarytool history가같은오류다. 현재기본키체인은login.keychain-db이며잠금해제프롬프트는발생하지않았다. /tmp/tile-121-notarize.log, tile-121-notary-history.err. 비밀값조회/키체인검색목록변경은하지않았다.
- 재저장을요청한상태이며notary_id는없고notary_pending_submission=true가남았다. 인증복구후제출이력을확인하고없는경우에만플래그를해제해새제출한다. 앱1.2.1공증·설치완료로표시하지않으며디스크설치본의Info.plist는1.2.0/21임을확인했다.

- PanelLayout.scale/contentSize와 최대1.4배 계산을 추가했다. 기본 단위 정책은 보존하고 실제 호출에서 preferredScale을 사용한다. 화면 안 배율/프레임 제한, 프로필/Option 복원, 전체 목록/완전한 등록 최소 한 줄을 검사한다. UI patch1.2.1(22)이며 새로운 데스크탑별 열을 적용하지 않는다.
- native XCTest128개/Python23개 통과: /tmp/tile-121-tests.log, tile-121-python-tests.log. 추가4개 테스트는 큰 화면의 동일 논리 크기·배율, 여러 화면/음수 원점/0·18·36·200개 프로필, 프로필 축소/복원·윗변과 배율, 작은 화면 재맞춤/전체 목록 보존이다. 처음 정확한CGRect 비교가약1e-13pt 소수 오차로 실패해 좌표별0.001pt 허용으로 바로잡았고 전체 재검증을 통과했다.
- 실제NSHostingView/DeckSurfaceView를 표시하지 않은 상태에서1568×1020.6pt·배율1.4, 헤더의 실제 좌표 크기, 두34pt 버튼의1.4배 앵커, 버튼 중앙 제외/빈 헤더 드래그 hitTest와 비표시 상태를 확인했다. 실제 사용자의 마우스/키 입력을 수행하지 않았다.
- 실제 전달 기본값으로 같은23개 샘플과 두 테마/명암·작은1024×768 화면·프로필0/18/36/200·최근100개 끝 스크롤을 렌더했다. /tmp/tile-121-build.log, tile-121-previews.log. 선택 시안과 같은1.2 배치/큰 아이콘/왼쪽 아래 제목을 확인했으며 작은 유리 타일의 모서리가 제목을 자르지 않게 반지름8pt를 적용했다. 최종 서명 실행 파일에서 다시 확인한다.

## R154–R155 · 1.2 배치의 아이콘 비율·기존/확대 크기 비교

- previewStartTileLabels 기본false, MonitorGroupingPreview production=true의 공유 DeckView 경로를 사용한다.1.2의 그룹/대표 크기·번호·실시간 색 입력을 유지하고 새 라벨만비교 입력으로 적용했다. 확대안은 동일한 SwiftUI 뷰를1.4배로 렌더한 개념 시안이며 실제 패널 정책을 새로 구현한 것이 아니다.
- 대표2×2는98.4pt/아이콘58pt/제목12pt/하단·왼쪽8pt다. 메뉴 기호52pt, 등록 아이콘36pt도 확대했고 모든 제목은왼쪽 아래한 줄이다. 작은 타일은26pt 아이콘·8pt 제목/12pt 번호로 겹침을 피했다. 기존 툴팁·접근성 이름은 유지한다. 긴 제목은 한 줄 생략 표시라는 절충을 기록한다.
- 실제 AppKit.systemFont12pt medium의 ‘가나다’ 끝39.14pt/‘가나다라’ 끝49.52pt(왼쪽8포함)가정사각 중앙49.2를 감싸는 검사를 통과했다. 확대1.4배에서도 상대 비율은 같다. wide4×2나small1×1에서같은3~4글자중앙관계를 주장하지 않는다.
- native 개발 빌드4.79초와 글꼴 검사 추가 후2.23초, 전체 비표시 렌더 통과. /tmp/tile-start-scale-build.log, /tmp/tile-start-scale-previews.log. XCTest/Python을 새로 쓰거나 반복하지 않았다. PNG 헤더로두비교바탕1640×1120, 원본1120×729/1568×1021을확인했다. 바탕크기를맞춰채팅자동축소로두앱이같은크기처럼보이는문제를피했다.
- 실제 렌더에서 메뉴/최근/등록 아이콘과 하단 제목·숫자·회색/파스텔을 확인했다. PreviewIconAssets의 합성 캐시만64→256px로 늘려 확대안에서 원래 아이콘 리소스의 해상도를 사용한다. 사용자 화면/실행 목록/설정은 변경하지 않았고 설치1.2.0/공개1.1.5·버전·노트는 유지한다. 산출물은 dist/previews/20261014/overlay-start-{base,large}-{canvas,native}.png다.

## R153 · 내용에 맞춘 열 너비 비교

- DesktopColumnsPreviewData.fittingGroups는 비교용으로만 각 열의 최대 그룹 폭을 계산해2–4칸으로 제한한다. 동일한 작은 타일 세로 쌍 기준이며 회색 앱은최대3칸이다. fixedModule/preferredWidth가 없는 기존 시안/production 기본은 유지한다. 새 렌더만 fixedModule45.2와 열 간격24pt를 사용하고 제목을primary 대비로 표시한다.
- native 개발 빌드4.36초 및 최종 제목 대비 변경 후1.56초, 전체 비표시 렌더 통과. /tmp/tile-fitted-columns-build.log, /tmp/tile-fitted-columns-previews.log. 로그에서 실제 계산된[3,3,3]·폭502.80000000000007·단위45.2를 확인했다. 기존5/3/3개 그룹·6/4/5개 실제 창·회색8개 및 전체23개 인덱스 보존 검사를 통과했다.
- 실제 렌더에서 큰 아이콘/타일 크기·작은 후속/번호·파스텔과 회색·제목/그룹 간격을 유지하며 빈 열 폭만 줄어든 것을 확인했다. PNG 헤더는 이전679×677/새551×676이다. 의미 있는 세로 행수/간격 변경은 없고 출력 경계에1px 차이가 있다. 최근 영역 자체는630.4→502.8pt로약20.24% 줄었다. 결과는 dist/previews/20261014/desktop-fitted-columns-full.png다.
- 사용자 실제 목록·화면·설정은 읽거나 조작하지 않았다.2–4칸에서 모든 실제 화면·그룹 조합을 검증했다고 주장하지 않으며 채택 시 긴 헤더/빈 열/다수 후속과 열 폭 스냅샷 고정을 별도로 확인한다. XCTest/Python을 추가·반복하지 않았고 설치·공개 버전은 유지한다.

## R152 · 내부 간격·제목 시작선 정리

- 비교 입력relaxedSpacing/previewBalancedWindowLabels만 켜고 기본값false를 유지한다.4·4·3칸/630.4pt·타일/아이콘/열 간격·번호·색·샘플23개는 이전과 같다. 대표의 가변 Spacer를6pt 간격과28pt 제목2줄 자리로 대체해 제목 시작선을 맞췄다. 앱 그룹 사이20pt, 열 제목 아래16pt다.
- native 개발 빌드3.35초 및 전체 비표시 렌더 통과. /tmp/tile-spaced-icons-build.log, /tmp/tile-spaced-icons-previews.log. 상세 이미지에서 긴 Notes/한 줄 제목의 시작선과42pt 아이콘, 작은 타일/회색 앱·번호, 그룹 간격을 확인했다. 기존 모든 비교 렌더도 유지하며 XCTest/Python 반복은 하지 않았다.
- PNG 헤더를 읽어 이전679×641px/새679×677px를 확인했다. 현재 export는1× 스케일이므로 너비 유지/높이36pt 증가와 같다. 이것은 전체 펼친 상세 길이이며 production 오버레이 프레임이나 시작 크기는 바꾸지 않았다. 결과는 dist/previews/20261014/desktop-spaced-icons-full.png다.
- 실제 사용자 화면/앱 상태를 읽거나 조작하지 않았다. 다섯 앱은 이전 Mission Control에 근거한 샘플이며 현재 실제 목록의 확정 결과가 아니다. 설치1.2.0/공개1.1.5·버전·릴리스 노트는 유지한다.

## R151 · 큰 앱 아이콘 시안

- DeckView의 previewLargeWindowIcons는 기본false이며 MonitorGroupingPreview의 명시적largeIcons 입력에서만 켠다. 기존 production·이전 시안의 타일 라벨과 아이콘 크기는 유지한다. 원래 앱 실행/선택/툴팁/접근성/정상 종료 경로를 공유한다.
- 대표98.4pt 정사각에서42pt 중앙 아이콘·8pt 안쪽 여백·11pt 창 제목 최대2줄을 사용한다. 별도 앱 이름 행은 제거한다.45.2pt 작은 타일은24pt 아이콘·3pt 여백·8.5pt 제목/앱 이름1줄이고 번호는 모서리2pt 여백으로 옮겼다. 대표 번호는 기존5pt다. 아이콘/번호·제목이 겹치거나 잘리지 않는지 실제 렌더를 확인했다.
- native 개발 빌드4.19초 및 전체 비표시 --render-previews 통과. /tmp/tile-large-icons-build.log, /tmp/tile-large-icons-previews.log. desktop-large-icons-overlay/full.png에서42pt 실제 앱 아이콘, 창 이름·작은 후속/회색 앱, 동일23개/색/배치/번호를 확인했다. 새 XCTest/Python을 작성하거나 반복 실행하지 않았다.
- 사용자 작업 화면은 건드리지 않았고 이전 캡처 기반 합성 목록과 로컬 아이콘 리소스로 비교했다. 아이콘 확대가 실제 사용성을 개선했다고 측정한 결과는 아니다. 앱 버전·설치·공개 자산은 유지하며 비교 결과는 dist/previews/20261014에 로컬 보관한다.

## R150 · 4·4·3칸·대표 창2×2 비교

- MonitorGroupingPreview의 새 비교 입력squareColumnHeads만 첫 두 열을4·4칸으로 만들고 모든 앱 대표를square로 정한다. 기본값false로 R149와 기존 production 경로를 유지하며 실제 데스크탑 판정·앱 버전은 변경하지 않는다.
- native 개발 빌드2.35초와 전체 격리 렌더 통과. /tmp/tile-square-columns-build.log, /tmp/tile-square-columns-previews.log. 전체23개 인덱스 보존, 열별5/3/3그룹·6/4/5창과 회색8앱을 확인했다. 단위 테스트를 새로 작성하거나 XCTest/Python을 반복 실행하지 않았다.
- desktop-square-columns-overlay/full.png를 확인했다. 대표11개가98.4pt 정사각이고 후속4개·회색8개는45.2pt이며 wide는 없다. 열204.8/204.8/151.6pt와 간격34.6pt로 전체630.4pt를 유지한다. 첫 열 폭만 줄고 대표 높이는 같아서 이전 시안과 세로 표시량은 같다. 작은 진한색·파스텔 후속과 회색 앱, 제목/번호가 정상 표시된다.
- 출력은 desktop-square-columns-overlay-20261014.png와 desktop-square-columns-full-20261014.png로 별도 보존했다. 이전5·3·3/6·6렌더도 같은 실행에서 통과했으며 사용자 화면/설정/설치 앱은 건드리지 않았다. 실제 창 전환·권한·Aside 증상을 검사한 결과로 설명하지 않는다.

## R149 · 5·3·3칸의 세 열 비교

- DesktopColumnsPreviewData를 열 제목/칸 수/앱 그룹/회색 앱 목록으로 일반화해 이전6·6안도 보존했다. 새 안만 원래12칸의 작은 단위를 기준으로 삼고 남는 폭을 두 열 간격에 균등하게 배분한다.630.4pt에서 작은 타일45.2pt, 열258/151.6/151.6pt, 열 간격34.6pt로 합계가 일치한다.2×2는98.4pt/4×2는204.8pt이며 기존 오버레이 타일과 같은 크기다.
- 실제 RecentTileArrangement의 최소4칸 정책을 바꾸지 않고 비교 뷰 안에3칸용 동일 세로 쌍 배치를 둔다. 회색8개가3칸 안에서6개+2개로 줄바꿈하고 Claude2×2 옆에 후속1×1 두 개가 세로로 들어옴을 확인했다. 각 열의 그룹 시작은 새 행이며 다른 그룹으로 구멍을 메우지 않는다.
- 합성 모니터A/B/other/none 입력을 분리해 세 열5/3/3개 그룹, 실제 창6/4/5개 및 회색 앱8개로 전체23개 인덱스가 중복/누락 없이 보존되는 precondition을 통과했다. 첫 열만 대표wide, 둘째/셋째 대표square, 후속small이며 보이는 두 열의 작은 창도 진한색이다. 번호는 왼쪽 열부터 각 열 위→아래다.
- native 개발 빌드4.47초 및 전체 비표시 렌더 통과. /tmp/tile-three-columns-build.log, /tmp/tile-three-columns-previews.log. desktop-three-columns-overlay/full.png에서 같은1120×729pt 패널 폭, 세 열의 여백·독립 스크롤·전체 상세를 확인했다. 기존6·6안도 같은 렌더 실행에서 유지했다. 새 XCTest/Python 테스트를 작성하거나 반복 실행하지 않았다.
- 시안 PNG는 desktop-three-columns-overlay-20261014.png와 desktop-three-columns-full-20261014.png로 별도 저장했다. 기본 앱 비교 입력nil/설치1.2.0/공개1.1.5와 버전·노트는 유지한다. 실제 모니터 판정/사용자 입력/Aside 증상을 검증하거나 수정한 결과로 설명하지 않는다.

## R148 · 데스크탑 두 열 비교 시안

- R147의 격리된 서명/공증 산출물은 그대로 설치하고, 추가 소스는 비교 전용 DesktopColumnsPreviewData 및 nil 기본값의 DeckView 입력이다. 설치된 소스2980b02에는 이 비교 변경이 들어 있지 않다. 앱 버전은 올리지 않았다.
- 각 열은 작은 타일6칸이며 열 사이24pt, 타일 사이8pt다. 현재 최근 창 전체 폭630.4pt 안에서 1×1은43.87pt/2×2는95.73pt/4×2는199.47pt다. 왼쪽7개 그룹·10개 창, 오른쪽3개 그룹·5개 창과 회색 앱8개, 전체23개 인덱스를 중복/누락 없이 확인했다. 같은 앱의 보이는/안 보이는 창은 각 열에서 독립 그룹이다.
- 숫자 순서는 왼쪽 그룹 위→아래 다음 오른쪽이며, 작은 창의 진한색과 파스텔·앱 회색은 크기와 독립적이다. 공유 windowTile과 RecentTileArrangement를 써 작은 후속 둘의 세로 스택/이전 줄 미채움을 유지했다. 기본 실행 경로의 입력은 nil이다.
- native 개발 빌드 및 전체 격리 렌더 통과: /tmp/tile-columns-build.log, /tmp/tile-columns-previews.log. 실제1120×729pt 오버레이와 잘리지 않은 두 열 상세를 눈으로 확인했다. 현 높이에서는 왼쪽3개 앱 그룹이 보이고 나머지는 독립 세로 스크롤 대상이다. 상세는 전체 구성을 검토하는 이미지이며 실제 패널 높이를 바꾼 것이 아니다.
- 사용자 화면·실제 창·설정을 읽거나 조작하지 않았으며 이전 캡처 기반 합성23개를 사용했다. 모니터B는 이전과 같은 가정이고 현재 Aside 상태를 재진단하지 않았다. R148에 대해 단위 테스트를 새로 작성하거나 전체 XCTest/Python을 다시 돌렸다고 기록하지 않는다.

## R147 · 1.2.0 앱별 창 묶기·활성 앱 대표 창

- 사용자 적용 요청을 직전 추천 두 번째 안으로 해석해 먼저 안내하고 기본 RecentAppearance를 grouped로 바꿨다. 실제 appID를 AX/CG-only/앱 전용 항목에 전달하며 ID/경로/PID 기반으로 동일 앱을 묶는다. 활성 그룹을 앞에 두고 그룹 및 내부 MRU를 보존한다. 개별 창 ID는 유지한다.
- 새 DeckCore 정책은 활성 앱의 첫 보이는 실제 창 하나만 wide, 나머지 current 창은 square, other/unknown·앱 전용은 small이다. 색은 기존 실시간 windowDesktops를 사용하며 크기는 숫자 대상과 같은 고정 snapshot.desktop을 사용한다. Option 유지 중 순서/번호/크기를 바꾸지 않고 핀 갱신에서 그룹/대표를 갱신한다. 수동 제한은 그룹화 후 적용한다.
- native XCTest 124개/Python 배포 정책 23개 통과. /tmp/tile-120-tests.log, tile-120-python-tests.log. 새 7개 테스트는 떨어진 창 그룹화/앱 전환·nil/동일 이름 별도 ID·활성 대표 하나/보이는 후속 square·숨겨진 대표 skip/앱 전용·unknown 및 1000개 창 인덱스 보존이다. native 도구 중단 예정 경고는 앱 실패와 구별한다.
- 실제 OverlayContent.refresh 격리 검사에서 그룹화 뒤 수동6 적용으로 첫 그룹의 떨어진 창들을 보존하고 번호2가 해당 그룹의 두 번째 창 ID인 것을 확인했다. 앱 전환 뒤 새 snapshot 번호와 기존 캡처 snapshot의 번호/ID도 대조했다. 기존 HoldMonitor/핀 갱신 정책·메뉴·아이콘·설정 크기·표면 마스크·스크롤 검사도 통과했다.
- debug 빌드 및 production override 없는 공유 DeckView 렌더 통과. /tmp/tile-120-debug-build.log, tile-120-previews.log, tile-120-production-build.log, tile-120-production-previews.log. grouped-production-chatgpt/terminal.png의 23개 합성 목록에서 대표 wide 하나/모든 보이는 square·다른 small/색 독립성·앱 회색과 번호를 확인했다. 두 테마/명암·작은 화면/프로필별 높이·최근100개 끝 스크롤도 통과했다. 사용자 화면을 조작하거나 실제 앱 전환 수신을 검증한 것으로 기록하지 않는다.
- 기능 minor1.2.0(21), 누적 노트 v1.1.5→v1.2.0 범위를 검사했다. 메인 Source의 번호 선택은 그룹화된 visibleSnapshot.windows를 사용함을 대조했다. Aside 조사 보류는 유지했고 AX/CG 후보 판정·focus 경로는 변경하지 않았다. 서명·공증·설치 결과는 이어 기록한다. 새 GitHub 공개는 별도다.
- 전달 완료: 소스2980b02a54feb2ae7179d19134a09e926b9a3a24에서 격리 release 빌드, Developer ID Team VV2W9U5XT3 서명 및 실제 서명 실행 파일 --render-previews 검사가 통과했다. /tmp/tile-120-prepare.log, tile-120-sign.log, tile-120-signed-previews.log. production override 없는 ChatGPT/iTerm 그룹 렌더와 기존 설정·마스크·스크롤 검사를 확인했다.
- Apple 제출af2f41a0-f10d-4178-a542-10f2448d1ca2는 Accepted다. 티켓 부착/검증·Gatekeeper·최종 ZIP 검증을 완료했다. 산출물은 ~/Library/Developer/TileLauncher/releases/v1.2.0에 있고 공증 인증은 기존 Keychain 프로필만 사용했다.
- 번들 SHA256 4cfdd4083f0f5158c79d957128e52fc7fcab484bc32699468a8400b4ebafa718, ZIP 8c82a0820445208ad361aef051efd3fc68d8f65d60bf029d200af02490c897a7, 메타데이터4b8c327787044e0a8a08264f9bdd05d815a7fc43e1a9c6281b03686c314d4c00, SHA256SUMS fd3e9b430a1752038936371138f566b2caff9cf0e3e5d099583c73a620f920f2다.
- /Applications/launch at Login/Tile Launcher.app에 이전 앱을 백업한 뒤 설치했고 버전1.2.0/빌드21·동일 번들 해시·codesign/stapler/spctl을 다시 확인했다. /tmp/tile-120-install.json과 tile-120-install.log에 근거가 있다. 실행 소유자 파일이 같아 기존 인스턴스를 보존했으며 자동 재시작은 하지 않았다. 다음 재열기에서 새 빌드로 전환한다. 사용자 설정/권한을 변경하지 않았고 실제 입력/Aside 재현을 통과했다고 주장하지 않는다. 공개는1.1.5로 유지한다.

## R146 · Aside 일시 누락의 읽기 진단·현재 정상

- 설치 1.1.5(20)의 --diagnose-window-inventory at.studio.AsideBrowser는 GUI/인스턴스 잠금/전역 입력 없이 실행했고 Aside 실제 창 1개를 other로 반환했다(/tmp/tile-aside-inventory.json). 실행 소유자 버전/빌드도 1.1.5(20)이며 설정의 automaticWindowCount=true를 필요한 항목만 읽었다.
- /tmp/tile-aside-metadata.swift의 메타데이터 읽기에서 Aside regular/hidden=false, AXWindows success·0개, ordered-in=1/alpha=1/1779×851 서버 창 1개를 확인했다. 다른 큰 보조 표면들은 ordered-out이며 제외되는 것이 맞다. /tmp/tile-aside-metadata.log. 개인 창 제목/웹 내용/계정은 출력하지 않았다.
- WindowTracker의 CG-only 대체 수집은 other만 허용하고, 창 없는 앱 판정은 후보 서버 창이 있으면 막힌다. 이는 current에서 AX 목록이 비는 앱의 누락 후보 조건이나 이번 실제 누락 시점의 재현 증거는 아니다. 실제 UI 입력/Aside 활성화/권한 변경 없이 현재 상태만 확인했다.
- 사용자는 이후 지금은 잘 나온다며 바빠서 재현을 나중으로 미루겠다고 했다. 추가 진단/코드 수정·테스트·빌드·설치/버전 변경을 하지 않는다. 버그 원인이나 해결을 선언하지 않으며 설치/공개 1.1.5는 유지한다.

## R145 · 보이는 창 2×2·활성 앱 대표 하나 4×2 비교

- MonitorPreviewSizing에 비교 전용 visibleWindows/activeAppOnly를 추가했다. 기본 smallFollowers 및 production 입력 nil은 유지한다. 첫 안은 보이는 창 2×2/안 보이는 창 1×1이며 활성 모니터의 그룹 첫 창만 4×2, 두 번째는 활성 앱 첫 창 하나만 4×2다. 동일 창의 색·순서는 R144를 유지한다.
- native 개발 빌드 2.28초 및 전체 격리 --render-previews 통과. /tmp/tile-visible-size-build.log, tile-visible-size-previews.log. 로그의 실제 크기 집계는 visibleWindows wide=5/square=5/small=13, activeAppOnly wide=1/square=9/small=13이다. XCTest/Python을 다시 실행했다고 기록하지 않는다.
- 두 공유 뷰 이미지에서 보이는 iTerm 두 창/Safari 두 창/Finder 두 창이 2×2이고 숨겨진 ChatGPT/Docmost/Claude가 1×1임을 확인했다. 첫 안에서는 활성 모니터 다섯 앱의 첫 창이 4×2이며 일부 마지막 작은 타일이 3.3줄 경계에 걸친다. 대안은 ChatGPT 하나만 4×2이고 더 많은 타일을 동일 영역 안에 온전히 표시한다. 작은 회색 앱 타일도 유지한다.
- 동일 23개·등록 18개·1120×729pt/모니터 B 가정의 정적 합성 렌더다. 실제 사용자 앱/화면/설정을 조작하지 않았다. 전달 PNG는 monitor-visible-window-sizes-20261014.png / monitor-active-app-hero-20261014.png이며 앞선 시안 파일을 보존한다. 설치/공개 1.1.5(20) 번들 해시는 그대로다. 실제 선택·구현/설치/새 버전·릴리스는 하지 않았다.

## R144 · 작은 창도 모든 보이는 데스크탑 기준으로 강조

- MonitorGroupingPreview의 색상 대상에서 첫 창 조건을 제거하고 isApplication=false/desktop=current만 사용했다. 크기/모니터/묶음 순서 로직은 그대로이며 범례도 현재 보이는 데스크탑으로 정정했다. 실제 WindowTracker/DesktopWindows 및 production 입력 nil은 유지한다.
- native 개발 빌드 1.79초 및 전체 --render-previews 통과. /tmp/tile-visible-colors-build.log, tile-visible-colors-previews.log. 두 시안에서 Safari/iTerm/Finder/Docmost의 보이는 작은 창은 진한색, ChatGPT/Claude의 보이지 않는 작은 창은 파스텔, 앱 전용 항목은 회색을 확인했다. iTerm 선택 전후 색은 유지되고 묶음 순서·첫 창 크기만 달라진다.
- 같은 23개/모니터 B 가정의 합성 정적 공유 뷰 렌더다. 새 전달 PNG는 monitor-all-visible-active-20261014.png / monitor-all-visible-terminal-20261014.png이며 앞선 시안 파일을 보존한다. 실제 모니터 분류/MRU 갱신 기능을 구현했다고 기록하지 않는다. 기존 XCTest/Python을 다시 실행하지 않았고 설치/공개 앱 1.1.5(20)의 번들 해시를 보존했다.

## R143 · 보이는 데스크탑의 첫 창만 강조하는 시안

- 비교 fixture의 강조 대상만 정정했다. 모니터와 무관하게 visible 데스크탑의 앱 묶음 첫 실제 창을 강조하며 후속 창/보이지 않는 데스크탑은 파스텔, 앱 전용 항목은 회색이다. 크기는 기존 시안의 활성 모니터 첫 창 4×2/그 외 첫 창 2×2/후속·앱 1×1을 유지한다.
- native 개발 빌드 1.84초·전체 격리 --render-previews 통과. /tmp/tile-monitor-colors-build.log, tile-monitor-colors-previews.log. ChatGPT활성 오른쪽 위 iTerm의 진한 2×2, iTerm활성에서 다른 모니터 앱들의 진한 2×2, 두 화면의 모든 작은 후속 창 파스텔/앱 회색을 이미지로 확인했다. 앞선 XCTest/Python을 새로 실행했다고 기록하지 않는다.
- 같은 23개 합성 목록과 모니터 B 가정을 사용한 정적 공유 뷰 렌더다. 실시간 모니터 판정/앱 묶기를 실제 구현·검증했다고 하지 않는다. 이전 시안 PNG는 보존하며 새 전달 파일은 monitor-visible-heads-active-20261014.png / monitor-visible-heads-terminal-20261014.png다.
- 변경은 MonitorGroupingPreview에만 있으며 production 비교 입력 nil·설치/공개 버전 1.1.5(20)은 유지한다. 새 서명/공증/설치/릴리스는 하지 않았다.

## R142 · 활성 모니터·앱 묶기 비교 시안

- DesktopWindows.refresh가 모든 display의 Current Space ID를 activeSpaces 합집합에 넣고 resolve에 전달하는 것을 확인했다. 현재 모든 모니터의 보이는 데스크탑을 강조하는 이유다. 이 production 코드는 수정하지 않았다.
- 동일 23개 합성 창·앱/등록 18개/1120×729pt의 monitor-current / monitor-grouped-active / monitor-grouped-terminal을 공유 DeckView로 화면 없이 렌더했다. 첫 창은 활성 모니터 4×2/다른 모니터·Space 2×2, 이후 같은 앱은 1×1이며 기존 작은 쌍 세로 스택/이전 줄 미채우기를 유지한다. iTerm의 두 창이 맨 앞으로 모이고 A의 앱 첫 창이 2×2로 바뀌는 모습을 확인했다.
- A는 제공된 Mission Control 기준, B는 이전 오버레이의 visible 색에 따른 가정이다. Safari/Finder 새 창은 두 시점의 캡처를 보완한 합성 샘플이며 실제 AX/CG 목록이 아니다. 개인 문서/계정 제목은 일반화했고 아이콘은 로컬 앱 리소스에서 읽었다. 사용자 설정·화면 조작/새 권한 요청은 하지 않았다.
- native 개발 빌드 5.06초, 프로필 이름 보정 후 2.05초 통과. /tmp/tile-monitor-preview-build.log, tile-monitor-preview-final-build.log. 지원 중단 예정 도구 경고는 앱 오류와 구별한다. 전체 --render-previews의 키/클릭 정책·메뉴 카탈로그·설정/표면 마스크·최근 100개 끝 스크롤도 통과했다(/tmp/tile-monitor-previews.log). XCTest/Python을 새로 실행했다고 기록하지 않는다.
- 전달 PNG는 ~/.codex/visualizations/2026/10/12/01a12d92-b01c-7760-b0c2-ef84fe97ea6c/monitor-current-20261014.png, monitor-grouped-active-20261014.png, monitor-grouped-terminal-20261014.png다. 정적 합성 렌더이며 실제 Glass 데스크탑 합성/실시간 모니터 분류/앱 선택 MRU 갱신을 구현·검증했다고 하지 않는다.
- 시안 입력은 nil 기본이며 실제 DeckView 호출의 .consecutiveSmall/순서/강조 판정은 유지한다. 앱 적용/서명·공증/설치/새 버전/릴리스는 하지 않았다. 설치 1.1.5(20)의 번들 해시가 기존 v1.1.5 manifest와 일치하는 것을 읽기 검사로 확인했다.

## R141 · 1.1.5 정식 공개 및 공개 재다운로드 검증

- 실제 공개 목록의 직전 정식 버전v1.1.3과 CHANGELOG/요청·검증 기록/Git v1.1.3..3485794 차이를 대조했다. 중간 미게시1.1.4의 색상 예시·등록 앱과 폴더 구분,1.1.5의 열 정렬을 모두 노트에 포함했다. 범위/버전 검사 통과이며 원문은 기존 준비된 파일과 같아서 refresh-notes/재빌드/서명·공증 재수행은 하지 않았다.
- 기존 공증 앱의 서명·티켓·Gatekeeper·ZIP 재추출/해시 검증과 PUBLIC 저장소·원격main 포함·태그/소스·직전 공개본·본문/자산 목록·초안 다운로드 해시 검사를 통과했다. 2026-10-14 14:41:23 KST 최신 정식v1.1.5 공개, release ID 412373030. /tmp/tile-115-release-draft.log, tile-115-release-publish.log.
- 공개 API에서 draft=false/prerelease=false/latest=v1.1.5, 태그의 commit 3485794d957f20df5b2cb415a2e075d9c2e9cd60 및 공개 본문 원문 일치를 확인했다. 세 공개 자산을 asset ID로 다시 내려받아 release-metadata.json 5ee4f0e914ffbcd9a1af830732724147145d686d7328005d0f2c902a4987a7bc; SHA256SUMS.txt 1dfad1b238900c1f9735254b22e7c090ce9ecd4b5b1257ae36441f8c7519ada7; Tile-Launcher-1.1.5-arm64.zip 8996fe486672664f577aa3d81aa1a09a25782cef2f52acb910692ae1c9c1f7e2 일치를 확인했다. /tmp/tile-115-public-verification.json.
- 원문은 release/history/v1.1.5.md에 보존하고 공개 목록/다운로드/현재 단계 문서를 갱신했다. 기존 공개 릴리스 태그·자산 및 설치 앱/사용자 설정·권한/실행 상태는 변경하지 않았다. 이번 게시에서 앱 기능 테스트를 새로 실행했다고 기록하지 않는다. 앞서 통과한 두 테마/명암·기본/작은 설정·실제 서명 실행 파일의 격리 렌더 결과를 사용했다.

## R140 · 1.1.5(20) 색상 예시 열 정렬

- 회색 작은 예시의 컨테이너만64pt여서 나머지56pt 예시보다 두 번째 열이8pt 밀렸다. 컨테이너를56pt로 맞췄으며 작은 타일24pt/텍스트/8pt 행 간격·색/강조 순서는 유지한다. 메뉴 자주 사용/최근 창 연한색/등록 앱의 두 번째 열, 고정 메뉴/최근 창 진한색의 세 번째 열이 맞는다.
- 소스 3485794d957f20df5b2cb415a2e075d9c2e9cd60의 독립 최적화 빌드/App Intents 추출·Developer ID Team VV2W9U5XT3/강화된 런타임/타임스탬프/strict 서명/ZIP 검증 통과. /tmp/tile-115-prepare.log, tile-115-sign.log. 실제 서명 실행 파일의 --render-previews에서 설정 창 크기/키·클릭 정책/메뉴 카탈로그/작은 설정 하단·최근100개 끝 스크롤/표면 마스크와 전체 렌더를 통과했다(/tmp/tile-115-previews.log). UI 정렬에 필요한 빌드·네이티브 렌더 검증이며 기존 XCTest/Python을 이번에 다시 실행했다고 기록하지 않는다.
- appearance-classic/glass-dark/light와 settings-appearance-580/540에서 타일 열 시작선·회색 크기 유지/읽기 쉬운 글자를 확인했다. 합성 설정·화면 밖 렌더이며 사용자 화면/Glass 데스크탑 합성/실제 UI 입력 검증과 구별한다. 사용자 캡처는 공개 저장소에 복사하지 않았다.
- Apple 제출 6d3e83e8-110b-41fd-a1d5-9a8af09e882a을 중복 업로드 없이 같은 ID로 재조회해 Accepted를 확인했다. 티켓·Gatekeeper·최종 ZIP 재추출 검증 통과. /tmp/tile-115-notarize.log, tile-115-notarize-final.log. 기존 Keychain profile을 사용하며 암호/개인 키는 출력하지 않았다.
- 최종 번들 SHA-256 98a124bbcfa97e20d0de986cfa2c6d35a0d93ac12a0f32b936520740cdd67abf; Tile-Launcher-1.1.5-arm64.zip 8996fe486672664f577aa3d81aa1a09a25782cef2f52acb910692ae1c9c1f7e2; release-metadata.json 5ee4f0e914ffbcd9a1af830732724147145d686d7328005d0f2c902a4987a7bc; SHA256SUMS.txt 1dfad1b238900c1f9735254b22e7c090ce9ecd4b5b1257ae36441f8c7519ada7.
- 설치 /Applications/launch at Login/Tile Launcher.app, 백업 /var/folders/cy/rhl7z2sn7mv4yjlmfy7xsl8c0000gp/T/tile-before-115-we60isch.app, receipt /tmp/tile-115-install.json, 설치 로그 /tmp/tile-115-install.log. 설치 후 버전1.1.5/빌드20·서명·stapler·Gatekeeper·번들 해시가 공증 산출물과 일치한다. 실행 소유자 파일은 전후 동일하며 사용자 설정·권한/현재 실행 앱을 유지했다. 자동 재시작/사용자 화면 조작은 하지 않고 다음 다시 열기에서 전환한다.
- 공개 1.1.3 자산·태그는 보존하며 새 GitHub 릴리스를 게시하지 않았다. 다음 공개 범위 v1.1.3→v1.1.5의 누적 노트에는 1.1.4/1.1.5 모두를 포함한다. 소스·기록은 main에 푸시한다.

## R138–R139 · 1.1.4(19) 색상 예시·등록 앱과 폴더

- 사용자가 확정한 최근 창 색상 예시는 회색 1×1 → 연한색 2×2 → 진한색 2×2다. 컬러 1×1을 제외하고 진한색을 오른쪽에 맞췄다. 등록 예시는 파스텔 폴더 → 진한 앱 정사각이며 실제 등록 타일의 kind=.app만 기존 강조 팔레트를 사용한다. 폴더/휴지통은 기존 파스텔, 아이콘·번호/선택·hover/실행/프로필/저장 색은 유지한다.
- 최초 후보 b99f3ae의 긴 현재/다른 데스크탑 예시 제목이 잘려 색 이름 진한색/연한색과 툴팁으로 보정했다. 전용 AppearancePreview 호스트에 배경을 넣어 네이티브 박스/기본 글자를 확인했다. 이후 R139의 추가 요청은 같은 미전달 1.1.4(19)에 포함했다. 앞 후보 산출물은 v1.1.4-candidate-b99f3ae / v1.1.4-candidate-d12d3dc에 보존하며 최종 기본 경로는 v1.1.4다.
- 최종 소스 bdd5cb5381c204c0db974b4e74c1456f41114a1a의 독립 최적화 빌드/App Intents 추출 및 Developer ID Team VV2W9U5XT3/강화된 런타임/타임스탬프/strict 서명을 통과했다. /tmp/tile-114-r139-prepare.log, tile-114-r139-sign.log. 실제 서명 배포 실행 파일의 --render-previews에서 키/클릭 정책·메뉴 카탈로그·설정 크기·하단 스크롤·표면 마스크·최근 창 100개 끝 및 전체 렌더를 통과했다(/tmp/tile-114-r139-previews.log). UI 변경에 필요한 빌드/공유 뷰 검사이며 앞선 117개 XCTest/23개 Python을 이번에 다시 실행했다고 기록하지 않는다.
- appearance-classic/glass-dark/light와 settings-appearance-540/580의 샘플 크기·순서·글자/아이콘을 확인했다. menu-realistic-2-gray-square.png의 앱 강조/폴더·휴지통 파스텔과 읽기 쉬운 글자를 확인했다. 합성 프로필/창 제목·정적 네이티브 렌더이며 실제 사용자 오버레이·데스크탑 Glass 합성·Focus/TCC 입력 확인과 구별한다. 개인 설정을 읽거나 변경하지 않았다.
- Apple 제출 18ab19a3-c32e-4b28-8a94-843841578f5e은 같은 ID 재조회 후 Accepted이며 티켓·Gatekeeper·최종 ZIP 검증을 통과했다. /tmp/tile-114-notarize.log, tile-114-notarize-final.log. 기존 Keychain profile을 사용했고 공증 로그인 재요청/암호·개인 키 출력은 하지 않았다.
- 최종 번들 SHA-256 3dcd27969a566885ec88af8de189b061fdba7994e90fee8ba9ebdb2386942111; Tile-Launcher-1.1.4-arm64.zip e9fc1cf196afbe3faf504cab7a22c6a87c539d757bc8e27eb72e819bd139c001; release-metadata.json 5d2b99e5c5da067816eca4aa920de2153d63ec7f0b229ab69baa441f74da6d98; SHA256SUMS.txt d028185ae0b959b27c4eba03888c4343661473ca777e49cf0c35bd376c866ae3.
- 설치 /Applications/launch at Login/Tile Launcher.app, 백업 /var/folders/cy/rhl7z2sn7mv4yjlmfy7xsl8c0000gp/T/tile-before-114-l0_por0h.app, receipt /tmp/tile-114-install.json, 설치 로그 /tmp/tile-114-install.log. 설치 후 버전1.1.4/빌드19·서명·stapler·Gatekeeper·번들 해시가 공증 산출물과 일치한다. 실행 소유자 파일이 전후 동일하며 자동 재시작/사용자 화면 조작/설정·권한 변경을 하지 않았다. 다음 다시 열기에서 새 빌드로 전환한다.
- 새 GitHub 릴리스/태그는 만들지 않았고 공개 1.1.3 자산을 보존한다. 다음 누적 노트는 v1.1.3→v1.1.4 범위로 준비하며 소스/최종 검증 기록을 main에 푸시한다.

## R137 · 1.1.3 정식 공개·누적 노트·공개 다운로드 확인

- GitHub 공개 목록의 직전 실제 정식 버전 v1.0.0과 CHANGELOG/요청·검증 기록 및 v1.0.0..ce58673 Git 변경을 대조했다. 1.1.0/1.1.1/1.1.2/1.1.3 전체 기능·버그·UI 변경을 포함하고 중간 4×2 창 단계/최종 2×2·1×1을 구별했다. 시안은 출시 기능에서 제외했고 R136 원인 확인을 반영해 오래된 USBClean 미확정 안내를 정리했다.
- 사용자 최종 캡처에서 Developer/USBclean의 회색 작은 앱 타일이 확인됐고 정상 종료도 사용자가 확인했다. 앞선 CUA 실패를 에이전트의 픽셀 캡처 성공으로 바꾸지 않는다. 개인 캡처/문서 제목을 공개 저장소에 저장하지 않았다.
- 노트 커밋 1f91c5f 이후 refresh-notes는 기존 설명/manifest를 notes-history에 보존하고 앱/ZIP/메타데이터/체크섬을 바꾸지 않았다. 기존 1.1.3(18) 서명·티켓·Gatekeeper·ZIP 검사를 재통과했다. /tmp/tile-113-release-refresh.log. 앱 재빌드·공증 재제출·설치·새 버전 증가는 하지 않았다.
- draft/publish의 범위/직전 공개본/정식 정책/PUBLIC 저장소/태그-소스/원격 main 포함/본문/자산 검사 및 초안 asset ID 다운로드 체크섬 검증을 통과했다. 2026-10-14 13:48:03 KST v1.1.3을 최신 정식으로 공개했다. /tmp/tile-113-release-draft.log, tile-113-release-publish.log.
- 공개 API의 release ID 412346571, draft=false/prerelease=false/latest=v1.1.3와 본문 원문 일치, 태그의 실제 commit ce58673c587f9d5e9a3359d8bbbeed0034ace15f를 재확인했다. 공개 세 자산을 asset ID로 다시 다운로드해 ZIP 5e3ba121e597497b7c7522e276d7d11aed1c3f3cbbcff3523e9cffe259d73a9f / 메타데이터 9a12bdf124118bcb7e8e46f9a085425ec26211cf19e2b924d9f6ca5ab5ce6e1e / 체크섬 파일 dd59b105c20793edda4df08219786a3e698812288a3fa291bc238cf1faff8b41 일치를 확인했다. /tmp/tile-113-public-verification.json.
- 공개 설명 원문은 release/history/v1.1.3.md에 보존한다. 링크/다운로드/현재 단계 문서만 갱신하고 기존 네 공개 릴리스의 태그·바이너리·자산은 건드리지 않았다. 이번 게시 작업에서 앱 기능 테스트를 새로 실행한 것으로 기록하지 않는다. 이전 117개 XCTest/23개 Python 및 실제 앱/서명 실행 파일 렌더 결과를 사용했다.

## R136 · 1.1.3(18) 닫힌 보조 창 판정

- 사용자 요청에 따라 CUA로 실제 오버레이의 Developer 세 타일과 Developer의 실제 Discover 창을 확인했다. 현재 작업의 화면 조작은 명시적 승인 범위이며 보통의 무조작 검증 선호를 일반적으로 철회한 것으로 취급하지 않는다. 개인 문서 제목/사용자 목록은 공개 기록에 복사하지 않는다.
- 읽기 진단 /tmp/tile-window-metadata-before.log, tile-window-order.log에서 Developer AXWindows=1, Discover ordered-in=1, General/Account ordered-in=0/alpha=1/큰 bounds를 대조했다. USBclean/Keychain Access는 AXWindows 성공·0개지만 ordered-out 큰 표면이 남아 있었다. Developer를 닫은 뒤 AXWindows=0/세 서버 표면 ordered-out도 확인했다(/tmp/tile-window-closed.log). CG의 .optionAll 잔존을 실제 창으로 오판한 원인이다.
- runtime-checked SLSWindowIsOrderedIn/CGSWindowIsOrderedIn의 UInt8 출력/성공/0 또는 1만 사용한다. 참고 선언/사용은 macos-upgrade-guide.md의 yabai 1차 소스 링크다. 값이 false인 CG-only 후보/캐시를 제외하고 AX 목록에서 사라진 캐시는 최소화·숨김·AX 실패·nil 상태를 보존한다. 현재 최소화 AX 값이 캐시보다 우선한다. 실제 AX 목록에 있는 창은 ordered-out만으로 제거하지 않는다.
- XCTest 117개/Python 배포 정책 23개 통과, /tmp/tile-113-tests.log. 새 두 회귀는 큰 alpha=1 ordered-out 표면 제외/true·nil 보존, 누락 AX 캐시의 정상/최소화/숨김/조회 실패/미지원 보존 조건이다. 기존 Space·MRU·프로필·배치·사용 통계도 통과했다.
- 수정된 실제 생산 WindowTracker의 별도 --diagnose-window-inventory에서 Developer/USBclean/Keychain Access 앱 항목 각각 1개, 다른 Space 두 창을 포함한 실제 문서 창 3개 보존을 확인했다(/tmp/tile-113-live-closed.json). 실제 Developer 최소화 후에는 앱 항목이 아니라 실제 창 1개로 보존됐다(/tmp/tile-113-live-minimized.json). 제목/문서 내용을 출력하지 않았다. 이미 실행 중인 앱을 새 추적기에서 읽는 검사여서 앱 시작 순서 때문인 것으로 취급하지 않는다.
- 기존 화면 없는 렌더/설정/키 정책/메뉴·최근/100개 스크롤/마스크 통과(/tmp/tile-113-previews.log). 최종 최소화 캐시 우선순위 보정 빌드 로그 /tmp/tile-113-final-debug-build.log. 최종 서명·공증·설치와 실제 목록 결과는 아래와 같다. 새 GitHub 릴리스는 별도다.

- 소스 ce58673c587f9d5e9a3359d8bbbeed0034ace15f, 1.1.3(18)/arm64/min26.0의 독립 최적화 빌드·App Intents 추출·Developer ID Team VV2W9U5XT3/강화된 런타임/타임스탬프/strict 서명·ZIP 검증을 통과했다. /tmp/tile-113-prepare.log, tile-113-sign.log. 실제 서명 배포 실행 파일의 화면 없는 설정·메뉴/최근·100개 스크롤·마스크 렌더도 통과했다(/tmp/tile-113-signed-previews.log).
- Apple 제출 a8678b86-f159-4c7a-905d-0310b8184919 Accepted 후 stapler/Gatekeeper·최종 ZIP 재추출 검증 완료. /tmp/tile-113-notarize.log, tile-113-notarize-final.log. 공증 인증 재요청이나 암호/개인 키 출력은 하지 않았다. 실제 서명 배포 실행 파일의 읽기 생산 추적기에서도 닫힌 Developer/USBclean/Keychain Access가 앱 항목 하나씩이다(/tmp/tile-113-signed-closed.json).
- 최종 번들 SHA-256 192a99f8afccb1117916d9c03dc3f013f67abca1fbc8dbb67ea800403511aee5; Tile-Launcher-1.1.3-arm64.zip 5e3ba121e597497b7c7522e276d7d11aed1c3f3cbbcff3523e9cffe259d73a9f; release-metadata.json 9a12bdf124118bcb7e8e46f9a085425ec26211cf19e2b924d9f6ca5ab5ce6e1e; SHA256SUMS.txt dd59b105c20793edda4df08219786a3e698812288a3fa291bc238cf1faff8b41.
- /Applications/launch at Login/Tile Launcher.app에 설치 후 버전/빌드/서명/티켓/Gatekeeper/번들 해시 재검증 통과. 이전 앱 백업 /var/folders/cy/rhl7z2sn7mv4yjlmfy7xsl8c0000gp/T/tile-before-113-py9reh9h.app, receipt /tmp/tile-113-install.json, 설치 로그 /tmp/tile-113-install.log. 앱 경로·설정·프로필·권한은 보존했으며 이후 CUA/Finder 재호출로 새 실행 소유자 1.1.3(18)/같은 설치 경로를 확인했다.
- 최종 CUA는 새 프로세스에 noWindowsAvailable가 반복되고 Option 단독 입력도 keyPressIncludedNoNonModifierKeys로 거부됐다. 사용자에게 오버레이 열기·고정을 요청했고 사용자가 완료를 확인했다. 그 뒤 화면 입력 없이 실행 중인 새 오버레이 AX/CG를 읽어 AXWindows=1, ordered-in=1/onScreen=true/1120×729pt와 Developer/USBclean/Keychain Access 열린 창 없음 버튼 각각 1개를 확인했다(/tmp/tile-113-overlay-read.log). 등록 버튼/앱 메뉴 검색 항목은 최근 목록 개수에서 제외한다. 최종 픽셀 캡처 확인과 구별하며 사용자 개인 문서/목록/스크린샷은 공개 저장소에 넣지 않았다.

## R135 · 1.1.2(17) 선택한 메뉴 기본 적용

- 사용자가 두 번째 메뉴 안의 실제 적용·공증·설치를 승인해 DeckView/DeckPreview의 공통 MenuAppearance.selected를 recentGraySquare로 정했다. 고정 강조색 4×2/자주 파스텔 2×2/최근 회색 2×2이며 기본 창과 같은 모듈·8pt 간격/줄 배치를 쓴다. 최근 창/등록 프로필의 동작은 유지한다.
- 선택한 메뉴 색은 고정·자주 사용에 적용하며 최근은 중립색 0x777777의 기존 테마별 표면 배합으로 표시한다. 실제 설정 값을 덮어쓰지 않고 타일 환경에만 적용한다. 모양 예시의 최근/자주를 2×2·고정을 4×2로 맞추고 메뉴 안내의 자주 사용 가로형 설명을 수정했다.
- 기존 scripts/test.sh 통과: XCTest 115개/Python 배포 정책 23개, /tmp/tile-112-tests.log. 메뉴 저장·핀/합산 통계·최근/빈도 기간·사용자 색 보존/설정 왕복·즉시 클릭/숫자 대기·Focus 모델/프로필·배치를 검사했다. 이번 UI 수정에 구현을 그대로 복제하는 새 테스트를 추가하지 않는다.
- 실제 공유 뷰의 최종 --render-previews 통과(/tmp/tile-112-previews.log). 비교 전용 연두색은 비교/현실 샘플에만 쓰도록 분리해 기본 유리 메뉴 노랑/클래식 기본 초록/사용자 색을 유지하는 샘플을 검토했다. 회색 최근 2×2·자주 파스텔 2×2·고정 4×2 및 두 테마·명암·작은 화면/설정 예시·100개 최근 스크롤 끝을 확인했다. /tmp/tile-112-previews, 재빌드 /tmp/tile-112-preview-build.log. 비표시 탭 제목/네이티브 선택 컨트롤/실제 데스크탑 Glass 합성은 별도 실기 범위다.
- UI patch 1.1.2(17)의 노트 범위는 공개 v1.0.0 이후 1.1.0/1.1.1/1.1.2 모두 포함한다. 아직 태그/공개 릴리스는 만들지 않았다. 독립 서명·공증·설치 결과는 이어 기록한다.
- 실제 기본 메뉴는 기존 LazyVStack 행을 유지하고 고정만 span=2로 표시한다. 1×1 비교 전용 안의 ZStack을 생산 기본 경로로 사용하지 않아 많은 메뉴의 모든 버튼을 한꺼번에 만드는 회귀를 피한다. 기본 큰 줄의 단위/순서는 같은 기존 TileArrangement를 사용한다. 보정 후 115개 XCTest/23개 배포 정책 재검사 통과와 최종 렌더를 기록한다(/tmp/tile-112-final-previews.log).
- 소스 bfbc3b61431fe305d93ffead92e872df981bf655에서 독립 최적화 빌드·App Intents 추출·Developer ID Team VV2W9U5XT3/강화된 런타임/타임스탬프/strict 검증·ZIP 재추출 통과. /tmp/tile-112-prepare.log, tile-112-sign.log. 서명된 실제 배포 실행 파일의 --render-previews 격리 검사/메뉴/설정/스크롤/표면 마스크도 통과했다(/tmp/tile-112-signed-previews.log). 실제 전경 앱·사용자 입력을 조작하지 않았다.
- 기존 Keychain 프로필의 읽기 조회가 정상이고 새 제출 ID 6598c2e3-a5fa-40da-9fa3-466e099022a7 하나로 Accepted를 확인했다. 같은 ID를 조회해 티켓 첨부/검증·Gatekeeper source=Notarized Developer ID·최종 ZIP 검증을 완료했다. /tmp/tile-112-notary-history.json, tile-112-notarize.log, tile-112-notarize-final.log. 자격 증명/개인 키를 출력하지 않았다.
- 최종 번들 SHA-256 d26d8fb5fc9fd226b4be49d46cc77fa58c6416443db92c5c25f67cd4896e965b; Tile-Launcher-1.1.2-arm64.zip 3f272e48fc7420bad1cddd432b76f942b1ffe78f4a3e4c3e50f1f91cee827721; release-metadata.json 240a8beb713182b227d10691ebd14da1d3f729ee709ec2d9b8a3a1c1c3dea334; SHA256SUMS.txt c5c39b148cd77663ef319cf0bc41dee1e739214c07f104d306a75124bc11fbb6. 결과 ~/Library/Developer/TileLauncher/releases/v1.1.2.
- /Applications/launch at Login/Tile Launcher.app에 설치 후 1.1.2(17)/소스·번들 해시·서명·stapler·Gatekeeper 재검증 통과. 이전 1.1.1 백업 /var/folders/cy/rhl7z2sn7mv4yjlmfy7xsl8c0000gp/T/tile-before-112-hq70yx8n.app; receipt /tmp/tile-112-install.json; 로그 /tmp/tile-112-install.log. 실행 소유자 파일 설치 전후 동일이며 자동 재시작/사용자 설정·프로필·권한 변경 없음. 다음 다시 열기에서 새 빌드로 전환한다. 사용자 실제 오버레이/Focus/메뉴 수신은 별도 확인 범위다.
- 소스·검증 기록을 main에 푸시하고 새 GitHub 태그/릴리스는 만들지 않았다. 현재 공개본 v1.0.0 및 기존 자산/이력은 유지한다. 실제 앱 버전은 1.1.2(17)이며 문서 결과 기록을 위한 빌드 재생성은 하지 않는다.

## R134 · 현실적인 최근 창으로 메뉴 세 안 비교

- 동일 Finder 메뉴 9개/최근 항목 19개/등록 18개/1120×729pt의 공유 DeckView로 ① 최근 파스텔 1×1 ② 최근 회색 2×2 ③ 현재 기본 메뉴를 렌더링했다. ③의 고정·자주 사용은 4×2이고 최근은 파스텔 2×2다. 기본 메뉴/설치 1.1.1(16)/설정/릴리스는 유지한다.
- 최근 캡처와 비슷한 앱 순서·연속 창·데스크탑 색·창 없는 회색 앱 19개를 가상 데이터로 만들었다. Finder/ChatGPT/Docmost/Claude/Slack/iTerm2 등의 제목은 일반 가상 제목이며 사용자 현재 창/문서를 읽지 않았다. 실제 앱과 macOS의 아이콘 리소스를 직접 읽어 Preview 전용 키에 64pt 이미지로 보관했다. 앱 실행/IconServices 호출 없이 세 안의 동일 아이콘을 확인했다.
- 기본 등록 가상 앱도 읽을 수 있는 실제 앱 아이콘/이름과 기본 macOS 폴더/휴지통으로 비교 맥락을 맞췄다. 사용자의 실제 등록 목록/프로필을 읽거나 수정하지 않았다. 시스템 접근성/전역 입력/전경 창은 조작하지 않았다.
- 최종 native 빌드와 전체 --render-previews 통과, /tmp/tile-menu-realistic-build.log, tile-menu-realistic-previews.log. 설정/기존 메뉴·최근 뷰/100개 스크롤 끝/표면 검사는 같은 격리 경로로 통과했다. 도구 native 사용 중단 예정 경고 외 앱 오류 없음. XCTest/Python을 새로 실행한 것으로 기록하지 않는다.
- 세 PNG를 함께 검토했다. ① 작은 최근 메뉴 이름이 줄어들고, ② 2×2 회색 최근 메뉴의 두 줄 제목과 색 구분, ③ 자주 메뉴도 4×2로 늘어나 같은 목록의 마지막 메뉴가 네 번째 줄 일부로 내려가는 차이를 확인했다. 추천은 ②의 가독성/현재 창 2×2와의 크기 균형/고정만 4×2인 의미 구분을 우선한 에이전트 의견이다. 사용자 최종 선택으로 기록하지 않는다.
- 전달 경로 ~/.codex/visualizations/2026/10/12/01a12d92-b01c-7760-b0c2-ef84fe97ea6c/menu-realistic-1-pastel-small-20261014.png, menu-realistic-2-gray-square-20261014.png, menu-realistic-3-original-20261014.png. 정적 화면 없는 네이티브 렌더이며 실제 데스크탑 Glass 합성/사용자 앱 수신 검증과 구별한다.

## R133 · 최근 메뉴 회색 2×2로 시안 정정

- 사용자 정정에 따라 두 번째 안은 최근 메뉴의 기존 2×2 크기를 유지하고 회색만 적용했다. 첫 안의 최근 파스텔 1×1은 유지하며 기존 회색 1×1 시안은 과거 기록으로 보존한다. 고정 4×2/자주 2×2 파스텔은 공통이다.
- 동일 9개 메뉴/16개 최근 창/등록 18개/1120×729pt 실제 공유 DeckView의 화면 없는 렌더링을 통과했다. 최근 4개가 2×2로 가로 한 줄에 배치되고 큰 글자로 제목/누적 횟수가 보이며, 첫 안의 작은 쌍 세로 스택은 유지됨을 확인했다.
- 비교 전용 enum을 recentGraySquare로 명확히 하고 해당 안의 최근 크기도 square로 지정했다. 기본 .original 메뉴와 설치 앱/버전 1.1.1(16)은 바꾸지 않았다. 공증/설치/새 공개 태그/릴리스는 하지 않는다.
- 빌드 4.07초·전체 --render-previews 격리 검사/표면 마스크/최근 창 100개 스크롤 및 수정된 두 메뉴 시안 통과. /tmp/tile-menu-gray-square-build.log, tile-menu-gray-square-previews.log. 도구의 native 사용 중단 예정 경고는 앱 오류와 구별한다. 단위 테스트를 다시 실행했다고 기록하지 않는다.
- 전달 파일 ~/.codex/visualizations/2026/10/12/01a12d92-b01c-7760-b0c2-ef84fe97ea6c/menu-gray-square-20261014.png. 첫 안은 기존 menu-small-pastel-20261014.png다. 합성 메뉴/횟수/SF 아이콘이며 실제 사용자 앱 수집/데스크탑 Glass 검증과 구별한다.

## R132 · 메뉴 4×2/2×2/1×1 두 비교 시안

- 비교 전용 MenuAppearance의 최근 파스텔/최근 회색을 실제 공유 DeckView로 렌더링했다. 기본 .original 메뉴는 유지하며 설치 앱/버전 1.1.1(16)/프로필/색을 바꾸지 않았다. 새 앱 서명·설치·공개 릴리스는 하지 않는다.
- 같은 Finder 메뉴 샘플 9개(고정 3/자주 2/최근 4), 최근 창 16개/등록 18개/1120×729pt다. 고정 4×2 강조·자주 2×2 파스텔·최근 1×1, 최근 작은 쌍의 세로 스택/앞 줄 빈칸 미채우기와 최근 창에 동일한 모듈·8pt 간격을 확인했다. 최근 메뉴 배경만 두 시안에서 다르다.
- 제공된 캡처의 연두색에 맞춰 비교 샘플에만 메뉴 기준색 0x4CBB00을 지정했다. 실제 사용자 색을 읽거나 덮어쓰지 않았으며 최근 창과 등록은 동일한 샘플 색이다. 합성 SF 아이콘/샘플 메뉴·횟수를 쓴 화면이며 실제 사용자 앱/메뉴 자동 수집 또는 데스크탑 Glass 합성 검증과 구별한다.
- 작은 메뉴에서 command 아이콘·누적 횟수·최대 두 줄 제목을 확인했다. 긴 제목은 말줄임하며 기존 전체 경로/경로별 횟수 툴팁은 유지한다. 시안 생성용 native 빌드 통과(/tmp/tile-menu-comparison-build.log, 4.85초 이후 제목/색 보정 재빌드); 도구의 native 방식 중단 예정 경고 외 앱 오류 없음.
- --render-previews의 설정/키 입력 정책/메뉴 카탈로그/기본 메뉴/최근 창/표면 마스크/100개 최근 스크롤 끝 및 두 비교 렌더 통과(/tmp/tile-menu-comparison-previews.log). 앞선 115개 XCTest/23개 Python을 이번에 다시 실행했다고 기록하지 않는다.
- 전달 파일 ~/.codex/visualizations/2026/10/12/01a12d92-b01c-7760-b0c2-ef84fe97ea6c/menu-small-pastel-20261014.png, menu-small-gray-20261014.png. 실제 공유 뷰의 정적 PNG이며 두 안의 실제 앱 적용/사용자 최종 선택은 아직 없다.

## R131 · 1.1.1(16) 작은 창 타일 세로 배치

- 사용자가 R129의 두 번째 안을 선택해 실제 DeckView 기본을 앱 전환점 2×2/같은 앱 연속 창 1×1로 바꿨다. 작은 실제 창의 제목/데스크탑 색, 창 없는 앱의 회색/앱 이름과 정상 종료 대상을 구별하며 메뉴 크기는 유지한다.
- RecentTileArrangement는 큰 타일 높이의 줄을 왼쪽부터 채운다. 연속된 작은 둘은 한 열의 위·아래이며 홀수 아래/앞 줄의 빈칸을 후속 항목으로 채우지 않는다. 홀수 뒤 큰 창·짝수·오른쪽 경계·줄바꿈·앱 전환·1000개 및 4/8/12칸에서 겹침/순서/번호 검사를 통과했다.
- scripts/test.sh의 XCTest 115개와 Python 배포 정책 23개 통과, /tmp/tile-111-tests.log. 베타 SDK 캐시 도구가 약 3분간 출력 없이 대기했지만 정상 완료했다. 대기 중 시작한 공식 native 빌드 방식의 교차 검사도 통과(/tmp/tile-111-native-tests.log)했으며 기본 빌드 스크립트는 바꾸지 않았다. native 방식의 도구 사용 중단 예정 경고는 앱 컴파일 오류와 구별한다.
- 실제 공유 뷰를 화면 밖에서 두 테마/명암/작은 화면/등록 0·18·36·200개로 렌더링했다. 작은 타일 밀도가 높아 16개가 3.3줄 안에 들어가므로 스크롤 끝 샘플을 100개로 늘렸다. 최근 마지막 샘플 100번과 작은 일반 설정 하단을 확인했다. /tmp/tile-111-previews.log, /tmp/tile-111-previews/recent-scroll-bottom.png. 최초 렌더의 16개 샘플은 넘침이 없어 스크롤 검사가 실패했으며 샘플 보정 후 전체 검사 통과했다.
- 같은 16개 비교 목록에서 2/3번 세로 스택, 10번/배포 로그 세로 스택, 계산기/다음 주/회의 기록/변경 이력 아래의 빈칸과 오른쪽 큰 창을 확인했다. 전달 PNG ~/.codex/visualizations/2026/10/12/01a12d92-b01c-7760-b0c2-ef84fe97ea6c/recent-vertical-pairs-20261014.png. 합성 SF 아이콘/샘플 제목이며 실제 사용자 앱 아이콘·데스크탑 Glass 합성 검증과 구별한다.
- UI patch 1.1.1(16)의 누적 노트는 공개 v1.0.0 이후 1.1.0과 1.1.1을 모두 포함한다. 서명·공증·설치 결과는 이어 기록한다. 공개 태그/릴리스는 이번 요청으로 만들지 않는다.
- 소스 acb6fc1595bbba26f26edaad26bd3d37a38e3e53의 독립 최적화 빌드(19.34초)/App Intents 추출/Developer ID Team VV2W9U5XT3/강화된 런타임/타임스탬프/서명 및 ZIP 재추출 검증 통과. /tmp/tile-111-prepare.log, tile-111-sign.log. 서명한 실제 배포 실행 파일의 격리 검사/렌더도 통과했고 마지막 100번을 확인했다(/tmp/tile-111-signed-previews.log).
- Apple 제출은 기존 Keychain 프로필을 찾지 못해 인증 단계에서 실패했다(‘No Keychain password item found for profile: tile-launcher-notary’). 기본 및 명시적인 login.keychain-db 모두 같은 결과다. 당시 notary_id가 없었고 Accepted/설치 완료로 선언하지 않았다. 사용자 터미널의 안전한 자격 증명 재저장을 요청했으며 암호·개인 키를 출력/수집하지 않았다. 서명·공증 완료 이전 1.1.0 설치 앱은 보존한다. /tmp/tile-111-notarize.log.
- 이후 사용자가 공증 로그인 재저장과 설치 진행을 확인했다. history 조회 성공 및 해당 1.1.1 제출 없음(/tmp/tile-111-restored-notary-history.json)을 확인해 실패 표시만 백업 후 해제했다. 최초 제출 ID 69951ec3-152d-4386-a605-96ce0c18a670은 Accepted다. 같은 ID로 승인 조회·stapler·Gatekeeper·최종 ZIP 재추출 검증을 완료했다. /tmp/tile-111-notarize-restored.log, tile-111-notarize-final.log. 자격 증명/개인 키를 출력하지 않았다.
- 최종 번들 SHA-256 4fa5f7464f71d45b4ffa90eb6a822ae0726a82103fb9ea8723336fc347d035d1; Tile-Launcher-1.1.1-arm64.zip 826f9e9f4e0193a3a2eef2ed6d375fd0874046d54f83c540195d425cac2cc7cf; release-metadata.json 6c23a3b15aded4451542b6f3ad74f554b75b2566adeef6d21a7654cec427d1c9; SHA256SUMS.txt d7e57f76bc64a4e0e072b98972431b432851236e6ca2777744289ab1d37d11bf. 소스 acb6fc1595bbba26f26edaad26bd3d37a38e3e53, Developer ID Team VV2W9U5XT3와 1.1.1(16) 일치.
- 설치 완료 경로 /Applications/launch at Login/Tile Launcher.app의 서명·stapler·Gatekeeper·번들 해시/버전 재검증 통과. 이전 1.1.0 백업 /var/folders/cy/rhl7z2sn7mv4yjlmfy7xsl8c0000gp/T/tile-before-111-8jr8g47l.app, receipt /tmp/tile-111-install.json, 최종 로그 /tmp/tile-111-install-final.log. 실행 소유자 파일이 설치 전후 동일하며 자동 재시작/권한/설정 변경 없이 다음 다시 열기에서 새 빌드로 전환한다. 첫 상위 폴더 임시 생성은 쓰기 권한이 없어 실패했고, 다음 내부 백업 폴더가 해시에 포함된 검사는 자동 복원했다. 앱 밖 임시 폴더로 보정 후 최종 설치/검증을 완료했다. 사용자 앱의 실제 재호출/드래그/Focus 수신 검증과 구별한다.
- 이번에는 새 앱 빌드/테스트를 반복하지 않고 앞서 통과한 115개 XCTest/23개 Python/실제 서명 실행 파일 렌더 결과와 동일 소스를 사용했다. 새 공개 GitHub 릴리스/태그는 만들지 않았으며 문서·결과를 main에 푸시한다.

## R130 · 누적 릴리스 노트 보완

- 실제 공개 v0.16.3/v0.17.1/v0.17.6/v1.0.0의 설명을 release/history의 정본으로 갱신했다. 범위는 첫 공개 / 0.17.0–0.17.1 / 0.17.2–0.17.6 / 1.0.0이다. CHANGELOG의 실제 버전 제목을 이용한 네 파일의 오프라인 범위 검사 통과. 첫 공개의 소급 개발 단계는 공개 릴리스와 구별한다.
- GitHub API 변경 전후 본문은 정본과 일치했다. id/tag/name/draft/prerelease/published_at/created_at/target_commitish와 모든 자산의 ID·이름·크기·digest·타입·생성/수정 시각·다운로드 URL 동일, latest v1.0.0 유지. 다운로드 수는 외부 사용에 따라 달라져 비교 대상에서 제외했다. /tmp/tile-release-notes-audit.json, tile-release-notes-after.json, tile-release-notes-receipt.json, tile-release-notes-latest.txt.
- Python 배포 정책 23개 통과, /tmp/tile-cumulative-notes-tests.log. 중간 버전 누락/빈 본문/잘못된 버전 제목/중복·순서·다른 산출물 버전·이전 정식 공개본 불일치·기존 공개/초안의 자동 노트 변경 거부와 설명 갱신 시 자산 보존/실패 복원을 검사한다. 검사는 의미상 모든 변경을 자동 판별하지 않으므로 요청·검증 기록과 Git 변경을 대조했다.
- 문서/배포 도구만 변경해 앱 버전은 1.1.0(15)이고 별도 Swift/Xcode 빌드나 사용자 앱 재시작/권한 변경은 하지 않았다. 기존 공개 바이너리/메타데이터/체크섬/태그는 보존했다. 이전 산출물의 release-notes.md/notes_sha256는 최초 게시 기록이며 보완된 공개 설명 정본과 의도적으로 구별한다.
- 미공개 서명·공증 1.1.0의 refresh-notes 실행과 갱신 전후 verify 통과. 노트 소스 커밋 eb5785ca068e9bdadeca5f9011cebd7fff1ac7a5, 새 노트 SHA-256 b13d0a50f8b6d5df2ba8c10a54683718fcf98f75852aff640f144d7be139157a. notes_sha256/notes_range/notes_revision 세 필드를 제외한 manifest 전체 동일이며 앱 소스 2d68dd1ab8e89d4047a4c2c3820e893cb1a81d3e와 번들/ZIP/metadata/체크섬 해시는 위 R124–R127 기록 그대로다. 원본 설명 세 파일은 releases/v1.1.0/notes-history/20261014T023153088154Z에 보존했다. 로그 /tmp/tile-110-cumulative-notes-refresh.log, receipt /tmp/tile-110-cumulative-notes-receipt.json. 새 GitHub 릴리스·태그를 만들지 않았다.

## R124–R127 · 1.1.0(15) 기능 후보 검증

- 등록 0/18/36/200개, 유리/클래식, 작은 화면과 같은 공유 DeckView를 화면에 표시하지 않고 렌더링했다. 작은 타일의 숫자 배지가 아이콘을 가리지 않도록 왼쪽에 아이콘을 배치했다. 정상 1120pt 폭에서 프로필 18개는 높이 729pt, 36개는 801pt이며 최근 3.3줄 바로 아래에 등록 영역이 붙는다. 실제 프로필 변경/휠/드래그는 아직 사용자 실기 확인 대상이다.
- 순서를 유지하는 1×1/2×2/4×2 혼합 배치의 겹침/번호/앞 빈칸 비점유, 프로필 축소 후 재확대와 x/윗변 유지/음수 모니터/화면 보정, 성공한 AX와 유효 CG에서만 창 없음 판정을 검사했다. 투명 보조 표면/실패·시간 초과/실제 다른 Space 후보를 구별한다.
- XCTest 110개 및 Python 배포 정책 14개 통과. /tmp/tile-110-tests.log. 공유 앱의 최종 격리 검사/렌더링 통과 /tmp/tile-110-scroll-previews.log 및 PNG들. Swift 경고/오류 없음. 실제 배경 Glass/전역 키/접근성 수신을 이 렌더링 검사로 통과했다고 하지 않는다.
- scripts/verify-application-quit.py가 실제 임시 LSUIElement 앱을 사용자 활성화/창 없이 실행해 생산 ApplicationTermination의 nil/자기 자신/종료된 객체 거부, 정상 종료 요청/취소 존중/실제 종료를 확인했다. /tmp/tile-110-quit.log. 사용자 앱/문서/권한은 바꾸지 않았다.
- 사용자는 USBClean이 계속 창 없는 상태지만 현재 목록에는 나타나지 않는다고 확인했다. 진단 호스트는 AX 신뢰가 없고 이름/ID에 usb가 들어간 실행 앱을 찾지 못했다. 캡처의 정확한 오표시 원인이나 이 앱의 새 작은 타일 표시 성공을 확정하지 않는다.
- 사용자의 1.0.0 실기: Focus 앱 필터 설정이 로딩되고 프로필을 선택할 수 있다. 캡처의 기본 아이콘과 실제 자동 전환/해제 전체 조합은 별도 검증으로 남긴다.
- 최근 항목 1000개를 유지하면서 뷰포트와 한 큰 타일 높이의 여유만 렌더링하는 범위 검사를 통과했다. 시작/중간/끝에서 표시 대상은 30개 미만이며 마지막 999번에 접근한다. 실제 비표시 NSScrollView를 끝으로 이동한 recent-scroll-bottom.png에서 마지막 샘플 16번을 확인했다. Instruments의 실제 CPU/메모리 측정과 구별한다.
- 최종 1.1.0(15)은 소스 2d68dd1ab8e89d4047a4c2c3820e893cb1a81d3e에서 Developer ID Team VV2W9U5XT3/강화된 런타임/타임스탬프 서명, Apple 공증 ID c5910ff0-4866-4038-b5e6-c73a8904ca63 Accepted, stapler/Gatekeeper와 ZIP 재추출 검증을 통과했다. 최종 ZIP SHA-256 69468c87d82da1fd8213b0b37551a8b0a368f56fa6d5700be88fefe91954cf26, metadata cab5e5768e2b00251596dd4c83dfdb0aa53709e819f80c2616f60a64958c4634, 체크섬 파일 b62804bd37631b042892c3446da8f31b984d5627b9851186b06a3154d7995718. /tmp/tile-110-prepare.log, sign.log, notarize.log(접두사 tile-110-), 서명 실행 파일 검사 /tmp/tile-110-final-signed-previews.log.
- /Applications/launch at Login/Tile Launcher.app에 설치 후 서명/티켓/Gatekeeper를 다시 확인했다. 이전 1.0.0 Contents는 /tmp/tile-before-110-afp494ou.app에 보존했다. /tmp/tile-110-install.json에 기록하며 설치 전후 실행 소유자 파일 동일·자동 재시작/권한/사용자 데이터 변경 없음. 사용자 다시 열기에서 새 빌드로 전환한다. 현재 GitHub 공개본은 1.0.0이고 새 1.1.0 태그/릴리스를 만들지 않았다.
- 앞선 내부 후보 94613cc와 제출 ID 7a9a858e-fc8b-41a7-b991-de4b1ff69a42는 releases/v1.1.0-internal-94613cc에 보존했다. 최종 파일은 렌더링 범위 보완 후 다른 소스/제출 ID이며 최종 ID를 재조회했고 중복 업로드하지 않았다.
- R128–R129의 세 배치/회색 앱 비교는 /tmp/tile-110-three-delivery.log의 화면 없는 렌더링이다. 실제 설치 앱의 4×2/2×2 기본 정책과 구별한다. 합성 심벌을 사용해 두 시안의 아이콘/색을 비교하며 실제 앱 아이콘/유리 합성 검증으로 기록하지 않는다.

최종 검증 기록일: 2026-10-14, Asia/Seoul. 제품명 Tile Launcher, Developer ID 서명·공증 완료 1.0.0(14) GitHub 공개.

## R122–R123 · 공통 여백·Developer ID 서명·공증·공개 완료

- Developer ID Application: WonJoon Seok (VV2W9U5XT3)로 1.0.0(14)을 실제 서명했다. Apple Root CA까지의 인증서 체인, TeamIdentifier VV2W9U5XT3, 강화된 런타임 flags=0x10000, 보안 타임스탬프와 deep/strict 검증을 통과했다. entitlement는 기존 Apple Events 한 개만 유지한다. ZIP 재추출 후 서명/번들 트리/소스 5aab3564279c28e3384ffa71000ab54b3c452fea를 대조했다.
- 사용자가 공증 자격 증명의 검증·Keychain 저장 성공을 알렸고 notarytool history로 프로필을 확인했다. 개인 키·앱 암호는 채팅/파일로 받거나 출력하지 않았다. 제출 ID 913be6a2-f267-4162-a6b0-f719b717db75는 Accepted이며 stapler staple/validate와 Gatekeeper source=Notarized Developer ID를 통과했다. 제출은 한 번이며 같은 ID로 조회했다.
- 가입 완료는 사용자 보고다. 초기 valid identity는 0개였고 Xcode에서 생성 후 유효 Developer ID Application identity 1개를 확인했다. 개인 키·계정 암호를 내보내거나 출력하지 않았다. 공증 자격 증명은 별도 사용자 Keychain profile로 설정했다.
- 네 설정 탭에 공통 SettingsPaneInsets를 적용해 중복 상단 16pt를 없앴다. 같은 창/스크롤 시작의 실제 공유 SettingsView 렌더링에서 일반 첫 안내와 모양/메뉴/프로필 제목의 시작 높이를 함께 확인했다. 일반 권한→버전 간격 12pt와 바깥 여백 16pt를 사용한다. 일반 fitted 콘텐츠 샘플은 580×849pt이며 폰트/로그인 상태에 따라 달라진다.
- 기본/작은 540×638pt 창의 네 탭과 일반 하단 스크롤·빈/많은 메뉴를 렌더링했다. 비표시 native TabView는 inline 제목 영역을 추가하므로 기본 일반 본문은 별도 공유 콘텐츠 렌더링으로도 확인했다. 실제 도구 막대/ColorPicker/Glass 합성은 Xcode canvas 또는 실기 확인 범위로 구별한다.
- DeckSpacing으로 바깥 24pt·열 간 24pt·제목 아래 12pt·섹션 간격과 sizing 계산을 통일했다. 기본 오버레이 1040×719pt에서 최근 창 3줄+다음 일부와 등록 35개 3행을 확인했다. 작은 512×341pt 샘플도 렌더링했다. 타일 비율/순서·폰트·클릭/드래그 기능·기존 테마/색은 바꾸지 않았다.
- 변경된 헤더 높이에 맞춰 행 경계 검사를 수정했다. 가용 높이 570pt의 등록 3행, 560pt의 완전한 2행 및 작은 화면의 최소 두 창 행/한 등록 행을 검증했다. 극소 부동소수점 경계는 0.001pt 허용 오차로 비교한다.
- 최종 scripts/test.sh 통과: XCTest 105개, Python release 정책 14개, 실패 없음. 기존 SettingsStore/AppDelegate/HoldMonitor/메뉴/Focus 모델/사용 횟수/마스크 격리 검사도 통과했다. 컴파일 경고/오류 없음.
- 로그 /tmp/tile-100-tests.log, /tmp/tile-100-previews.log; 이미지 /tmp/tile-100-previews/settings-general-fitted.png, settings-general-580.png, settings-appearance-580.png, settings-menus-580.png, settings-registered-580.png 및 각 -540.png, classic-dark.png, glass-dark.png, compact-dark.png. 사용자 전경 앱/입력/권한을 자동 조작하지 않았다.
- 1.0.0(14)을 2026-10-14 10:01:27 KST 최신 정식 GitHub 릴리스로 공개했다. 초안에 최종 세 자산만 업로드하고 asset ID로 다시 내려받아 SHA-256을 확인한 뒤 공개했다. latest API의 tag=v1.0.0, draft=false, prerelease=false, 각 이름/크기/digest 일치와 원격 annotated tag의 peeled source 5aab3564279c28e3384ffa71000ab54b3c452fea를 확인했다. 기존 v0.17.6과 이전 공개 자산을 보존했다.
- 최종 ZIP Tile-Launcher-1.0.0-arm64.zip은 2,042,543 bytes, SHA-256 5701494a39badc522deaae10ca044695e9d1a2f911ac7304571b05d62329111e다. release-metadata.json은 7892d8d8281e86b838aa60f2820576fd9985fda5b50cb4a4dc465aa2ff31fb57, SHA256SUMS.txt는 b7031df8e90231d381ee4922c574ed28ce767b695ea5bd41e2e3a7597acf740e다. 결과 ~/Library/Developer/TileLauncher/releases/v1.0.0, 로그 /tmp/tile-100-prepare.log, sign.log, notarize.log, draft.log, publish.log(모두 tile-100- 접두사), 공개 확인 /tmp/tile-100-public-release.json 및 public-tag.txt.
- Developer ID 서명된 실제 배포 실행 파일의 --render-previews 경로도 실행해 격리된 저장/모델/키 이벤트 정책/설정 크기/메뉴 카탈로그/마스크 및 네 탭/오버레이 렌더링이 통과했다. /tmp/tile-100-signed-previews.log 및 /tmp/tile-100-signed-previews. 사용자 인스턴스 잠금·상태 아이콘·전역 입력을 시작하지 않는 경로이며 실제 접근성/Focus/드래그 검증을 대신하지 않는다.
- /Applications/launch at Login/Tile Launcher.app에 최종 공증 앱을 설치하고 codesign/stapler/Gatekeeper를 재검증했다. 기존 Contents는 /tmp/tile-before-100-kvppetd3.app에 보존했다. /tmp/tile-100-install.json에 기록하며 설치 전후 인스턴스 소유자 파일 동일, 자동 재시작·사용자 설정/권한 변경 없음. 다음 앱 열기에서 새 빌드로 전환한다. 접근성은 Developer ID 전환 후 사용자 실기 확인 대상이다.

## R120 · 0.17.6 GitHub 공개 완료

- 사용자가 R119의 여백 개선을 다음으로 미룬 채 현재 GitHub 릴리스를 요청해 R113의 바이너리 게시 보류를 해제했다. 앱 UI 코드는 수정하지 않는다.
- scripts/test.sh 전체 재실행 통과: Swift XCTest 105개, 배포 정책 Python unittest 14개, 실패 0개. 로그 /tmp/tile-0176-release-tests.log. 네이티브 입력/Focus/권한의 실제 수신을 이 단위 검사로 검증했다고 하지 않는다.
- 대상 저장소 colaH16/tile-launcher는 PUBLIC/main이며 기존 공개본은 v0.16.3과 v0.17.1이다. v0.17.6 충돌이 없음을 확인했다. 현재 개발용 ad-hoc 서명·미공증 선택을 유지하며 여백 문제와 Focus 제한을 릴리스 노트에 명시했다.
- 소스 eb36d246b52b1fb418fa2e475885b5c87c0382b9의 git archive에서 독립 최적화 빌드·App Intents 추출·ad-hoc 서명/strict 검증 통과. 빌드 경고/오류 없음. 번들 버전 0.17.6(13), arm64/macOS 26, 앱 아이콘·실행 권한·Focus 메타데이터·소스 리비전을 확인했다. ZIP을 다시 풀어 앱 트리 해시와 서명을 대조했다. 배포 빌드 식별자는 b58d735ee63c8052d2a9fb394684e4379c047e2d099797f6dd6092925feb9fd9다.
- 결과는 ~/Library/Developer/TileLauncher/releases/v0.17.6에 보존한다. ZIP Tile-Launcher-0.17.6-arm64-unnotarized.zip, 2,033,030 bytes, SHA-256 ffbde9caccf19436f4947f879f0865b38901c2794ebfd960456697232d34068d. release-metadata.json SHA-256 77e4029c567b0054f7caf2b5b3ebbabc2f2da0acebee4430f67179d405b5112b, SHA256SUMS.txt SHA-256 71921fb9362db052a02f237297ae8a23751f8647e1c731674cd51fff6a0e3b6b.
- 초안에 세 자산만 업로드하고 asset ID로 다시 내려받아 각 SHA-256을 확인한 뒤 공개했다. GitHub latest API에서도 tag=v0.17.6, draft=false, prerelease=false, 세 자산 이름·크기·서버 digest 일치를 확인했다. 원격 annotated tag의 peeled commit은 위 소스 리비전과 같다. 기존 v0.16.3/v0.17.1을 수정하지 않았다.
- 공개 시각 2026-10-13 17:03:03 KST. [정식 릴리스](https://github.com/colaH16/tile-launcher/releases/tag/v0.17.6) · [ZIP](https://github.com/colaH16/tile-launcher/releases/download/v0.17.6/Tile-Launcher-0.17.6-arm64-unnotarized.zip). 로그 /tmp/tile-0176-release-prepare.log, release-draft.log, release-publish.log(모두 tile-0176- 접두사), 공개 확인 /tmp/tile-0176-public-receipt.json.
- 개발용 ad-hoc 서명·Apple 미공증 및 Focus 제한을 공개 노트에 명시했다. R119의 여백 균일화는 다음 작업이며 이번에 고치지 않았다. 이 배포 준비/게시에서 사용자 설치 앱을 교체·실행하거나 설정/권한을 변경하지 않았다.

## R118 · 일반 내용에 맞춘 초기 창 높이

- R119 사용자 후속 실기: 0.17.6에서 내용은 표시되지만 상단 안내 위·권한 박스와 버전 사이·버전 아래 여백이 달라 보인다는 캡처를 받았다. 초기 높이 조정과 여백 균일화의 완료를 구별한다. 여백 통일은 다음 UI 작업으로 보류하며 이번에는 문서 기록만 한다.

- 사용자의 0.17.5 실기 캡처에서 네 개 탭과 일반 권한 표시는 정상이고 초기 창의 버전 아래 여백이 과한 것을 확인했다. 직접 줄인 첫 캡처의 크기를 목표로, 1000pt 고정을 제거하고 일반의 실제 높이를 측정하도록 바꿨다.
- 실제 일반과 측정에 공유 GeneralSettingsContent를 사용한다. 폭 580pt에서 설정 바깥 좌우 여백을 제외한 548pt로 NSHostingView의 fittingSize를 읽고 세로 바깥 여백을 더한다. 본문은 세로 압축하지 않는다. 내부 하단 padding을 없애 바깥 16pt 여백과 중복되지 않게 했다. 초기/닫힌 창 재열기에서만 적용하고 이미 보이는 창의 사용자 크기는 유지한다.
- 최종 격리 샘플의 측정 콘텐츠 크기는 580×869pt로 기존 580×1000pt보다 131pt 작았다. 실제 일반 내용과 바깥 여백을 이 크기로 렌더링해 안내문 줄바꿈·권한 두 버튼/설명·마지막 버전이 모두 보이고 아래에 기본 여백만 남는 것을 확인했다. 이 높이는 로그인 상태·글꼴/OS 레이아웃 등에 따라 달라질 수 있으며 고정 규격이 아니다.
- 실제 공통 AppKit 적용 검사 통과: 측정값 적용, 수동 800×850pt 변경 허용, 재적용 후 측정 크기 복원, 작은 1024×768pt 작업 영역의 프레임 크기·최소 크기 제한. 작은 540×638pt 콘텐츠에서 실제 NSScrollView를 끝까지 이동해 권한/버전에 접근했다. 메뉴의 가변 목록·하단 추가 및 빈 목록도 렌더링했다.
- 파일 /tmp/tile-0176-previews/settings-general-fitted.png, settings-general-540-bottom.png, settings-menus-580.png, settings-menus-540.png 및 settings-menus-empty.png, 로그 /tmp/tile-0176-previews.log. 실제 일반 본문을 직접 렌더링해 비표시 창의 inline 탭 높이를 실제 시스템 도구 막대 높이와 중복 계산하지 않았다. 실제 사용 화면에서의 초기 프레임/도구 막대 합성은 격리 검사와 구별하며 사용자 화면을 자동 조작하지 않았다.
- 기존 즉시 클릭/설정 이동/웹 앱 아이콘/재입력/메뉴 카탈로그/저장/횟수/Focus 모델/마스크의 격리 검사도 통과했다. 최종 debug 및 최적화 빌드에서 경고/오류 없음. DeckCore는 변경하지 않아 이전 105개 전체 XCTest를 새로 실행했다고 기록하지 않는다.
- 0.17.6(13) 최적화 빌드·App Intents 추출·ad-hoc deep/strict 서명 검증 통과. /tmp/tile-0176-build.log, 빌드 식별자 247adb4ad5c7c60307a7bfcab829685756f6ac3e5005422994741cba77c8ba9e.
- /Applications/launch at Login/Tile Launcher.app에 설치 후 서명을 재검증했다. 이전 0.17.5 Contents를 /tmp/tile-before-0176-4o0lsr8y.app에 보존했고 /tmp/tile-0176-install.json에 기록했다. 설치 전후 인스턴스 소유자 기록 동일, 앱 자동 재시작·사용자 데이터/권한 변경 없음. 사용자가 다시 열면 새 빌드로 전환한다.
- R113에 따라 소스만 푸시하며 새 태그/바이너리 릴리스는 보류한다. 공개본 0.17.1은 유지한다.

## R116–R117 · 일반 권한 복귀·지정한 세로형 기본 크기

- 사용자 실기에서 0.17.4의 다섯 탭이 좁은 창의 도구 막대 overflow로 접히고 가로 확장 후 본문 여백이 과해짐을 확인했다. 권한을 일반 하단으로 합치고 네 개 탭으로 복귀했다. 창의 접근성 제목은 유지하며 titleVisibility를 hidden으로 설정해 도구 막대에 중복 제목 공간을 요구하지 않게 했다.
- 기본 콘텐츠 크기는 공통 SettingsWindowLayout의 580×1000pt다. AppDelegate는 처음 생성/닫힌 창 재열기에서 크기 적용 후 가운데에 놓는다. 기존에 보이는 창이면 이 적용을 건너뛰므로 탭만 바꿀 때 사용자 크기를 유지한다. resizable 스타일을 유지했고 사용자 설정/권한/로그인 항목을 바꾸지 않았다.
- 실제 NSWindow에 공통 크기 함수를 적용하는 격리 검사 통과: 580×1000pt 콘텐츠, resizable 유지, 800×850pt 수동 변경 허용, 다시 적용 후 기본 크기 복원, 1024×768pt 작업 영역에서 네 변 24pt 여백에 대응하는 프레임 크기 제한 및 최소 크기 조정. 이 창은 화면에 표시하지 않았다. AppDelegate의 실제 화면 재열기/도구 막대 합성은 이 함수 검사와 구별한다.
- 실제 SettingsView와 격리된 설정·가상 앱·24개 메뉴를 580×1000pt 및 540×638pt 콘텐츠에서 렌더링했다. 기본 일반 탭의 권한 두 버튼/설명·버전이 모두 보였고 작은 일반 탭은 실제 NSScrollView를 끝까지 이동해 해당 항목에 접근했다. 기본 메뉴 목록은 샘플 8개와 다음 행 일부, 메뉴 추가는 하단에 표시했다. 빈 목록 및 작은 창도 렌더링했다. 행 수는 실제 줄바꿈/로그인 안내에 따라 달라진다.
- 출력 /tmp/tile-0175-previews/settings-general-580.png, settings-general-540-bottom.png, settings-menus-580.png, settings-menus-540.png, settings-menus-empty.png. 로그 /tmp/tile-0175-previews.log. 비표시 탭 컨트롤의 축소/검은 선택 표시 한계는 이전과 같으며 실제 도구 막대 외관/overflow 해소를 이 PNG로 검증했다고 하지 않는다. 사용자 화면/키보드를 자동 조작하지 않았다.
- 기존 즉시 클릭/설정 이동/웹 앱 아이콘/재입력/메뉴 카탈로그/저장/횟수/Focus 모델/마스크의 네이티브 격리 검사도 통과했다. 최종 debug 렌더링과 최적화 빌드에는 컴파일 경고/오류가 없었다. DeckCore 변경이 없어 이전 105개 XCTest 전체를 다시 실행한 것으로 기록하지 않는다.
- 0.17.5(12) 최적화 빌드·App Intents 추출·ad-hoc deep/strict 서명 검증 통과. /tmp/tile-0175-build.log, 빌드 식별자 6bf25a95151db82e78b4837b11848ad1210892cadf65776e447825f72753f5cb.
- /Applications/launch at Login/Tile Launcher.app에 설치 후 서명을 재검증했다. 기존 0.17.4 Contents는 /tmp/tile-before-0175-ozkv55vx.app에 보존하고 /tmp/tile-0175-install.json에 결과를 남겼다. 인스턴스 소유자 기록은 설치 전후 동일했다. 앱을 자동 재시작하거나 사용자 데이터·권한을 변경하지 않았다.
- R113에 따라 소스만 푸시하고 새 태그/바이너리 릴리스는 보류한다. 공개본 0.17.1은 유지한다.

## R114–R115 · 일반 하단 잘림과 메뉴 목록 공간

- 실제 SettingsView/GeneralSettingsView/MenuSettingsView/PermissionsSettingsView를 고유 UserDefaults와 가상 앱·24개 메뉴로 화면에 표시하지 않는 NSWindow에 렌더링했다. 기본 640×820pt 콘텐츠와 최소 540×660pt 창 프레임에 대응하는 540×638pt 콘텐츠를 확인했다. SettingsLayoutPreview는 Xcode Canvas에서도 재사용한다.
- 기본 창에서 일반의 시작·재입력·숫자·최근 창 설정과 마지막 버전이 모두 보였다. 작은 창에서는 실제 NSScrollView를 화면 밖 창 안에서 끝까지 이동해 최근 창·버전에 접근하는 검사 및 이미지 확인을 통과했다. 권한 두 버튼과 설명은 별도 탭 안에 들어갔다. 긴 실제 로그인 오류 안내까지 재현한 검사는 아니며 스크롤을 유지한다.
- 메뉴 목록의 180pt 고정을 제거했다. 기본 창의 세 줄 샘플 행은 5개, 작은 창에서는 2개와 다음 행 일부가 보였고 메뉴 추가 버튼이 두 크기 모두 하단에 남았다. 실제 메뉴의 제목/경로 줄바꿈에 따라 행 수는 달라진다. 24개 메뉴와 빈 목록을 각각 렌더링했으며 핀/순서/삭제/횟수와 빈 목록 안내를 확인했다. 긴 설명은 기본 접힘, 펼친 경우 상단 스크롤로 접근하는 구조다. 안내 펼침의 실제 입력은 별도 실기 범위다.
- 파일: /tmp/tile-0174-previews/settings-general-640.png, settings-general-540.png, settings-general-540-bottom.png, settings-menus-640.png, settings-menus-540.png, settings-menus-empty.png, settings-permissions-640.png 및 settings-permissions-540.png. 로그: /tmp/tile-0174-previews.log. 비표시 네이티브 탭 컨트롤의 글자/선택 표시는 축소·검게 렌더링되는 한계가 있어 이를 실기 외관 확인으로 설명하지 않는다. 창을 화면에 띄우거나 시스템 입력/권한을 조작하지 않았다.
- 기존 클릭 즉시 실행/숫자 대기·설정 이동·웹 앱 아이콘·재입력·메뉴 카탈로그·Focus 모델/저장·횟수/기간·surface 마스크의 격리 검사도 통과했다. DeckCore는 변경하지 않았고 이전 105개 전체 XCTest를 이번에 다시 실행한 것으로 표시하지 않는다.
- 0.17.4(11) 최적화 빌드, App Intents 추출, ad-hoc 서명 및 deep/strict 검증 통과. 컴파일 경고/오류 없음. 로그 /tmp/tile-0174-build.log, 빌드 식별자 f7a51f9b1b24c517124328fd474f7632acabe2d9b047fe7c46999418261fa0f7.
- /Applications/launch at Login/Tile Launcher.app에 Contents를 교체해 설치하고 서명을 재검증했다. 이전 0.17.3 Contents는 /tmp/tile-before-0174-55p1gklb.app에 보존했다. /tmp/tile-0174-install.json에 결과를 기록했고 설치 전후 인스턴스 소유자 기록은 동일했다. 사용자 데이터/권한을 변경하거나 앱을 자동 종료·재실행하지 않았다. 사용자가 다음에 다시 열면 새 UI를 사용한다.
- R113에 따라 소스만 커밋·푸시하며 새 태그/릴리스/바이너리는 게시하지 않는다. 공개본은 0.17.1이다.

## R112 · 수동 메뉴 검색의 시스템 메뉴 제외·시트 확장

- 자동 수집과 달리 수동 카탈로그는 Apple 루트까지 순회하던 차이를 확인했다. AXMenuBar 첫 시스템 루트를 건너뛰고 경로/최종 후보에서도 공유 Apple 정책을 적용했다. 중복 경로는 기존처럼 후보에서 제외하며 사용자 저장 항목은 변경하지 않았다.
- 실제 MenuCatalog 결과 경계의 격리 검사 통과: Apple//대소문자·공백 루트, Recent Items/Location 하위 전체 제외, Finder의 Settings 및 File → Apple → Export 보존, 중복 후보 제거. 실제 AX 메뉴 전체 수신은 해당 합성 검사와 구별한다.
- 부모 콘텐츠 580×760/540×660/900×1100pt에서 시트가 부모 안에 들어가고 높이의 대부분을 사용하는 계산 검사를 통과했다. 실제 메뉴 추가 시트와 동일한 MenuAdditionSheet를 오프스크린 렌더링했다. 기본 540×696pt에서 단일 행 샘플 15개, 작은 500×596pt에서 직접 입력을 펼친 샘플 10개와 다음 행 일부가 보였다. 검색/제목/완료/직접 입력이 잘리지 않음을 이미지로 확인했다. 실제 행 수는 메뉴 줄바꿈과 부모 크기에 따라 달라진다.
- 렌더링 파일은 /tmp/tile-0173-previews/menu-addition-large.png 및 menu-addition-compact.png, 로그는 /tmp/tile-0173-previews.log다. 이전 클릭/설정 이동/아이콘/재입력/사용 기록/마스크 네이티브 격리 검사도 통과했다. 사용자 화면을 조작하거나 전경 앱의 메뉴를 자동 열지 않았다. 실제 부모 창 리사이즈와 AX 수신은 사용자 실기 확인 범위다.
- 0.17.3(10) 최적화 빌드·App Intents 추출·ad-hoc 서명 및 strict 검증 통과. 컴파일 경고/오류 없음. /tmp/tile-0173-build.log에 기록했다. 빌드 식별자 a4c109ece3a30dc1477ab51f13811810a96fd2d2ebb503e135ae1c652c03c926.
- /Applications/launch at Login/Tile Launcher.app의 Contents를 교체하고 서명을 재검증했다. 이전 Contents는 /tmp/tile-before-0173-nbuey5y7.app에 보존했다. 설치 전후 인스턴스 소유자 기록이 동일했다. 앱을 자동 종료/재실행하지 않았고 사용자 데이터/권한은 변경하지 않았다. GitHub 소스만 푸시하며 공개 릴리스는 0.17.1이다.

## R109–R111 · 클릭 즉시 실행·설정 경로·앱 관리 알림

- 최초 f5b81df 및 54fa9ee 이후 이력을 읽어 클릭이 Option 해제까지 대기하던 공통 처리기를 확인했다. 최근 재입력 시간 패치만의 회귀로 설명하지 않는다. 클릭은 즉시 실행하고 숫자 선택만 해제까지 대기하도록 수정했다.
- 격리 UserDefaults를 주입한 실제 AppDelegate/HoldMonitor 검사 통과: Option 유지 중 비고정·고정 클릭 즉시 실행, 고정 보존, 이전 숫자 대기 취소, 해제 시 중복 없음, 숫자 대기는 합성 release 이벤트에 한 번 실행한다. 전역 모니터/실제 입력/앱 실행/설정 창 표시는 사용하지 않았다.
- 실제 SettingsNavigation 검사 통과: 일반/등록 항목·프로필/현재 앱 메뉴 추가, 같은 메뉴 추가 반복 요청 구별, 탭 변경 시 추가 요청 초기화. SwiftUI TabView/메뉴 추가 sheet는 컴파일했으며 눈에 보이는 시트·포커스·앱 메뉴 읽기 실기는 별도다. 시트 안에서도 실행 앱 목록을 새로고침할 수 있다.
- 사용자가 등록 앱 실행 경고를 재현했다. 15:20:25 KST 로그에 TileLauncher PID 43227의 SystemPolicyAppBundles 검사 Unknown 및 특정 Safari 웹 앱 묶음의 승인 거부가 있고, 이어 아이콘 조회 로그와 15:20:28 웹 앱 실행이 보였다. 정확한 내부 쓰기 작업은 아직 미확인이다. 앞서 설정 UI는 full을 표시했지만 실제 검사 결과와 달랐다. 부수 메타데이터/아이콘 처리·개발용 신원 영향은 가능성으로 구별한다. 원시 로그는 /tmp/tile-registered-app-denial.log와 /tmp/tile-denial-precise.log에만 두며 사용자 웹 앱 경로/캡처를 저장소에 복사하지 않았다.
- 앱 관리는 업데이트/삭제용이라는 Apple 설명과 런처의 앱 파일 수정 기능 부재를 확인했다. Safari 웹 앱 아이콘은 명시한 리소스에서 직접 로드하고 앱 실행은 openApplication으로 분리했다. 실제 AppIconCache의 격리 리소스 읽기·원본 plist 보존·경로 이탈 기본 심벌·일반 앱 구별 검사 통과. 경고가 사라졌다는 실기 판정은 아직 하지 않았다.
- 접근성/앱 관리 확인 버튼을 구별하고 권한 용도를 설명했다. Privacy_AppBundles 앵커는 15:08:01의 기존 System Settings URL 처리 로그로 확인했다. 앱 관리 필수 권한 안내·자동 승인·TCC 초기화·전체 디스크 접근 요청은 하지 않았다.
- 기존 설정·메뉴 사용 기록·Focus 모델·재입력 보정·마스크 검사도 격리 실행에서 통과했다. /tmp/tile-0172-final-previews.log에 기록했다. DeckCore 변경이 없어 이전 전체 105개 검사를 새로 실행한 것으로 표시하지 않는다.
- 최종 최적화 빌드·App Intents 메타데이터 추출·ad-hoc 코드 서명/strict 검사 통과. /tmp/tile-0172-final-build.log에 기록했다. UI/실행 경로 보완을 동일한 미전달 패치 0.17.2(9)에 묶었고 내부 후보 재컴파일은 번호를 추가 소비하지 않았다.
- 최종 빌드 식별자 **1e1ae3e9c5fce3b7253ce01ddf0ef5f067d2c290b8f9f67baf792f014c513296**, 0.17.2(9)를 /Applications/launch at Login/Tile Launcher.app에 설치하고 서명을 재검증했다. 기존 0.17.0 Contents는 /tmp/tile-before-0172-f95oe3ea.app, 중간 후보는 /tmp/tile-before-0172-final-3scyzwfh.app에 보존했다. 설치 전후 인스턴스 소유자 기록이 동일했고 실행 중 앱을 자동 종료/재시작하지 않았다. 사용자 데이터/OS 권한은 변경하지 않았다.
- 클릭/설정 시트·권한 링크와 등록 앱 경고의 실제 확인은 사용자가 새 앱을 다시 연 뒤 진행한다. 소스·요청 기록만 푸시하며 GitHub 공개 태그/바이너리는 0.17.1을 유지한다.

## R108 · 기본값 0.6초 패치 및 공개 준비

- 사용자 피드백에 따라 기본값·설명·잘못된 값 복원 기준을 0.6초로 변경했다. 기존에 저장한 유효한 값은 유지한다. 새 기능 없이 patch 0.17.1(8)로 올렸다.
- 변경 대상 OptionReopenTests **9개, 실패 0개**. 600ms 경계 포함/초과·일회성 복원·비활성화·설정 누락/손상·기존 0.8초 설정 보존을 확인했다. 로그는 /tmp/tile-0171-tests.log다. 기존 0.17.0 전체 검사 105개 결과와 구별한다.
- 화면 없는 실제 SettingsStore/HoldMonitor 통합 검사를 통과했다. 기본 0.6초·사용자 지정 값 저장·기존 데이터 보존·550ms 즉시 복원·타이머 중복 열기 없음·중간 입력 취소·정상 호출/단일 실행을 확인했다. /tmp/tile-0171-previews.log에 기록했다. 사용자 전경 앱/키 입력/실행 프로세스를 조작하지 않았다.
- 깨끗한 소스 커밋에서 별도 배포 폴더로 패키징하고 GitHub 초안에 올린 뒤, 파일 재다운로드·SHA-256 대조를 통과해야 공개한다. 최종 결과는 아래에 추가한다. 기존 v0.16.3 자산과 사용자 설치 앱은 보존한다.
- 소스 **31133fec941bd3e894c408b45437cda3d3a38e14**를 git archive로 분리해 최적화 빌드·ad-hoc 서명·코드 무결성·아이콘/Focus 메타데이터·버전/소스/arm64 검사와 ZIP 재추출 트리 해시 검사를 통과했다. local_only=false, prerelease=false, 0.17.1(8). 컴파일 경고/오류 없음. /tmp/tile-0171-release-prepare.log 및 배포 폴더 build.log에 기록했다.
- ZIP 1,958,572바이트, SHA-256 **db7b8ec8ae05e2ad5e0a8e864a73693c75e1a18a821fdd087483fdaa9657020d**. 배포 폴더는 ~/Library/Developer/TileLauncher/releases/v0.17.1이다. 메타데이터·SHA256SUMS.txt와 함께 초안에 올리고 세 파일을 다시 내려받아 각각 대조했다. /tmp/tile-0171-release-draft.log 및 /tmp/tile-0171-release-publish.log에 기록했다.
- **2026-10-13 14:55 KST 공개 완료**: https://github.com/colaH16/tile-launcher/releases/tag/v0.17.1 . GitHub latest 응답의 tag/draft=false/prerelease=false와 세 자산 uploaded/서버 digest 일치를 재확인했다. 이전 v0.16.3 ZIP의 서버 해시도 c8a598d4…66c0d로 기존 기록과 일치했다.
- 사용자 설치 앱/프로세스·권한·설정은 변경하지 않았다. Developer ID 서명·공증·Focus 제한 해결이나 모든 지원 OS에서의 실기 검증을 뜻하지 않는다.

## R104–R107 · 설정 가능한 Option 재입력 보정

- 사용자 측정·선호에 맞춰 기본 시간을 0.8초로 변경했다. 일반 설정에서 켜기/끄기 및 0.1–2.0초를 0.1초 단위로 저장한다. 내부 0.15/0.3초 후보는 전달본으로 세지 않았으며 새 동작·설정을 0.17.0(7) 한 번으로 반영했다.
- XCTest **105개, 실패 0개**: 기본 800ms 경계 포함/초과, 0.1/0.3/1.2/2.0초 지정 경계, 일회성 위치 기억, 연속 해제, 끄기, 명시적 닫기/실행/비정상 시각 제외, 설정 누락·잘못된 값 복원을 포함한다. Python 배포 정책 **14개 통과**. 로그는 /tmp/tile-0170-tests.log다.
- 실제 HoldMonitor에 합성 NSEvent를 직접 전달하는 화면 없는 검사를 통과했다. 750ms 재입력 즉시 복원, 남은 250ms 타이머의 중복 열기 없음, 중간 키 입력의 복원 취소, 일반 호출 대기 및 선택 동작 1회 실행을 확인했다. 전역 모니터를 설치하거나 OS 키 입력을 주입하지 않았다.
- 격리 UserDefaults를 사용하는 실제 SettingsStore에서 기본 0.8초, 끄기/1.2초, 다시 켜기/0.3초의 저장·복원을 확인했다. 기존 프로필·명령·색·기간 설정 보존 검사도 통과했다. 사용자 설정은 테스트에서 쓰지 않았다.
- 새 네이티브 설정 그룹을 화면에 띄우지 않고 렌더링해 설명·0.8초·Stepper가 잘리지 않음을 이미지로 확인했다(/tmp/tile-0170-previews/option-reopen-settings.png). 기존 미리보기 검사도 통과했다. 로그는 /tmp/tile-0170-previews.log다. 실제 키 접점/반응 시간, 전역 이벤트 전달, 눈에 보이는 오버레이 위치 복원은 사용자 실기 확인이 남아 있다.
- 최적화 빌드·App Intents 메타데이터 추출·ad-hoc 코드 서명 및 strict 검증 통과. 버전 0.17.0(7), 빌드 식별자 97afeb8db79f83e424f076c3ba0da65b365405d0a9ecde444ab08b08b2e98af7. 컴파일 경고/오류 없음. 로그는 /tmp/tile-0170-build.log다.
- 현재 설치 경로 /Applications/launch at Login/Tile Launcher.app의 Contents를 교체하고 서명을 재검증했다. 상위 폴더에는 쓰기 권한이 없어 같은 볼륨의 /tmp에서 준비했으며 소유권/권한은 변경하지 않았다. 이전 Contents는 /tmp/tile-before-0170-1ujpngv3.app에 보존했다. 실행 중 프로세스를 종료/재실행하지 않았고 설치 전후 인스턴스 소유자 기록이 동일했다. 사용자가 다시 열 때 새 빌드로 전환한다.
- GitHub 공개 태그/바이너리는 변경하지 않았다. Developer ID 서명·공증이나 Focus 제한 해결을 뜻하지 않는다.

## R103 · 배포본 Focus 오류 읽기 진단

- Applications/launch at Login의 0.16.3(6)이 실제 실행 중이며 Launch Services의 기본 경로도 일치함을 확인했다. codesign 무결성 통과, Signature=adhoc / TeamIdentifier 없음. 유효한 서명 identity는 0개다.
- AppIcon.icns와 Focus intent/entity/query 메타데이터 존재 및 linkd의 새 경로 메타데이터 등록 로그를 확인했다. 별도 화면 없는 NSWorkspace 검사에서 유효한 아이콘(32개 표현)과 최종 심벌 PNG를 확인했다. 아이콘 파일 누락으로 설명하지 않는다.
- 14:02–14:04 linkd에서 Unable to get teamId 오류가 반복되고 FocusSettingsExtension 연결이 약 32초 후 ProcessRegistry.Errors Code=0으로 실패했다. BackgroundShortcutRunner의 앱 definition 조회 실패도 있었다. 사용자가 제공한 최종 오류 화면과 시간대가 일치한다.
- 사용자/시스템 설정·프로세스·앱 파일·Launch Services 캐시는 변경하지 않았다. 등록 3개가 남아 있어도 실제 기본 경로는 설치 앱이다. 원시 로그는 /tmp/tile-focus-diagnostic.log 및 /tmp/tile-focus-lsregister.txt에만 두고 앱 관련 증거를 focus-diagnostics.md에 요약했다.
- 직접 확인된 차단점은 Team ID 없는 앱의 identity 생성 실패다. Apple 서명 전후 비교는 인증서 부재로 아직 수행할 수 없다. 아이콘 누락과의 인과관계 및 서명 후 전체 Focus 동작은 미검증이다. 문서만 변경하므로 새 버전/빌드/코드 테스트는 만들지 않는다.

## R102 · v0.16.3 정식 GitHub 릴리스 공개

- 사용자 게시 승인·colaH16 GitHub CLI 인증·지정 저장소 PUBLIC을 확인했다. 소스 5388c2c400c8dd9b084538adf6f74385eabfe27b의 깨끗한 git archive를 독립 경로에서 빌드했다. 앱 기능/실행 중 프로세스/사용자 설정은 바꾸지 않았다.
- 버전 0.16.3(6), arm64, macOS 26 이상, ad-hoc, local_only=false. 코드 서명·실행 권한·아이콘·Focus 메타데이터·버전/소스·ZIP 재추출 트리 해시 검증 통과. 컴파일 경고/오류 없음. ZIP 1,941,375바이트. /tmp/tile-0163-release-prepare.log와 배포 폴더 build.log에 기록했다.
- 첫 게시 때 태그 조회 REST API가 초안을 반환하지 않아 404로 중단됐다. 인증된 릴리스 목록을 페이지별로 조회하고 중복 초안을 거부하도록 수정했다. asset ID로 내려받아 체크섬을 대조하고 같은 release ID로 게시한다. 새 초안/중복 업로드/태그 변경 없이 기존 초안을 사용했다.
- 배포 정책 테스트 **14개 통과**. 추가 검사는 뒤 페이지의 초안, 없는 태그, 중복/잘못된 목록 거부다. /tmp/tile-0163-publication-tests.log에 기록했다. 앱 코드는 바꾸지 않아 XCTest/실기 UI를 반복하지 않았다.
- ZIP·release-metadata.json·SHA256SUMS.txt를 GitHub에서 다시 다운로드해 로컬 해시와 모두 일치함을 확인한 뒤 공개했다. /tmp/tile-0163-release-draft.log와 /tmp/tile-0163-release-publish.log에 기록했다.
- **2026-10-13 13:59 KST 공개 완료**: https://github.com/colaH16/tile-launcher/releases/tag/v0.16.3 . releases/latest 응답에서 v0.16.3, draft=false, prerelease=false, 자산 3개 uploaded 및 서버 SHA-256을 확인했다. 비인증 API는 공유 IP 한도(403)였지만 별도의 비인증 공개 웹 페이지와 ZIP 다운로드 HEAD는 모두 HTTP 200이었다.
- ZIP SHA-256: c8a598d4f1d147d846e04480cbbfcf1285bf2d0bc3ab359558289d0b3ae66c0d.
- 공개 태그는 소스 5388c2c를 유지한다. 이후 배포 도구 수정·공개 완료 문서는 main에 별도 커밋하고 공개 앱/파일/버전을 바꾸지 않는다. Apple Developer ID 서명·공증은 아직 수행하지 않았다.

## R99–R101 · 버전 재정리·Apple 메뉴 제외·UI 보완

- CHANGELOG.md의 26단계 번호 순서와 현재 release/config.json/릴리스 노트의 0.16.3(6) 일치를 확인했다. 과거 실제 표시 버전과 소급 번호를 구분했다. 잠정 0.20.2 후보는 설치하지 않았으며 공개 태그/Release/ZIP을 만들지 않았다.
- XCTest **96개, 실패 0개**. 추가 3개는 Apple/ 루트·하위 메뉴 제외와 같은 이름의 앱 메뉴 허용, Help 우회 차단, 과거 자동 시스템 기록의 최근 5개/빈도 제외 및 핀/수동 등록·기록 보존이다. 정책 검사이며 실제 외부 메뉴 클릭을 자동 수행하지 않았다. 기존 Copy/Paste 포함·취소/단축키 제외 검사도 통과했다.
- Python 배포 정책 **12개 통과**. 첫 실행은 후보 번호 변경 중 릴리스 노트 제목이 달라 일치 검사가 실패했으며, 최종 번호/제목을 맞춘 후 재실행해 통과했다. 기록: /tmp/tile-0163-tests.log, /tmp/tile-0163-release-tests.log.
- 읽기 전용으로 저장된 자동 메뉴의 Apple 루트 2개를 확인했다. 사용자 메뉴 이름/목록은 저장소에 복사하지 않고 실제 저장 기록도 직접 수정하지 않았다. 다음 앱 실행 시 필터가 적용된다. 기존 자동 기록은 설정에서 확인할 수 있으며 직접 고정/수동 등록은 유지한다.
- 화면 없는 SettingsStore 통합 검사·기본 두 테마/명암·사용자 색·작은 배치 렌더링 통과. 1pt 유리 확장 뒤 콘텐츠 좌표/크기가 원래 표면과 같고, 512×420 및 1040×720의 네 모서리 1×/2× alpha 검사 통과. /tmp/tile-0163-previews 및 같은 이름의 .log에 저장했다.
- hover는 메뉴/창의 실제 SwiftUI Surface 상태와 채움/2pt 테두리에 연결했고 글자 아래만 칠한다. 등록 타일은 변경하지 않았다. 화면 없는 일반 미리보기는 실제 커서 hover/WindowServer 굴절·그림자를 검증하지 못한다. 사용자가 보고한 좌우 선의 최종 해소도 아직 확인되지 않았다.
- 배경 색 레이어는 0.72→0.28, 타일은 그대로다. 투명도 줄이기는 불투명을 유지한다. 네이티브 NSGlassEffectView regular와 단일 마스크를 유지하며 효과만 1pt 확장했다. OS 굴절을 수동으로 왜곡하거나 가짜 배경 캡처로 구현하지 않았다.
- 최종 디버그/릴리스 컴파일·App Intents 추출·개발용 ad-hoc 서명 검증 통과. 로그에 컴파일 경고/오류 없음. /tmp/tile-0163-build.log에 기록했다.
- 설치 fingerprint는 fdf65cd9e31b55cb1bcd09751c358cbae0e952c323183863e79d356e17a221f2, 이전 Contents 백업은 /tmp/tile-before-0163-cba3uum4다. 안정된 개발 경로에 설치 후 서명을 재검사했고 실행 소유자 기록은 동일하다. 자동 재시작/Computer Use/공개 바이너리 게시는 하지 않았다.

## R96–R98 · 모서리 검은 선 패치와 버전 표시

- 사용자 스크린샷에서 모서리 바깥 검은 선을 확인했다. 기존 구성은 SwiftUI의 연속 곡선 배경과 마스크 없는 NSGlassEffectView를 함께 사용했다. 화면을 띄우지 않는 AppKit 검사에서 glass/content holder/hosting layer에 외곽 마스크가 없음을 확인했다. 이것만으로 WindowServer의 정확한 검은 픽셀 발생 원인을 단정하지 않는다.
- 새 DeckSurfaceView는 유리와 콘텐츠 전체를 한 연속 곡선 마스크로 자르며 크기가 달라질 때만 경로를 갱신한다. 기존 타일·불투명도·등록 선반·창 크기는 바꾸지 않았다. NSWindow 그림자를 유지하고 최초 레이아웃 후 다시 계산하도록 했다.
- 화면 없는 생산 표면 검사 통과: 512×420에서 1040×720으로 같은 뷰의 크기를 바꾸고 1×/2×로 레이어를 렌더링했다. 네 모서리의 5×5pt 영역은 alpha 0, 내부는 채움 유지였다. 처음에는 AppKit 레이아웃/레이어 커밋 전 렌더링해 내부 채움 검사가 실패했으며, 레이아웃 커밋 후 검사하도록 보정해 통과했다. 창은 order/makeKey 하지 않았다.
- 기존 설정/Focus/메뉴 횟수 저장의 격리 검사와 클래식·유리, 라이트·다크, 사용자 색·작은 레이아웃 렌더링을 완료했다. `/tmp/tile-021-previews`와 `/tmp/tile-021-previews.log`에 기록했다. 실제 데스크탑 Glass 합성·창 그림자·드래그 잔상 해소는 사용자 재실행 후 확인 대상이다.
- Python 배포 정책 테스트 12개 통과(`/tmp/tile-021-release-tests.log`). 릴리스 노트 제목과 현재 설정 버전의 일치를 검사하도록 버전 고정 테스트를 수정했다. 순수 DeckCore 정책은 바꾸지 않아 기존 XCTest 93개 전체를 이번에 반복하지 않았다.
- 개발용/배포용 버전 원본은 release/config.json 하나이며 이번은 0.2.1(5)다. 개발 앱 번들에서도 같은 버전/빌드, 아이콘, Focus 메타데이터를 확인했다. 설정의 고정된 ‘0.2’ 문자열 대신 시작 시 읽은 번들 정보를 표시한다.
- 디버그/릴리스 컴파일, App Intents 추출과 개발용 ad-hoc 코드 서명 검증 통과. 로그는 `/tmp/tile-021-build.log`다. 새 fingerprint는 `0f0691cdbd731c7aab2d5d5a4f075690766ab27e79c7ab4183e8bd2c588aded1`이다.
- 안정된 개발 경로에 설치하고 서명을 재검사했다. 이전 Contents는 `/tmp/tile-before-021-lynjvtcl`에 보존했으며 설치 전후 실행 소유자 기록은 동일하다. 사용자의 앱을 자동 종료/재실행하지 않았다. GitHub 태그/자산/릴리스는 생성하지 않았고 이전 0.2.0 배포 ZIP은 이번 패치의 산출물이 아니다.

## R93–R95 · 개발용 서명 릴리스 준비

- 사용자는 정식 GitHub 릴리스를 선택했고, 개발자 등록을 지금 완료할 수 없어 현재는 개발용 ad-hoc 서명만 요청했다. v0.2.0(4), Apple Silicon, 공증 없음으로 준비한다. Release/태그 게시나 유료 공증 제출은 실행하지 않는다.
- XCTest **93개, 실패 0개**와 Python 배포 정책 테스트 **12개, 실패 0개** 통과. 로컬 리허설 업로드 금지, 미공증 업로드의 명시 선택, 리소스/실행 권한 변조, ZIP 경로·symlink, 알 수 없는 서명 상태, 검증 전 GitHub 호출 차단, 공증 결과 불명/진행/거절 상태의 중복 제출 방지를 검사했다. 공증 상태 테스트는 모의 응답이며 실제 Apple 서비스 검증이 아니다.
- `/tmp/tile-release-rehearsal`에서 실제 개발용 서명 패키징을 실행했다. ZIP을 재추출하여 앱 서명·아키텍처·아이콘·Focus 메타데이터·버전·빌드·소스 SHA·실행 권한 및 번들 트리 해시 일치를 확인했다. local_only=true 리허설이라 업로드할 수 없다. 로그는 `/tmp/tile-release-rehearsal.log`다.
- 현재 `gh`는 로그인되지 않았고 유효한 Developer ID Application 인증서는 0개였다. 소스 푸시는 기존 SSH 경로를 사용한다. Developer ID/강화된 런타임/공증/GitHub 초안·게시 경로는 구현했지만 실제 자격 증명을 사용한 검증은 아직 하지 않았다.
- Apple Events 권한은 향후 Developer ID 서명 시 Finder 통합 휴지통 요청을 위해 선언한다. get-task-allow/JIT/라이브러리 검증 해제는 넣지 않았다. 현재 ad-hoc 단계는 권한을 새로 켜지 않으며 사용자 앱을 설치/재실행하거나 시스템 보안을 변경하지 않는다.
- 첫 깨끗한 커밋 빌드는 Desktop 아래 dist 경로에서 동기화 메타데이터가 붙어 codesign 검증에 실패했다. 기본 작업 경로를 Library/Developer/TileLauncher/releases로 바꾸고 알려진 동기화 폴더를 거부하도록 보완했다. 실패 산출물은 작업 폴더 밖 임시 백업으로 보존했다.
- 최종 `29f6fa0bd6c413efe23f79a6f6752196b9452fb9` 커밋을 git archive로 추출해 새 소스 경로에서 빌드했다. `~/Library/Developer/TileLauncher/releases/v0.2.0/downloads/Tile-Launcher-0.2.0-arm64-unnotarized.zip`(1,931,145바이트), release-metadata.json, SHA256SUMS.txt와 릴리스 노트를 생성했다. ZIP SHA-256은 `a42c0b885e9c1a37e053a04d3b1e2c5c45cffca4189697cea47156a8c388cdda`다.
- 최종 ZIP의 재추출 코드 서명/트리 해시/실행 권한/아이콘/Focus/버전·빌드·소스/아키텍처 검사 통과. local_only=false, signing=adhoc, prerelease=false를 확인했다. 이 검사는 Developer ID 신원 확인이나 Gatekeeper 공증 승인을 의미하지 않는다. 실제 다운로드 후 첫 실행의 시스템 경고/접근성 허용은 자동 조작하지 않았다.
- 최종 로그는 `/tmp/tile-release-final.log`와 릴리스 폴더의 build.log다. 준비 파일은 실행 중인 개발 앱에 설치하지 않았고 GitHub 공개 바이너리·태그·초안도 생성하지 않았다. 현재 작업에서 푸시하는 것은 소스/문서뿐이다.

## R91–R92 · Focus 등록 점검·복귀 보완·공개 배포 안내

- 현재 개발 앱의 아이콘과 Info.plist 아이콘 키, LauncherFocusIntent/ProfileEntity/프로필 query 메타데이터 존재를 확인했다. 기존 서명은 ad-hoc, TeamIdentifier 없음이었다. 메타데이터만으로 Focus perform 전달 성공을 판정하지 않는다.
- 읽은 로컬 저장 설정은 followFocus=false, 프로필 2개, 수동 ID 유효였다. 프로필 이름/개인 등록 항목을 기록하거나 변경하지 않았다. 자동 선택 옵션은 사용자가 켜도록 안내했다.
- Launch Services에서 같은 기본 앱 ID로 12개 경로를 확인했다. 현재 개발 앱을 제외한 구 테스트 사본 11개만 `lsregister -u`로 정리하고 현재 앱에 `-f`를 적용했다. 재조회 결과 현재 개발 경로 하나만 남았다. 전체 DB 초기화·파일 삭제·시스템 Focus 필터 삭제는 하지 않았다. 진단 당시 경로 목록은 `/tmp/tile-focus-registration-before.json`에 있다.
- 실제 SettingsStore 격리 검사에서 자동 선택 끄기/정상 Focus ID/필터 해제/삭제된 Focus ID/유효한 수동 ID도 없는 경우를 확인했다. 삭제된 Focus ID는 마지막 수동 구성부터 쓰도록 보완했다. 기존 메뉴·색·스냅샷 저장 검사도 통과했다. XCTest 전체 반복 대신 변경 지점의 네이티브 설정 통합 검사를 사용했다.
- 디버그/릴리스 빌드, App Intents 메타데이터 추출, ad-hoc 서명 검증 통과. 로그는 `/tmp/tile-focus-previews.log`, `/tmp/tile-focus-build.log`다. 최종 개발 빌드 `cadb87e39eef8acac1566ba27b78e9da26b294cbe1b01866bf85b9a36cd948a9`를 안정된 경로에 설치하고 재등록했다. 이전 Contents 백업은 `/tmp/tile-before-focus-2396sisa`이며 설치 전후 실행 소유자 기록은 동일했다.
- 실제 시스템 설정의 아이콘 갱신, 필터 설정 후 집중 모드 전환/해제, OS의 perform/current 전달은 사용자 화면을 조작하지 않아 확인하지 않았다. 현재 준비된 빌드는 공증된 배포 파일이 아니다.
- 개발자 등록 안내는 2026-10-13 Apple 공식 등록 페이지·한국 Apple Developer 앱 가격·Developer ID 안내를 확인해 release-guide.md에 작성했다. 가입/결제/인증서 발급/공증 제출/GitHub 바이너리 Release는 수행하지 않았다.

## R90 · 오버레이에 누적 합계 표시

- 사용자 확인: 직전 빌드의 설정에서 Tile Launcher/메뉴 막대 경로별 횟수가 잘 보인다고 했다. 이번 요청은 오버레이 타일에도 합계만 항상 보이게 하는 표시 변경이다.
- 생산 DeckView의 화면 밖 렌더링으로 클래식 다크·유리 라이트의 고정 메뉴 핀 아래 `5회`/`0회`, 미고정 작은/가로형 타일의 `4회`/`1회`/`0회`를 확인했다. 기존 타일 크기·메뉴 제목·창/등록 선반 배치를 유지한다. 정확한 경로별 수치는 기존 툴팁/접근성 값에 남아 있다.
- 기존 SettingsStore 격리 검사와 스냅샷 검사 통과. 이번에는 집계/보존 정책을 바꾸지 않았고 표시 변경을 위한 별도 단위 테스트를 추가하거나 XCTest 전체를 반복하지 않았다.
- 디버그/릴리스 컴파일, App Intents 추출, ad-hoc 서명 검증 통과. 미리보기/빌드 로그에 컴파일 경고·오류가 없다. 로그는 `/tmp/tile-overlay-totals-previews.log`, `/tmp/tile-overlay-totals-build.log`, 이미지는 `/tmp/tile-overlay-totals-previews`에 있다. 실제 Glass 합성·VoiceOver·큰 숫자 축약의 실기 확인은 별도다.
- 빌드 `3c670b29bdba8da81ee4e047e2943699c469bdb3f4c93cbce29179d94f00fed2`를 안정된 개발 앱 경로에 설치했다. 이전 Contents는 `/tmp/tile-before-overlay-totals-0tgj_qnv`에 백업했다. 설치 전후 실행 소유자 기록이 같고 사용자 앱을 자동 재실행하지 않았다. 기존 사용자 설정/횟수는 수정하지 않았다.

## R88–R89 · 양쪽 메뉴 실행의 합산 횟수 표시

- 사용자 확인: 직전 새 빌드에서 메뉴 자동 수집이 잘 되고 최근 30일/자주 사용 90일 설정도 잘 보인다고 확인했다. 모든 앱/장기 날짜 경계까지 확인한 것으로 해석하지 않는다.
- 표시 문제를 확인했다. 런처 메뉴 실행 성공 콜백은 이미 recordUse로 횟수·최근 시각을 갱신했지만 설정에서는 외부 메뉴 선택 카운터가 0보다 클 때만 보였다. 기존 집계/저장 형식을 유지하면서 합계와 두 경로를 항상 표시하도록 수정했다.
- 최종 XCTest **93개, 실패 0개**. 고정 메뉴에서 메뉴 막대 1회+런처 2회 합산과 JSON 복원·고정 해제 후 빈도 유지, 오래된 메뉴의 런처 사용에 따른 최근 목록 복귀, 기간 이후에도 누적 횟수 유지와 합계 오버플로 방지를 검사했다.
- 실제 SettingsStore 격리 검사: 수집 중단 상태에서도 런처 사용 2회 기록, 수집을 켜 외부 선택 1회 합산, 새 Store에서 같은 ID/핀/누적 3회/각 경로 2·1회/사용 날짜 3개 유지, 고정 해제 후 자주 사용·최근 표시를 확인했다. 실제 외부 메뉴를 실행한 테스트가 아니라 저장·정책 통합 검사다.
- 생산 설정 행의 MenuCommandDetails를 재사용하는 화면 밖 미리보기에서 런처만 3회/양쪽 합계 5회/미사용 0회와 고정 표시를 확인했다. 오버레이는 타일 크기·제목을 유지하고 툴팁/접근성 값에 횟수를 제공한다. 실제 마우스 툴팁·VoiceOver·외부 AX 실행의 실기 검증은 하지 않았다.
- 디버그/릴리스 컴파일, App Intents 추출, ad-hoc 서명 검증 통과. 테스트/미리보기/빌드 로그에 컴파일 경고·오류가 없다. 로그는 `/tmp/tile-menu-counts-tests.log`, `/tmp/tile-menu-counts-previews.log`, `/tmp/tile-menu-counts-build.log`, 횟수 미리보기는 `/tmp/tile-menu-counts-previews/menu-usage-dark.png`다.
- 빌드 `48ad01f6af8318528959c394a52b3f177718f71b7034f15bf5f6219b936c90e2`를 안정된 개발 앱 경로에 설치했다. 이전 Contents는 `/tmp/tile-before-menu-counts-iv7_6lso`에 백업했다. 사용자 설정을 수정하지 않았고 설치 전후 실행 소유자 기록도 같았다. 자동 재실행/Computer Use는 하지 않았으며 최종 빌드의 권한 유지 여부는 미확인이다.

## R83–R86 · 날짜 기준 메뉴 표시·재연결·빌드 교체

- Xcode beta 최종 XCTest **90개, 실패 0개**. 앱별 최근 30일 OR 최근 5개, 6번째/경계 시각/다른 앱/고정 메뉴 제외, 90일 안의 양쪽 입력 합산과 기간 변경, 최대 3개 시각 보관, 이전 누적 카운터 이전, 설정 복원/유효성 검사를 추가했다. 초기 연결/제한 재시도/복구/중단/PID 재사용은 순수 상태 모델로 검증했다.
- 실제 SettingsStore를 격리 suite로 구동해 45/120일 설정 저장·재조회와 기존 데이터 보존, 자동 수집 시각 저장을 확인했다. 실제 OverlayContent에서 같은 의미의 갱신은 스냅샷이 달라지지 않고, 91일 후 갱신에는 가로형 빈도 상태가 해제되며 기존 스냅샷은 유지되는지 검사했다.
- 생산 InstanceCoordinator/BuildReplacement 소스를 컴파일한 **고유 ID·창 없는 테스트 앱**으로 네 가지 통합 검사를 통과했다: 같은 빌드 재실행은 기존 프로세스 유지, 업그레이드는 기존 종료 후 새 실행, 다운그레이드도 같은 규칙, 동일 경로·표시 버전의 번들을 교체한 뒤 `open` 재열기로 새 빌드 실행. `/tmp/tile-handoff-validation.log`에 결과를 남겼다. 일반 앱 본체의 키/AX/상태 막대/프로필은 시작하지 않았다.
- UI 없는 네이티브 샘플 렌더링에서 메뉴 큰/작은 타일과 최근 창·등록 선반 배치가 유지됨을 확인했다. 설정 필드의 실제 클릭/입력과 데스크탑 Glass 합성은 이번 자동 렌더링으로 확인하지 않았다.
- 디버그/릴리스 컴파일, App Intents 메타데이터 추출, ad-hoc 서명 검증을 통과했다. 테스트/미리보기/빌드 로그에 컴파일 경고/오류는 없다. 로그: `/tmp/tile-history-tests.log`, `/tmp/tile-history-previews.log`, `/tmp/tile-history-build.log`.
- 최종 빌드 `4e6d965c87e62b5a5e08c325f357d7d1ae8f5df31113e6bf03818491121bd0a2`를 안정된 개발 앱 경로에 설치했다. 이전 Contents는 `/tmp/tile-before-history-t8u3_yl5`에 백업했다. 설치 전후 실행 소유자 기록은 동일하며 사용자 앱을 자동 재시작하지 않았다. 이 최종 빌드의 접근성 권한 유지 여부는 확인하지 않았다.
- 사용자 실기 피드백: 이전 자동 수집 빌드에서 Finder 메뉴가 처음에는 추가되지 않았으나 재시작 후 수집됐다고 확인했다. hover 후 Esc에 대한 미수집 결과는 별도 확인되지 않았다. Help/키보드 메뉴/다른 앱/무응답 앱의 새 재시도 실기는 아직 미검증이다.
- 재시작 후 확인한 실행 소유자와 설치 파일은 같은 이전 빌드였다. 재시작 전 기록이 없어 사용자가 겪은 증상을 실행 교체 실패로 단정하지 않는다. 초기 메뉴 연결 실패가 같은 앱에서 재시도되지 않는 코드 결함은 확인해 수정했다.

## R80–R82 · 메뉴 막대 자동 수집 — 실험 기능

- 최종 자동 테스트 **78개, 실패 0개**. 입력 확정 없는 알림/hover·취소·만료·역순 이벤트 제외, 같은 입력의 중복 알림, Command/Control/Option 조합과 Esc·키 반복, 메뉴에서 선택한 Copy/Paste 허용, 전체/앱/메뉴 제외 설정 저장, Help 경로 유일성, 대표 동적 경로 제외, 기존 수동 ID/핀/횟수 보존, 이전 JSON 마이그레이션, 자동 이력 정리를 검사했다. 물리 입력/외부 앱 AX 수신 검증과 구분한다.
- 실제 SettingsStore를 격리 suite에서 실행해 자동 Copy 항목 생성, 삭제 후 재수집 제외, 앱 중단·전체 끄기 저장과 재조회, 기존 프로필 보존을 확인했다. 기존 색 설정/부분 복원 검사도 통과했다. 사용자 설정에 테스트 메뉴를 넣지 않았다.
- 접근성 어댑터·네이티브 설정 코드의 디버그/릴리스 컴파일, App Intents 추출, ad-hoc 서명 검증이 통과했다. 최종 로그에 컴파일 경고/오류가 없다.
- 메뉴 수집은 앱 시작 분기에만 연결했고 격리 Preview 분기에서는 시작하지 않는다. 이번 작업에서 Computer Use를 호출하거나 외부 앱 메뉴를 자동 클릭하지 않았다. 사용자에게 편할 때 Finder의 ‘이동 → 폴더로 이동…’을 직접 선택해 실제 수신을 확인해 달라고 요청했다. 현재 실제 Finder/Help/다른 앱의 수신 성공은 미확인이다.
- 입력은 읽기 전용 NSEvent 전역 모니터와 AX 조회/알림을 조합한다. characters·Help 검색어·텍스트 필드 값을 읽어 저장하지 않는다. UI의 선택기·앱별 중단 버튼 실제 클릭과 전체 앱/다중 모니터/빠른 클릭·키보드 메뉴 탐색의 실기는 아직 하지 않았다.
- 최종 빌드 ID는 `cc6a84f0fc707f830f7b27429061ba654e4a7b84c7ed6141b03e94d399cf1d7f`다. 안정된 개발 앱 경로의 파일을 교체하고 이전 Contents는 임시 백업했다. 설치 전후 실행 인스턴스 기록은 동일했고 새 앱을 자동으로 재시작하지 않았다.
- 알려진 제한: AX 메뉴 정보 누락/응답 지연, 메뉴가 빠르게 닫히거나 앱이 바뀌는 경우 누락 가능. Help는 전체 경로 조회가 한계 내에서 끝나고 제목이 유일할 때만 수집한다. 현재 앱만 관찰하고 유휴 메뉴 전체 조회를 하지 않지만 실제 CPU/지연 성능은 이번 정책 테스트로 측정하지 않았다.

## R78–R79 · 파스텔 보정과 자동 메뉴 수집 검토

- 기존 자동 테스트 **65개, 실패 0개**. 기본/강조 구분, 극단/중간 RGB 표본의 본문/보조 글자 대비 및 색 저장/복원 검사가 새 배합에서도 통과했다. 실제 SettingsStore 격리 검사의 색 유지·부분 복원·프로필/메뉴 보존도 통과했다.
- 화면에 표시하지 않는 DeckView 렌더링을 다시 생성하고 클래식 다크·유리 다크·사용자 지정 색에서 기본 타일의 밝은 파스텔, 진한 강조 구분, 자동 글자색을 직접 확인했다. 저장된 사용자 색/테마를 수정하지 않았고 실제 사용자 앱/문서 대신 합성 데이터를 사용했다.
- 릴리스 빌드·App Intents 추출·ad-hoc 서명 검증이 통과했다. 최종 테스트/미리보기/빌드 로그에 컴파일 경고/오류가 없다. 새 빌드 ID는 `fb27a23a7efe2c392f8cedf97af4a9bcd012f7da01a2a11fcb64facd1ed6bc82`다.
- 안정된 개발 경로의 앱 파일만 교체하고 이전 Contents를 임시 백업했다. 설치 전후 실행 인스턴스 기록이 동일함을 확인했으며 앱을 자동 재실행하거나 Computer Use로 화면을 조작하지 않았다. 실제 새 빌드 화면·Glass 합성은 이번 검증 범위가 아니다.
- 자동 메뉴 수집은 Apple 문서/로컬 SDK와 비교 제품 제작사의 설명을 확인한 가능성 검토다. 외부 앱의 메뉴 알림을 실제 수신하는 실험, 키보드/취소 구분, 자동 수집 기능 구현은 수행하지 않았다. 근거와 제안은 menu-observation-design.md에 기록했다.

## R75–R77 · 섹션 색상·모양 탭·작업을 방해하지 않는 검사

- Xcode beta 도구의 자동 테스트 **65개, 실패 0개**. 색 설정의 누락/손상 기본값, 섹션별 독립 저장/복원, 테마 전환 시 기준 색 보존, 세 기본색/강조 구분과 216개 RGB 표본 × 두 테마 × 라이트/다크 × 강조 여부의 본문/보조 글자 대비 검사가 추가됐다. 기존 입력·프로필·레이아웃 검사도 통과했다.
- 실제 SettingsStore의 격리 suite 검사에서 색을 저장한 뒤 새 인스턴스로 읽기, 테마 변경 후 색 유지, 한 섹션 기본값 복원 시 다른 두 색 유지, 기존 프로필·등록 목록·메뉴 보존을 확인했다. 테스트 전용 데이터만 사용했다.
- Xcode beta 디버그 컴파일·릴리스 빌드·App Intents 추출·ad-hoc 서명 검증이 통과했다. 최종 테스트/빌드 로그에 컴파일 경고/오류가 없다. 초기 미리보기 코드의 MainActor 호출과 복합 샘플 표현식 컴파일 오류는 수정한 뒤 재검사했다.
- 실제 DeckView를 합성 데이터로 렌더링한 6개 PNG를 생성했다. 클래식/유리의 라이트·다크, 사용자 지정 색, 작은 패널을 직접 확인했다. 메뉴의 기본 작은/긴 타일과 고정 강조, 최근 창의 기본/현재 데스크탑 강조, 등록 35개 세 줄 및 최근 창 3.3줄을 확인했다. 등록 아이콘은 가짜 경로의 일반 파일 아이콘이며 사용자 앱 목록이나 화면 캡처를 저장하지 않았다.
- 처음 사용한 ImageRenderer는 AppKit 표현/스크롤 콘텐츠를 누락해 화면에 표시하지 않는 NSHostingView 호스트로 교체했다. 모양 설정의 네이티브 라디오/색 선택기는 이 PNG 경로에서도 완전히 그려지지 않아 자동 이미지 검증 성공으로 처리하지 않았다. Xcode Canvas용 `#Preview("모양 설정")`를 제공했으며 실제 Canvas를 열어 조작한 것은 아니다.
- 이번 작업에서는 **Computer Use를 호출하지 않았고** 전역 키 감지·AX 관찰·권한 요청·메뉴 막대·인스턴스 잠금을 시작하지 않는 미리보기 분기를 사용했다. 호스트 창을 order/makeKey 하지 않았다. 실제 Glass 합성·키 입력·드래그 성능·네이티브 색 선택기의 클릭은 이번 검증 범위가 아니다.
- 최종 앱 파일을 안정된 개발 경로에 설치하고 기존 Contents는 임시 백업했다. 새 빌드 ID는 `b00b35a57780fadce8f4574d9b2f10e0ac24c33a6659db5d23d0628976ae5302`다. 실행 중 인스턴스 기록은 이전 빌드 ID로 그대로 유지됨을 확인했다. 사용자의 작업을 방해하지 않도록 새 앱을 자동 실행하지 않았으므로 사용자가 다음에 다시 열 때 적용된다.
- Finder에서 직접 선택한 메뉴는 자동 수집하지 않는 현재 구현을 확인하고 설정 설명을 보완했다. 메뉴 수집 기능을 새로 구현하거나 외부 클릭을 관찰했다고 보고하지 않는다.

## 2026-10-13 · R74 최종 빌드 재실행

- 사용자가 잠금을 해제한 후 Finder에서 기본 앱을 다시 열었다. 실행 중 PID 97054의 경로가 안정된 개발 앱 경로이며, 인스턴스 소유자 기록과 설치 번들의 빌드 ID가 `abc80cbf4e9a1f94f444b072afe132d3cd4c3ac2cb9443bd647d11c00a674a0c`로 일치했다. 코드 서명 검증도 통과했다. 새로운 빌드나 코드 수정은 하지 않았다.
- 첫 화면은 접근성 미허용이었다. 사용자 직접 재허용 후 실제 AX 트리에서 최근 창 16개/등록 항목 35개와 현재/다른 데스크탑 구분을 확인했다. 접근성 허용 완료를 단순 사용자 응답뿐 아니라 실제 창 목록으로 확인했다.
- 왼쪽 핀을 클릭해 닫기 버튼/드래그 안내로 전환되는 것과 우상단 설정 버튼으로 설정 창이 열리는 것을 확인했다. 이후 일반 탭 클릭/상태 조회/스크린샷이 UI 도구 연결 종료로 중단됐고 연결 초기화 후에도 동일했다. 자동 도구가 두 테마 전환을 검증했다고 설명하지 않는다.
- 사용자가 두 테마에서 오버레이는 원하는 대로 표시되며 메뉴 막대 아이콘은 동일하다고 직접 확인했다. 제공한 메뉴 막대 캡처에서도 계단형 바탕과 분리된 사각 타일의 최종 단색 심벌을 확인했다. 테마와 관계없이 같은 브랜드 심벌을 쓰는 의도된 동작이다. 캡처는 저장소에 복사하지 않았다. 실제 재실행 후 테마 저장 유지는 이번 UI 검사 범위가 아니며 앞서 격리 모델에서 검사했다.
- 연결 중단 시점 뒤 앱 프로세스는 생존했고 1초 sample의 메인 스레드는 AppKit 이벤트 대기 상태였다. 앱 충돌 보고서는 발견되지 않았다. 이 짧은 진단을 모든 멈춤의 부재나 드래그 성능 개선의 증명으로 해석하지 않는다.

## R65–R73 두 테마·고정 중 활성 앱 추종·최종 아이콘 — 현재 결과

- 자동 테스트 **60개, 실패 0개**. 고정/비고정, Option 유지, 선택/실행 대기, 마우스 누름에 따른 갱신 정책 3개와 기존 레이아웃/입력/프로필 검사를 통과했다. 프로필 선택기 높이를 포함한 등록 선반 및 작은 배치 회귀 검사도 통과했다. 최종 기능 소스 검증 뒤 변경한 것은 브랜드 벡터 경로·아이콘 자산·문서다.
- 실제 SettingsStore/OverlayContent/HoldMonitor를 사용하는 격리 통합 검사가 통과했다. 빈 프로필·복제·원본 보존·순서·임시 선택/Focus 복귀, 키 입력 소유권·반복 억제, 활성 앱/메뉴/창 제목 변경·레이아웃/프로필 보존·동일 스냅샷 발행 억제·권한 상실, 두 테마 저장/재조회와 18pt template 이미지 생성·렌더링을 확인했다. 사용자 설정에 테스트 데이터를 넣거나 OS 키 이벤트를 주입하지 않았다.
- 실제 네이티브 화면에서 파스텔 외관, 우상단 설정 단독 버튼과 하단 프로필 선택기, 등록 35개 세 줄, 최근 창 세 줄+다음 줄 일부를 확인했다. 고정 패널을 유지한 채 외부 앱을 왕복할 때 상단 제목/메뉴 문맥/최근 순서가 바뀌는 것을 확인했고 사용자도 활성 앱 추종을 긍정적으로 확인했다. 개인 목록/화면 캡처는 저장소에 넣지 않았다.
- Square 비교 단계에서는 별도 설정/인스턴스 및 실제 최근 창 18개·등록 35개를 확인했다. 사용자 삭제 요청 이후 Finder에서 해당 앱만 휴지통으로 옮기고 기본 앱 하나만 남음을 확인했다. 당시 Square는 이미 종료되어 다른 프로세스를 종료하지 않았고 휴지통도 비우지 않았다. 최종 소스는 단일 앱에 두 테마를 제공한다.
- 드래그 입력 자체는 수행했지만 유효한 전후 성능 측정을 확보하지 못했다. 처음 입력은 사용자 상태 변경으로 취소됐고 sample 기록과 실제 성공한 드래그 구간이 일치하지 않았다. 반복 창/접근성 속성 설정은 줄였으나 지연 원인을 불투명도라고 확정하거나 해결 완료라고 설명하지 않는다.
- 최종 선택한 계단형 바탕+분리된 타일 PNG를 직접 확인하고 ICNS를 재패키징했다. 10개 크기/배율 표현과 CFBundleIconFile 연결, 저장소 ICNS와 설치 번들 자산의 바이트 일치를 확인했다. 메뉴 막대는 같은 두 요소의 단색 벡터 template다. 생성 원본에는 큰 배율에서 외곽 알파의 미세한 불규칙성이 남아 있으며 완벽한 벡터 외곽이라고 설명하지 않는다.
- 선택한 아이콘의 최종 릴리스 빌드·App Intents 추출·ad-hoc 서명 검증이 통과했다. 안정된 개발 앱 경로의 Contents를 교체하고 이전 Contents는 임시 백업했다. 설치 빌드 ID는 `abc80cbf4e9a1f94f444b072afe132d3cd4c3ac2cb9443bd647d11c00a674a0c`다.
- 10월 12일 최종 재실행은 Mac 잠금으로 중단됐다. 10월 13일 위 R74에서 실행 ID와 사용자 재허용 후 최근 창을 확인했다. 테마 전환은 사용자 확인, 메뉴 막대 실물은 사용자가 제공한 캡처로 확인했으며 UI 도구 자동 검증과 구분한다.
- 남은 실기: 실제 드래그 성능, 모든 배율/라이트·접근성 조합, 실제 여러 프로필의 물리 제스처, Focus 필터/Excel 메뉴 등 아래 미검증 범위. 모델 테스트·코드 서명·아이콘 패키징을 이러한 실기 성공으로 확대하지 않는다.

## R61–R64 프로필 순환·3.3줄·Option 명령·불투명 시안 — 당시 결과

- 자동 테스트 **57개, 실패 0개**. 프로필 양끝 순환/단일·빈 목록/배열 순서, 임시 프로필 초기화, 가로 제스처 한 단계/관성/취소/자연스러운 스크롤 반전/세로 흔들림/일반 휠 묶음, A/S/D/F와 Option 명령/제외 보조키, 3.3줄/등록 완전한 행/크기·비율 경계를 검사함. 최초 실제 화면의 몇 포인트 부족으로 등록 세 번째 줄이 밀리는 문제를 발견하고 여유 높이와 고정 푸터를 보정했으며 해당 회귀 검사까지 통과함.
- 최종 릴리스 빌드·ad-hoc 서명·App Intents 추출 성공. 최종 테스트/빌드 로그에 컴파일 경고·오류 없음. 안정된 개발 앱 경로의 Contents를 교체한 뒤 최종 실행 프로세스의 빌드 식별값과 설치된 패키지의 일치를 확인함. 이전 앱과 후보 Contents는 임시 백업으로 보존함.
- 격리된 UserDefaults suite에서 실제 SettingsStore를 실행하여 빈 프로필/복제/원본 보존에 더해 프로필 순서 변경과 재조회·자동 추종/수동 선택 값 보존을 확인함. 임시 프로필 전환/초기화 후 Focus 대상 복귀와 HoldMonitor의 합성 NSEvent 입력 A/S/D/F/W/쉼표 처리도 통과함. 사용자 프로필에는 테스트 데이터를 추가하지 않았고 OS에 이벤트를 합성 주입하지 않음. 위 57개 XCTest와 별도 검사임.
- 후보 앱의 실제 1,040pt 폭 화면에서 최근 창 17개 전체 목록과 세 줄+네 번째 줄 일부를 확인함. 사용자가 후보 빌드 접근성을 재허용했음. 타일 색/모서리와 유리 재질은 변경하지 않음. 마지막 선반 높이 보정은 자동 기하 검사로 확인했으며 최종 네이티브 화면의 등록 세 줄 재캡처는 아직 완료하지 못함.
- 사용자와 UI 도구의 포커스가 겹쳐 자동 키 검사를 중단함. 도구의 Option 쉼표가 설정 검색란에 입력된 한 문자는 곧바로 원래 검색어로 복원함. **사용자가 최종 빌드에서 고정 상태의 Option 닫기/설정, Option+Command 조합과 Command 닫기/설정 모두 정상**이라고 직접 확인함. 도구가 키 검사를 모두 완료했다고 표현하지 않음.
- 불투명 타일 시안 두 안을 실제 브라우저에서 확인함. 좁은 폭에서 세로 배치, 넓은 폭에서 메뉴/최근 창 나란히 배치, 세 줄+다음 행 일부, 다음 프로필 선택 시 이름/등록 항목 전환과 이전 프로필 복귀, 안 전환을 확인함. 시안은 배경/타일 외관 비교이며 네이티브 디자인 변경으로 간주하지 않음. 외부 게시 없음.
- 남은 실기: 여러 실제 프로필을 사용한 물리적 가로 휠/트랙패드 방향과 관성, 프로필 순서 버튼/저장 후 재시작, 여러 프로필 왕복 후 숫자 실행, 라이트/접근성·물리 다중 모니터·전체 최소 크기 화면. 단위 테스트나 격리 모델 검사를 실제 장치 입력 성공으로 확대하지 않음. 기존 메뉴/Focus 앱별 미검증 범위는 아래 기록을 유지함.

## R58–R60 빈 프로필·고정 단축키·등록 타일 — 당시 결과

- 자동 테스트 **48개, 실패 0개**. 등록 그리드의 512/640/760/900/1,040pt 폭에서 정사각 크기·열 간격·실제 내폭 합계·선반 높이를 확인함. 기존 하단 선반/최근 창 배치와 키 입력 정책 검사도 통과함.
- 디버그 테스트와 릴리스 빌드·서명·App Intents 추출 성공. 최종 로그에 컴파일 경고/오류 없음. 안정된 개발 경로의 앱 폴더를 유지한 채 Contents를 교체하고 실행 중 빌드 식별값과 설치된 패키지의 일치를 확인함. 표시 버전은 0.2.0(3)이며 이전 Contents는 임시 백업으로 보존함.
- 실제 SettingsStore/Models를 사용하는 임시 통합 검사에서 고유 UserDefaults suite를 만들어 빈 프로필 생성(0개)/이름 앞뒤 공백 제거/복제/원본 항목 및 폴더 방식 보존/수동 선택 전환/공백 이름 거부/저장 후 새 인스턴스의 재조회가 통과함. 복제본 편집이 원본을 변경하지 않는 것도 확인함. 검사 후 suite를 제거했으며 사용자 프로필에는 테스트 데이터를 추가하지 않음. 이 검사는 위 48개 XCTest와 별도임.
- 실제 HoldMonitor를 연결한 합성 NSEvent 검사에서 ⌘,와 Option을 유지한 ⌘W 처리, 키 반복 시 동작 중복 방지, 키보드 소유권이 없거나 패널이 닫힌 상태의 미처리가 통과함. OS에 이벤트를 주입한 실기 검사가 아님.
- 고정 시 앱 활성화/키 창 요청과 NSPanel의 key-equivalent 경로를 함께 보완함. UI 도구에서 ⌥X 고정 상태를 확인했으나 후속 입력은 창 상태 변경/연결 종료로 중단됨. 사용자가 수정된 앱에서 **⌥X 고정 후 ⌘W 닫기 및 ⌘, 설정 열기 모두 정상**이라고 직접 확인함. 원래 오류의 정확한 OS 이벤트 경로를 자동 도구로 재현했다고 주장하지 않음.
- 실제 1,040×720pt 네이티브 화면에서 등록 35개가 배경/테두리 있는 작은 정사각 타일로 14열·3줄에 표시됨을 확인함. 마지막 줄, 32pt 아이콘, 이름과 첫 10개 숫자 배지, 위쪽 메뉴/최근 창 영역을 확인함. 개인 앱·파일 목록이나 캡처는 저장소에 포함하지 않음.
- 남은 확인: 설정 화면의 두 프로필 버튼 배치는 native pipe closed로 캡처하지 못함. 위 저장 검증을 버튼 클릭 실기로 설명하지 않음. 라이트 모드·대비/투명도 줄이기·VoiceOver·모든 패널 크기의 실제 화면은 전수 검증하지 않았고, 이전 메뉴/Focus/다중 모니터 등 미검증 범위는 아래 기록을 유지함.

## R56–R57 하단 선반·다른 데스크탑 창·현재 데스크탑 강조 — 당시 결과

- 자동 테스트 **47개, 실패 0개**. 선반의 실제 행 수/최대 뷰포트, 30% 여백 배분/타일 비율, 작은 패널의 최소 한 등록 행, 최소화/가려진 창·여러 모니터·모든 데스크탑 소속 판별, 내부 API 미지원 축소, AX 누락/확실한 닫힘 구분, 고정 상태의 색 갱신/선택 유지 검사를 추가함. 자동 개수 회귀 검사는 전체 목록과 두 줄 밖 스크롤 대상으로 수정함.
- 최종 디버그 테스트와 릴리스 빌드/서명·App Intents 추출 성공. 최종 로그에 컴파일 경고/오류 없음. 임시 후보 빌드 검증 후 안정된 개발 경로에 한 번 교체함. 이전 앱 파일은 임시 백업으로 보존함.
- 같은 DesktopWindows 구현을 링크한 읽기 전용 임시 프로그램으로 실제 WindowServer 메타데이터와 Space 소속을 확인함. 해당 시점 일반 앱의 크기 필터를 통과한 후보는 현재 11개/다른 데스크탑 9개/미확인 8개. 이 숫자는 AX 역할 필터를 통과한 최종 런처 창 수가 아니며 창 제목/개인 목록을 저장하지 않음. 메타데이터 조회와 분류 단일 표본 약 45ms로 장시간 성능을 보장하지 않음.
- 코드상 다른 Space의 캐시된 AX 창 유지·미관찰 CG 창 보완·선택 시 같은 ID 재조회·현재 데스크탑 배경색·자동 전체 목록 스크롤을 구현함. 내부 API 이름의 존재 및 읽기 동작 확인을 실제 선택 이동 성공으로 혼동하지 않음.
- UI 도구에서 Finder 상태 변경 오류와 앱 선택 시 native pipe closed가 반복되어 사용자에게 새 경로 앱 열기를 요청함. 사용자가 실행/권한 확인을 완료한 뒤 실제 새 오버레이의 AX와 스크린샷 검증을 재개함. 접근성 권한을 에이전트가 변경하지 않음.
- 실제 1,040×720pt 네이티브 화면에서 등록 항목 35개가 하단 3줄에 붙고 메뉴/최근 창은 같은 두 줄 높이를 유지함. 최근 창 19개, 현재 데스크탑에 속한 여러 창의 배경색과 접근성 안내를 확인함. 실제 개인 앱·파일 이름과 캡처는 저장소에 포함하지 않음.
- 아직 AX 객체가 없던 다른 데스크탑의 Finder 타일을 선택해 대상 데스크탑으로 이동했고 Finder 창이 조회됨을 확인함. 이어 원래 데스크탑의 창을 선택해 돌아옴. 두 방향 모두 고정 패널의 타일 순서·번호를 유지한 채 현재 데스크탑 색/안내만 갱신됨. 오류 안내는 나타나지 않았음.
- 최근 창 영역을 끝까지 스크롤하여 후순위 창들이 실제 표시되고 등록 선반/메뉴/푸터 위치는 그대로임을 확인함. 스크롤을 처음으로 복원하고 원래 데스크탑의 고정 패널 상태로 마침.
- 남은 한계: 콜드 스타트 시 제목 미제공 창의 대체 제목이 보임. 제목은 다음 호출의 최신 스냅샷에서 반영하는 정책이며 이 갱신 자체는 별도 실기로 확인하지 않음. 모든 서드파티 앱·전체 화면·Stage Manager·물리 다중 모니터·최소화 창의 실제 선택은 아직 전수 검증하지 않음. 내부 API의 향후 OS 호환 보장이 아님.

## R52–R55 네이티브 혼합 타일·숫자 설정·메뉴·프로필 — 당시 결과

- 자동 테스트 **38개, 실패 0개**. 기존 31개에 혼합 타일의 순서/줄 끝 빈칸, 다음 표시의 최근 이웃 변화, 혼합 타일 두 줄 자동 수용량과 수동 상한 없음, 512–1,040pt 기하, 열 개 숫자/두 배치/제외 보조키, 기존 등록의 프로필 이전, 앱별 고정/빈도/최근 정렬을 추가함.
- Xcode beta의 디버그 테스트·릴리스 컴파일 성공, 진단 로그에 경고/오류 없음. 최종 InstanceCoordinator 보완 후 릴리스 재컴파일/서명 검증도 통과함. 표시 버전 0.2.0(3), 안정된 경로의 ad-hoc 개발 앱임.
- App Intents 추출 성공. `.app/Contents/Resources/Metadata.appintents/extract.actionsdata`에 LauncherFocusIntent와 프로필 엔터티/쿼리가 포함됨. **메타데이터 검증이며 시스템 설정의 Focus 필터 선택·활성/해제 실기 성공을 뜻하지 않음.**
- 실제 네이티브 오버레이 AX에서 기존 등록 36개 유지, 첫 10개의 ⌥1–⌥0 도움말, 최근 창의 ⌥⌘1–0 안내, 프로필 선택/앱별 메뉴 추가/왼쪽 핀을 확인함. ⌥X 후 닫기/상단 이동 안내 전환을 확인함. 개인 앱·파일 이름/스크린샷은 저장소에 복사하지 않음.
- R55 재현: 작업 폴더 0.1.0 복사본과 최신 앱 두 프로세스의 bundle ID가 같지만 초기 앱에는 실행 잠금이 없었음. 보완 후 실제 초기 앱을 실행한 상태에서 최신 빌드를 시작해 초기 PID 정상 종료와 최신 인스턴스 하나를 확인함. 같은 최신 빌드를 다시 실행하면 추가 프로세스가 정상 종료하고 기존 PID가 유지됨.
- UI 검증 중 도구 연결 종료/창 없음/사용자 조작으로 상태 변경 응답이 있었음. 설정 확인 시 연결 종료가 반복되어 더 진행하지 못함. 프로세스는 생존하며 메인 스레드 1초 샘플은 정상 이벤트 대기 상태였음. 반복 실패를 성공으로 처리하지 않으며 다음 항목을 미확인으로 둠.
- 마지막 실행의 빌드 식별값과 패키지 식별값 일치, 코드 서명 및 Focus 메타데이터를 확인함. 1초 진단 표본의 physical footprint는 약 53.7MB였으나 유휴/다수 창/장시간 성능 측정으로 일반화하지 않음.

### 이번 빌드에서 남은 실기 확인

- 최종 빌드 재허용 후 실제 오버레이에서 권한 안내 대신 서로 다른 앱의 열린 창 6개가 표시됨을 확인함. 네이티브 스크린샷에서 메뉴/최근 창 영역의 두 줄 높이가 같고 등록 36개가 아래에 표시됨을 확인함. 앱의 권한을 임의로 허용하거나 TCC를 수정하지 않음.
- 실제 서로 다른 앱 창 6개 표시까지 확인. 같은 앱 연속 창의 혼합 배치·작은 폭 제목 가독성·숫자 전환/설정 반전, 실제 앱 메뉴 목록 읽기/등록/실행·빈도 변화, 프로필 생성/전환/Focus 활성·해제는 아직 실기 완료 아님.
- 등록 항목 숫자 실행·고정 패널 상태·Option/Command 해제 순서·폴더 진입 단축키, 설정 창 전체 탭의 작은 크기, 실제 Liquid Glass·VoiceOver·다중 모니터·Instruments 성능은 후속 실기 대상. 자동 테스트 통과와 구분함.
- 초기 잠금 없는 앱을 *최신 앱 시작 이후* 별도로 실행하는 과거 바이너리 자체의 동작은 바꿀 수 없음. 최신 빌드를 다시 실행하면 이전 복사본을 정리한다. 앞으로는 안정된 최신 빌드 경로를 사용하고 오래된 복사본을 로그인 시작 대상으로 사용하지 않는다.

## R51 최근 창 샘플 변경 — 당시 결과

- 첫 안의 새 기본 순서는 Terminal cc2/Terminal se3/Safari/Terminal local/Mail/Finder/Notes/Preview. DOM에서 앞 네 크기가 large/small/large/large임을 확인함. 900 CSS px 폭에서 앞 세 항목 y=0, 4·5·6번 y≈85px, 7·8번 y≈170px로 배치되어 첫 화면에 6개가 완전히 표시됨.
- ‘앱마다 창 하나’를 선택하면 모든 창이 가로형으로 표시됨. 이 선택 후 2번으로 이동해 기존 t1/t2/s1/s2/m1/m2/f1/f2 샘플이 유지되는 것을 확인함.
- 기존 타일 크기/창 크기/메뉴/등록 아이콘은 변경하지 않음. 네이티브 코드·앱 빌드 변경 없음.

## R49–R50 정사각형·가로형 비율 비교 — 당시 결과

- 시안과 기록만 수정. `tile-launcher-aligned-recents.html`의 두 배치만 남겼으며 실제 앱/빌드는 변경하지 않음. 외부 게시 없이 기존 sandbox iframe/CSP 미리보기로 확인함.
- 900×620 CSS px 창에서 메뉴의 정사각형은 약 77.22×77.22, 가로형은 약 162.44×77.22, 최근 창도 같은 치수임. 정사각형 두 개 + 약 8px 간격 = 가로형 너비, 동일한 높이를 DOM에서 확인함. 이전 108px 타일 높이와 720px 창 높이를 줄인 비교용 제안임.
- 두 배치 모두 메뉴/최근 창 그리드 시작선·끝선이 같고 높이는 약 162.43px로 두 줄임. 앱 연속 예시의 첫 안은 창 8개, 동일 크기 대안은 창 6개가 첫 화면에 완전히 들어감. 메뉴 두 개는 같은 행에 나란히 유지함.
- 앱 교차 예시의 앞 세 항목은 Terminal/Safari/Terminal 모두 가로형이며 전체 최근 순서를 유지함. 이 경우 첫 화면은 창 6개. 세 번째 Terminal 클릭으로 se3 개별 창의 미리보기 상태를 확인함. 작은 창 타일은 두 줄 제목과 전체 이름 도움말을 제공함.
- 325 CSS px 미리보기에서는 세로로 재배치되며 정사각형 약 66.8×66.8, 가로형 약 141.6×66.8로 비율을 유지함. 가로 넘침과 최근 앱 제목 줄 넘침 없음. 이 좁은 화면용 미리보기 재배치는 네이티브 2줄 규격의 변경이 아님.
- 브라우저 콘솔 오류 없음. 실제 앱 전환·메뉴 실행·Liquid Glass 렌더링/성능은 이번 시안 확인 대상이 아님.

## R47–R48 메뉴/최근 창 정렬 비교 — 당시 결과

- 네이티브 코드와 실행 중 앱은 변경하지 않음. `tile-launcher-aligned-recents.html`에 앱 전환점 큰 타일·제목 줄 최근 앱·아래쪽 최근 앱 세 비교안을 작성함. sandbox iframe/CSP를 유지하며 게시하지 않음.
- 900 CSS px 창에서 세 안 모두 메뉴/최근 창 그리드의 시작 y와 끝 y 차이가 **0px**임을 DOM 치수로 확인. 두 줄 그리드 높이는 약 226px. 최근 앱을 포함하는 대안의 아이콘은 제목 줄 안에 있어 창 목록을 아래로 밀지 않음.
- 사용자 예시 검증: 터미널→터미널→Safari는 큰·작은·큰, 터미널→Safari→터미널은 큰·큰·큰. 서로 다른 앱 뒤에 다시 등장한 터미널을 제거하거나 앞 그룹으로 이동하지 않음. 앱마다 창 하나인 예시는 모두 큰 타일임. 첫 화면은 연속 예시에서 창 8개, 교차 예시에서 6개이며 나머지는 세로 스크롤로 탐색함.
- 교차 예시의 세 번째 터미널을 선택해 해당 `se3` 창으로 이동한다는 미리보기 상태를 확인함. 큰 타일을 일반 앱 활성화로 바꾸지 않음. 선택·메뉴 고정·최근 앱·등록 아이콘은 로컬 시안 동작이며 실제 앱/창 전환을 수행하지 않음.
- 시안의 Light/Dark 외관과 세 안의 325 CSS px 폭 세로 재배치를 확인. 브라우저 콘솔 오류 없음. 작은 폭에서 문서 scrollWidth와 clientWidth가 같고 창 타일 최소 폭은 사용자안 약 67.6px, 동일 크기 대안 약 140.6px였음. 모바일 미리보기에서는 열 수를 줄여 세로로 펼치며 네이티브 2줄 지원 규격을 바꾸지 않음.
- 새 소프트웨어 기능 테스트나 네이티브 빌드는 필요하지 않은 시안/기록 변경임. HTML과 실제 Liquid Glass·AppKit 렌더링을 동일하다고 판정하지 않음.

## R43–R46 작은 등록 아이콘·통합 메뉴 시안과 헤더 수정 — 당시 결과

- 기존 자동 테스트 **31개, 실패 0개**. SwiftUI anchor preference와 AppKit hit-test를 포함한 디버그/릴리스 컴파일 및 ad-hoc 서명 검증 통과. 안정된 개발 경로의 앱을 새 빌드로 열어 확인함.
- 실제 앱에서 핀 클릭 → 닫기/상단 이동 안내 전환, 다운로드 폴더 진입 → **원형 Liquid Glass 뒤로 버튼 표시** → 클릭으로 등록 항목 화면 복귀, 오른쪽 설정 버튼으로 설정 창 열기를 확인함. 드래그 영역이 확인한 헤더 컨트롤의 클릭을 가로채지 않음. 개인 파일 목록/캡처는 저장소에 포함하지 않음.
- 상단 위쪽 여백에서 드래그 입력을 보낸 뒤 고정 상태와 콘텐츠 유지 확인. 도구가 창의 화면상 좌표를 제공하지 않아 위치 변화량, 비고정 이동 차단, 실제 다중 모니터 이동은 검증 완료로 판정하지 않음. 앱 상태가 사용자 조작으로 바뀐 호출은 중단하고 최신 상태에서만 확인했으며 이후 설정 닫기 재검사는 완료하지 않음.
- 시안은 예시 앱/폴더 36개, 기본 등록 아이콘 32 CSS px, 동일한 900×720 CSS px 창으로 비교함. 오른쪽 아이콘 모음은 **35개/최근 창 8개**, 아래 두 줄 Dock은 **28개/최근 창 8개**, 메뉴와 창 나란히는 **36개/최근 창 6개**가 첫 화면에 완전히 표시됨. 기본 macOS 앱/폴더 아이콘을 사용하며 사용자 등록 목록을 복사하지 않음.
- 세 시안 모두 메뉴 한 영역, 큰 메뉴 2개 나란히, 작은 최근 메뉴 타일을 포함함. 작은 ‘인쇄’ 메뉴의 고정 클릭으로 크기/배경 변경과 고정 그룹 우선 배치를 확인하고 고정 해제로 복원함. 사용 빈도에 따른 크기는 예시 데이터이며 자동 수집/실제 실행을 시험한 것이 아님.
- sandbox iframe/CSP 미리보기에서 세 배치 전환, 등록 항목 선택, 핀 토글이 동작하고 브라우저 콘솔 오류 없음. 736/360px viewport 요청에서 실제 iframe 폭은 각각 약 625/289 CSS px로 측정됨. 관찰한 작은 폭에서 가로 넘침이 없고 세로 재배치됨. CSS px와 네이티브 pt를 혼용하지 않으며 모바일 배치를 네이티브 지원 크기 확정으로 간주하지 않음.

## R41–R42 레이아웃 비교와 고정 창 이동 — 당시 결과

- 기존 자동 테스트 **31개, 실패 0개**. 새 드래그 영역을 포함한 디버그/릴리스 컴파일과 ad-hoc 서명 검증 통과. 새 빌드 재열기 후 안정된 경로의 프로세스로 교체됨.
- 고정 상태를 SwiftUI 관찰 값으로 받아 중앙 헤더의 NSView와 창 이동 가능 여부에 연결함. 처음에는 Mac 잠금으로 실기를 중단했으나 사용자가 잠금을 해제해 이어서 확인함. 고정 상태의 닫기 버튼·이동 영역·드래그 안내가 AX에 나타나고, 중앙 제목에서 드래그 입력을 보낸 뒤에도 고정 상태와 콘텐츠가 유지됨.
- 드래그 이후 오른쪽 설정 버튼으로 실제 설정 창이 열리고 `⌘W`로 닫힘을 확인. 재호출된 일반 오버레이에는 이동 영역이 노출되지 않음. 도구가 창 내부만 캡처하고 화면상 좌표를 제공하지 않아 실제 위치 변화·비고정 이동 차단은 실기 통과로 판정하지 않음. 이후 핀/닫기 재검사는 창을 사용할 수 없다는 응답으로 완료하지 못함. 물리 드래그·다중 모니터·폴더 헤더 버튼은 후속 실기 항목임.
- 별도의 레이아웃 비교 시안을 로컬의 sandbox iframe/CSP 안에서 검증함. 900 CSS px 폭에서 아래 전체 폭 안은 등록 24개/최근 창 6개, 오른쪽 선반 안은 등록 20개/최근 창 8개가 첫 화면에 표시됨. 예시 등록 항목은 36개이며 네이티브 앱의 개인 항목 목록을 복사하지 않음.
- 브라우저 736px·360px 폭에서 가로 넘침이 없고 좁은 폭에서 열을 세로로 재배치함을 확인. 배치 전환과 등록 항목 선택도 작동하며 콘솔 오류 없음. 시안의 메뉴와 등록 항목 버튼은 로컬 미리보기이고 실제 앱 실행/메뉴 실행을 수행하지 않음.

## R38–R40 버전별 실행 전환과 오버레이 단축키 — 당시 결과

- 자동 테스트 **31개, 실패 0개**. 같은 빌드 유지, 버전 증감과 무관한 마지막 실행 우선, 같은 표시 버전의 로컬 재빌드 구별, 잠금 획득 순서 역전, PID 재사용, 소유자 기록, 표시 전/후 보조키 처리, Option 유지 중 설정/닫기, Option-X와 Space/A 비점유를 추가 검증함.
- 임시 앱 복사본을 이용한 실제 프로세스 검증: 같은 빌드 재실행은 새 프로세스가 정상 종료되고 기존 PID 유지. 0.1.1 → 0.1.2 → 0.1.1 전환은 기존 PID 종료 후 새 PID가 소유자로 기록됨.
- 실행 중인 앱의 Info.plist를 0.1.3으로 바꿔도 실행 당시 기록은 0.1.1로 유지. Finder와 같은 `open <앱 경로>` 요청으로 새 인스턴스가 시작되고 0.1.3으로 전환됨. 서로 다른 버전을 연속 실행하면 마지막 시작 프로세스만 남고, 같은 빌드를 3개 동시에 시작하면 모두 정상 종료되어 기존 앱 하나만 유지됨.
- 첫 실기에서 사용자에게 시간 초과 오류가 표시됨(R40). 기존 PID는 이미 종료됐지만 앱 시작 단계의 AppKit 종료 상태가 지연되는 문제를 재현하고, 완료 확인을 커널 프로세스 식별자로 수정한 뒤 위 시나리오를 모두 통과함. 실제 종료 거부/멈춘 앱에 대한 시간 초과 분기와 별도 사용자 계정은 이번 실기 범위 밖임.
- 실제 네이티브 UI: 설정 창의 `⌘W` 닫기, 일반 오버레이의 `⌥X` 고정 및 키 해제 후 유지, 고정 오버레이의 `⌘W` 닫기/재호출 초기화, **고정하지 않은 오버레이에서 `⌥⌘,`로 바로 설정 열기**를 AX 상태 변화로 확인함. 자동 실행 켜짐과 기존 등록 목록이 유지됨.
- UI 도구는 Option 단독을 길게 누르는 입력을 지원하지 않음. 250ms 단독 누름 → 표시 → Command 추가라는 물리 키 연속 조작은 사용자 실기 대상으로 남기며, 해당 상태 전이는 단위 테스트와 표시된 실제 패널의 복합 단축키로 각각 검증함. 이번 작업에서 접근성 권한을 임의로 허용하지 않음.
- 최종 릴리스 빌드·ad-hoc 서명 검증 통과. 최적화된 릴리스 앱에서도 동일/다른 빌드, 같은 경로 덮어쓰기 후 재열기, 동시 실행 시나리오를 모두 다시 통과함. 안정된 개발 경로의 0.1.1 앱 하나가 남았음을 확인하고 테스트 복사본을 제거함. 최종 오버레이의 새 단축키 안내도 AX에서 확인함.

## R32–R36 고정·Dock 가져오기·macOS 헤더 — 당시 결과

- 자동 테스트 **22개, 실패 0개**. 기존 16개에 고정 중 Option 해제/키 입력/바깥 클릭 유지와 Esc 닫기, 재호출 초기화, Dock 앱/폴더 순서·공백/한글 경로·잘못된 데이터·기존 설정 유지·중복·반복 가져오기를 검증하는 6개 테스트를 추가함.
- 최신 소스의 디버그 컴파일과 테스트에서 경고·오류가 없음을 확인함. 실제 UI 검증 결과는 아래에 추가함.
- 실제 Dock 저장 데이터에서 고정 앱 28개와 폴더 5개의 형식을 확인함. 개인 항목 목록은 저장소에 복사하지 않음. 형식 관찰만으로 앱 안의 가져오기 성공을 간주하지 않음.
- 실제 오버레이 900×720pt에서 왼쪽 핀, 중앙 앱 이름/설명, 오른쪽 단일 캡슐의 프로필/설정 배치를 AX와 창 스크린샷으로 확인함. 핀을 누르면 닫기 접근성 이름과 `xmark`, 고정 안내로 바뀜. `⌘⇧5` 입력 후 고정된 오버레이가 유지됨. 캡처 파일 저장까지 수행하지 않았고 실제 배경의 유리 합성 품질을 창 단독 캡처로 판정하지 않음.
- 실제 설정 창에서 Dock 가져오기 실행: 31개 추가, 기존 항목을 포함해 36개 저장. 재실행 시 0개 추가. 저장된 앱·폴더의 순서가 실제 Dock과 일치하고 Finder/휴지통 위치 및 중복 ID가 없음을 확인함. Dock의 고정 앱/폴더 설정 내용은 실행 전후 동일함.
- 가져오기 결과 메시지와 긴 등록 목록을 포함한 580×792pt 설정 화면에서 버튼·목록 스크롤·하단 안내가 잘리지 않음을 확인함. 새 폴더와 기존 폴더는 오버레이 선택이 유지됨.
- 도구는 보조키 단독 길게 누르기를 지원하지 않아 실제 Option 단독 유지/해제는 사용자 실기 항목으로 남김. 고정 상태의 해제 정책은 자동 테스트로 확인함. 현재 개발 앱에서 접근성 권한 안내가 표시되어 전역 Option 호출/실제 창 제목은 권한 허용 후 검증해야 함.
- macOS 조작 점검에서 설정 창의 `⌘W`가 작동하지 않음을 발견하여 AppKit 기본 앱/파일 메뉴와 닫기 responder를 연결함. `⌘W`는 앱 창이 키 입력을 받는 경우에만 적용하며 다른 앱의 닫기 단축키를 가로채지 않음.
- 최종 릴리스 빌드·ad-hoc 서명 검증 통과. 재실행 뒤 36개 등록 항목과 자동 실행 켜짐이 유지됨. 실제 앱에서 `⌘W`로 설정 창 닫기, 고정 오버레이에서 `⌘,`로 설정 열기, 핀 → `×` 전환 및 `×` 닫기 후 재호출 시 일반 모드로 복귀를 확인함. 마지막에는 캡처용으로 오버레이를 고정해 둠.

## R31 통합 휴지통 수정 — 당시 결과

- 원인은 Finder에 로컬 `~/.Trash` 폴더 URL을 전달한 것. 현재는 Finder 애플리케이션의 `trash` 객체를 `aevt`/`odoc` 열기 이벤트로 전달함. 일반 폴더의 Finder URL 열기는 별도로 유지함.
- 자동 테스트 **16개, 실패 0개**. 기존 15개에 Finder 대상·열기 이벤트·최상위 `trash` 객체 지정 검사를 추가함. 테스트는 실제 파일을 삭제하거나 휴지통 내용을 읽지 않음.
- 릴리스 빌드·패키징·ad-hoc 서명 검증 통과. 실행 중인 이전 개발 앱을 종료하고 새 빌드를 실행함.
- 실제 새 휴지통 타일의 ‘Dock과 같은 통합 휴지통’ 도움말을 AX에서 확인하고 클릭함. Finder의 Bin에 표시된 **85개 항목의 URL 집합이 사용자가 열어둔 통합 Bin과 전부 일치**함. 창 제목만으로 판정하지 않음. 검증한 개인 파일 목록은 저장소에 남기지 않음.
- 추가로 일반 Finder 창을 연 뒤 다시 휴지통을 여는 반복 검증을 준비했으나 Mac 잠금으로 완료하지 못함. 외장 저장소의 연결/해제, 실제 복원, 다른 OS·공증된 앱의 동작은 이번 검증 범위에 포함하지 않음. 추가 전체 디스크 접근 권한을 요청하지 않음.

## R28/R29 추가 검증 — 당시 결과

- 자동 테스트 **15개, 실패 0개**. 기존 10개에 기존 등록 데이터/순서 유지, 폴더별 여는 방식 저장, 휴지통의 오버레이 선택 차단(저장 데이터 포함), 잠금 중복 방지와 재획득, 잠금 오류 구별을 추가함.
- 새 릴리스 앱 컴파일·패키징 및 ad-hoc 서명 검증 통과.
- 실제 설정 화면에서 로그인 시 자동 실행 등록 → 활성화, 해제 → 비활성화, 재등록 → 활성화를 확인. **현재 사용자 설정은 자동 실행 켜짐**으로 둠. 실제 로그아웃/로그인은 진행하지 않음.
- 처음 한 번도 등록하지 않은 `SMAppService.mainApp`이 이 환경에서 `.notFound`를 반환하는 것을 확인. 앱 위치 오류라고 단정하지 않도록 ‘자동 실행이 아직 등록되지 않았습니다’로 안내를 수정함.
- 서로 다른 경로에서 실행 중이던 이전 빌드 2개를 종료. 새 앱이 실행 중일 때 직접 실행 3개와 임시 복사본 실행이 모두 정상 종료되고 주 프로세스 1개만 남는 것을 확인.
- 주 프로세스 종료 후 세 번 동시에 시작했을 때도 생존 프로세스가 정확히 1개인 것을 확인. 종료 후 잠금 재획득도 동작함. 강제 충돌/다중 사용자 환경의 별도 검증은 하지 않음.
- 네이티브 설정 화면의 자동 실행 토글, 일반 폴더의 여는 방식 메뉴, 휴지통의 ‘Finder에서만 열 수 있습니다’ 고정 안내를 AX와 스크린샷으로 확인.
- 일반 폴더를 Finder 모드로 바꾸고 재실행 후 선택이 유지되는 것을 실제 오버레이 도움말에서 확인. Finder의 Downloads 창 생성도 관찰함.
- 검증 후 다운로드 폴더는 원래의 오버레이 모드로 UI에서 복원함. 최종 빌드 재실행 후에도 자동 실행 켜짐 및 휴지통 Finder 전용 안내를 확인함.
- 휴지통 타일 클릭 후 Finder의 Bin 창이 열림을 확인했으나 당시에는 로컬 폴더와 통합 휴지통을 구분해 검증하지 못했음. R31에서 사용자가 내용 차이를 보고하여 수정하고 목록을 비교함. 앱의 휴지통 오버레이/권한 요청 흐름은 제거함. ‘되돌려 놓기’는 직접 검증하지 않았으며 Finder에 맡김.
- 설정 창의 기본 크기에서 새 컨트롤·등록 목록·하단 안내가 잘리지 않는 것을 실제 화면으로 확인. 최소 크기·VoiceOver·승인 대기/시스템 설정에서 직접 해제한 경우는 후속 실기 항목.
- 다시 열기 시 이미 보이는 설정 창을 우선 활성화하도록 보완하고 최종 앱에서 확인함. 검증에 사용한 임시 복사본은 제거하고 안정된 개발 앱 경로의 새 버전 하나를 실행 상태로 둠.

아래 첫 빌드 기록은 당시 결과이며 위 항목이 최신 검증 상태입니다.

## 확인한 환경

- macOS 27.2 베타, 빌드 26B5101f / Apple Silicon arm64.
- Xcode 27.2 베타, 빌드 27B5028f: `/Applications/Develop/Xcode-beta.app`.
- Swift 6.4. 프로젝트별 `DEVELOPER_DIR`로 사용했으며 전역 xcode-select는 변경하지 않음.
- 최소 배포 버전 macOS 26. macOS 26 실기·Intel에서는 검증하지 않음.

## 통과

- Swift/SwiftUI/AppKit 네이티브 앱 컴파일과 로컬 릴리스 패키징.
- 자동 테스트 **10개, 실패 0개**. 사용자 최근 앱/창 예시 3종, 닫힌 항목 정리, 다양한 화면 비율/음수 원점/경계, 초광폭 크기 불변, 수동 개수 및 실제 창 수 제한, Option 조합키 취소, 실제 임시 폴더의 자연 정렬·숨김 항목 제외·앱 패키지 구별·읽기 실패, 날짜순 및 누락 날짜 정렬.
- 동기화 폴더 밖에서 만든 `.app`의 ad-hoc 서명 및 `codesign --verify --deep --strict` 검증.
- macOS LaunchServices로 실제 앱 실행. 약 30분 뒤 프로세스 생존 확인. 해당 시점 `ps` 스냅샷은 CPU 0.0%, RSS 약 88MiB였음. **접근성 권한 미허용 상태의 단일 표본**이며 다수 창/반복 호출/장시간 성능 보장이 아님.
- 자체 NSHostingView 렌더 결과에서 초기 권한 안내 화면의 제목·구획·푸터가 패널 안에 배치됨을 확인. 이 이미지는 앱 자신의 콘텐츠만 렌더한 것으로 WindowServer의 실제 유리 배경 합성을 검증하지 않음.

## 아직 확인하지 못한 항목

- 접근성 허용 후 실제 Option 단독 호출·클릭 후 해제·앱/창 전환. 권한은 사용자가 시스템 설정에서 허용해야 함.
- iTerm 실제 여러 창, Safari/Chrome, 최소화·다른 Space·전체 화면·Stage Manager 전환.
- UI를 통한 폴더 등록·순서 변경·파일 실행·휴지통 접근 허용/거부. 파일 목록·정렬의 자동 테스트와 실제 사용자 조작 검증은 다름.
- 실제 배경 위의 Liquid Glass, Light/Dark·투명도 줄이기·VoiceOver, 물리적 다중 모니터.
- 유휴 상태와 5/20/50개 창의 CPU·메모리·호출 지연을 Instruments로 비교하는 성능 측정.
- 앱별 메뉴·메뉴 순서 변경·집중 모드 연동은 다음 구현 단계.

## 환경 이슈와 재현 방법

- 명령줄 도구만으로 앱은 컴파일할 수 있지만 현재 CLT에는 XCTest가 없어 테스트는 설치된 전체 Xcode를 사용함.
- 빌드 캐시는 프로젝트 `.build`에 둠. 코드 서명 전에 생성물의 Finder 메타데이터를 제거하고 서명을 검증함.
- Desktop 작업 경로는 File Provider 메타데이터가 `.app`에 다시 붙는 것이 확인됨. 기본 앱 출력 경로를 `~/Library/Developer/TileLauncher/build`로 분리함. 소스 저장 위치는 변경하지 않음.
- 로컬 릴리스 스크립트는 최적화된 코드에 별도 dSYM을 생성하지 않음. Instruments에서 상세 소스 단위 분석이 필요하면 디버그 심벌을 포함한 별도 프로파일 빌드를 사용할 것.
- 컴퓨터 사용 도구의 앱 선택이 시간 초과하여 클릭 기반 UI QA를 완료하지 못함. 성공으로 기록하지 않음.
- 기본 실행은 메뉴 막대 앱. `--show` 인자를 주면 패널을 즉시 열어 확인할 수 있음. 개발 검증용 `--render-check <PNG 경로>`는 자체 콘텐츠를 저장하고 종료하며 다른 앱/화면 전체를 캡처하지 않음.

```sh
DEVELOPER_DIR="/Applications/Develop/Xcode-beta.app/Contents/Developer" ./scripts/test.sh
DEVELOPER_DIR="/Applications/Develop/Xcode-beta.app/Contents/Developer" ./scripts/build.sh
open "$HOME/Library/Developer/TileLauncher/build/Tile Launcher.app"
```

## 다음 사용 확인

1. 메뉴 막대 격자 → 설정 → 앱·폴더 추가, 순서를 바꾸고 재실행해 유지 확인.
2. 접근성 설정에서 Tile Launcher 허용 후 Option 단독/Option+다른 키 비교.
3. 실제 OS 창 6개 이상에서 순서·두 줄·수동 개수·스크롤 확인.
4. 다운로드와 휴지통의 읽기 권한, 폴더 진입/뒤로/파일 열기 확인.
5. 실제 외관 피드백과 Instruments 결과를 바탕으로 다음 변경을 기록.
