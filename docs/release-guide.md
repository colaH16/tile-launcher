# Apple 개발자 등록과 GitHub 공개 배포 준비

확인일: 2026-10-13, Asia/Seoul. R91–R92 기준. 아직 공개 바이너리 Release/개발자 등록/공증 제출을 실행한 상태는 아니다.

## 비용과 가입 유형

- 한국 Apple Developer 앱의 멤버십 표시 가격은 **연 129,000원**이다. [한국 App Store의 앱 내 구입 항목](https://apps.apple.com/kr/app/apple-developer/id640199958)에서 확인했다.
- 웹의 공식 기준은 **연 US$99**이고 지역별 현지 가격이 적용된다. 최종 금액/세금은 가입 결제 화면을 기준으로 한다. [Apple 멤버십 안내](https://developer.apple.com/kr/help/account/membership/program-enrollment/)
- 개인 제작자로 배포하면 일반 Apple Developer Program의 개인 등록을 사용할 수 있다. 법인의 이름으로 등록하려면 조직 요건과 D-U-N-S 확인이 필요하다. 개인 등록은 법적 실명을 사용하며 App Store에 배포할 경우 판매자 이름도 실명이다. [개인/조직 등록 요건](https://developer.apple.com/kr/programs/enroll/)
- Developer ID를 이용한 Mac App Store 외부 배포가 이 프로그램의 기능이다. 현재 Tile Launcher의 GitHub 배포 방향에 해당한다. [Developer ID 안내](https://developer.apple.com/kr/developer-id/)

## 사용자가 진행하는 등록

1. Mac/iPhone/iPad의 [Apple Developer 앱](https://apps.apple.com/kr/app/apple-developer/id640199958)을 연다.
2. 계정 → 로그인 → 지금 등록하기를 선택한다. 이중 인증이 켜진 Apple 계정을 사용한다.
3. 개인 제작 기준으로 개인을 선택하고 법적 이름/연락처와 요청받은 신원 확인을 완료한다. 한국어 이름은 로마자 표기도 요구될 수 있다. 신분증 종류 등은 해당 화면 안내를 따른다.
4. 약관을 검토하고 멤버십을 결제한다. 앱을 통한 가입은 연간 자동 갱신 구독이다.
5. 등록 승인을 받은 뒤 Xcode의 Apple 계정 설정에서 해당 팀이 보이는지 확인한다.

상세 절차와 기기 요건: [Apple Developer 앱 등록 안내](https://developer.apple.com/kr/help/account/membership/enrolling-in-the-app/). 로그인·신원 확인·결제는 사용자가 직접 진행한다. 계정 비밀번호나 인증서 개인 키를 채팅/저장소에 남기지 않는다.

## 등록 후 배포 작업

목표 순서: **릴리스 빌드 → Developer ID Application 서명 → Apple 공증 → 티켓 첨부·검증 → GitHub Release**.

- Xcode 또는 개발자 계정에서 **Developer ID Application** 서명 인증서를 만든다. 현재 빌드는 `codesign --sign -`인 ad-hoc 서명이며 정식 배포 서명이 아니다.
- 배포 버전/빌드 번호를 정하고 해당 소스 커밋에 연결한다. 같은 코드에 서명만 바꾸는 첫 전환에서도 앱의 교체 판단이 분명하도록 빌드 번호를 갱신한다.
- 현재 `scripts/build.sh`는 로컬 개발용이다. 정식 서명 경로에서는 강화된 런타임과 보안 타임스탬프를 적용하고 필요한 권한만 선언한 뒤 기능을 다시 검증한다. 인증서 이름을 하드코딩하거나 키를 저장소에 넣지 않는다.
- 배포 파일은 ZIP 또는 DMG로 패키징한다. `notarytool`로 공증을 제출하고 승인 결과를 확인한 뒤 `stapler`로 앱/DMG에 티켓을 첨부한다. 공증 후 바뀐 파일은 최종 형태로 다시 패키징한다.
- 코드 서명/공증 티켓/Gatekeeper와 실제 다운로드·첫 실행·업데이트를 검증한다. 통과한 파일, 체크섬, 지원 macOS/CPU, 변경 내용으로 GitHub Release를 만든다.

공증은 Apple의 자동 보안 검사다. App Store 제출 심사와 구분하며 서명/공증만으로 앱 기능의 호환성을 보장하지 않는다. [Apple의 서명·강화된 런타임·공증 절차](https://developer.apple.com/kr/developer-id/)

## 첫 공개 릴리스 전에 남은 확인

- 현재 개인용 빌드는 Apple Silicon/macOS 27.2 beta 환경에서 주로 확인했다. 선언된 최소 macOS 26과 지원할 실제 OS/CPU에서 시험하고, 공개 배포 빌드에 사용할 정식 Xcode/SDK를 정한다.
- 집중 모드 필터 추가·프로필 변경·필터 해제·앱 재시작을 실제 시스템에서 확인한다. 메타데이터가 있다는 사실만으로 추종 성공이라고 하지 않는다.
- Developer ID/강화된 런타임 적용 상태에서 접근성·전역 Option 입력·메뉴 실행·Finder 휴지통·로그인 항목·여러 데스크탑 선택을 확인한다. 내부 Space API의 지원 범위도 릴리스 노트에 반영한다.
- 배포 앱 설치 위치를 정리하고 개발/테스트 사본의 등록 충돌을 피한다. 향후 개발용 앱을 동시에 유지하려면 별도 번들 ID와 설정/권한 이전 방식을 설계한다. 현재 사용자의 기본 앱 ID를 임의로 변경하지 않는다.
- 유효한 Developer ID, 공증 인증 수단, 지원 범위와 최종 버전이 준비되기 전에는 지금의 ad-hoc 파일을 정식 서명 릴리스로 게시하지 않는다.

## 집중 모드 진단 기록과 다음 확인

2026-10-13 읽기 점검에서 현재 개발 앱에는 AppIcon.icns, LauncherFocusIntent, ProfileEntity, 프로필 query 메타데이터가 모두 있었다. 서명은 ad-hoc이며 Team ID는 없었다.

같은 앱 ID로 등록된 12개 경로 중 11개는 이전 테스트/작업 폴더 사본이었다. 해당 경로만 등록 해제하고 현재 `~/Library/Developer/TileLauncher/build/Tile Launcher.app`을 재등록하여 한 경로만 남겼다. 파일이나 집중 모드 연결을 삭제하지 않았다. 시스템 설정의 아이콘/필터 캐시가 즉시 갱신됐는지는 UI를 조작하지 않아 확인하지 못했다.

저장 설정에서 **집중 모드에 따른 프로필 자동 선택은 꺼져 있었다**. 사용자의 선택을 임의로 바꾸지 않았다. 확인 순서는 다음과 같다.

1. Tile Launcher 설정 → 등록 항목·프로필 → ‘집중 모드 필터에 따라 프로필 자동 선택’을 켠다.
2. 시스템 설정을 다시 열고 집중 모드 → 해당 모드 → 앱 필터에서 Tile Launcher의 원하는 프로필을 고른다.
3. 해당 집중 모드를 켠 다음 오버레이를 닫았다가 다시 열어 등록 목록을 확인한다. 이번 오버레이의 임시 프로필 선택은 다음 호출에서 해제되는 정책이다.
4. 집중 모드 해제 후 마지막 수동 프로필로 돌아오는지 확인한다. 필터가 삭제된 프로필을 참조할 때도 수동 구성을 우선하도록 코드를 보완했다.

앱 필터 아이콘은 앱 아이콘을 쓰며, 실행 중 앱의 perform 호출과 current 조회가 연동 경로다. [Apple Focus filters 설명](https://developer.apple.com/videos/play/wwdc2022/10121/). 아이콘 부재의 원인이 인증서 미등록이라고 단정하지 않는다.
