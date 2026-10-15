# Apple 개발자 등록과 GitHub 공개 배포 준비

확인일: 2026-10-15, Asia/Seoul. [v1.9.1](https://github.com/colaH16/tile-launcher/releases/tag/v1.9.1)을 2026-10-15 19:40:57 KST에 공개하고 개발 Mac 업데이트까지 완료했다. 공증 제출은 사용자의 다른 Mac에서 진행했으며, 이 Mac에서는 동일한 서명 앱에 Apple 티켓을 받아 검증하고 최종 ZIP을 만들었다. 공개 ZIP 재검증 기록은 [1.9.1 검증](reviews/1.9.1-app-settings-visibility.md)에 있다.

이전 기록: [v1.9.0 정식 릴리스](https://github.com/colaH16/tile-launcher/releases/tag/v1.9.0)를 Developer ID 서명·Apple 공증·티켓·Gatekeeper 및 공개 후 재다운로드 검증을 거쳐 2026-10-15 17:39:04 KST에 공개했다. 이전 공개 자산은 보존한다.

## R102 · 공개 완료와 버전 정책

R102 승인에 따라 5388c2c 커밋에서 0.16.3(6)을 새로 패키징해 공개했다. 기존 미게시 0.2.0(4) ZIP은 사용하지 않았다. 다음 버전에도 아래 절차를 사용하며 공개된 v0.16.3 자산을 덮어쓰지 않는다.

`release/config.json`은 버그·UI 수정이면 patch, 기능 추가·변경이면 minor를 올리고 patch=0으로 한다. build는 전달 산출물마다 증가하며 [CHANGELOG](../CHANGELOG.md)를 따른다. `scripts/build.sh`도 같은 값을 Info.plist에 넣고 설정은 실행 중인 번들에서 읽는다. 동일 패치의 내부 컴파일 재시도는 번호를 소비하지 않는다. 릴리스 노트 제목도 version과 일치시킨다.

## 비용과 가입 유형

- 한국 Apple Developer 앱의 멤버십 표시 가격은 **연 129,000원**이다. [한국 App Store의 앱 내 구입 항목](https://apps.apple.com/kr/app/apple-developer/id640199958)에서 확인했다.
- 웹의 공식 기준은 **연 US$99**이고 지역별 현지 가격이 적용된다. 최종 금액/세금은 가입 결제 화면을 기준으로 한다. [Apple 멤버십 안내](https://developer.apple.com/kr/help/account/membership/program-enrollment/)
- 개인 제작자로 배포하면 일반 Apple Developer Program의 개인 등록을 사용할 수 있다. 법인의 이름으로 등록하려면 조직 요건과 D-U-N-S 확인이 필요하다. 개인 등록은 법적 실명을 사용하며 App Store에 배포할 경우 판매자 이름도 실명이다. [개인/조직 등록 요건](https://developer.apple.com/kr/programs/enroll/)
- Developer ID를 이용한 Mac App Store 외부 배포가 이 프로그램의 기능이다. 현재 Tile Launcher의 GitHub 배포 방향에 해당한다. [Developer ID 안내](https://developer.apple.com/kr/developer-id/)

## 독립 배포 빌드 준비

현재 공개/개발 구성은 `release/config.json`의 v1.1.5, 빌드 20, Apple Silicon, 정식 릴리스(prerelease=false)다. R141에 따라 실제 Developer ID 서명·공증·검증·누적 노트 게시를 완료했다. Apple 공증 여부와 GitHub의 정식/사전 릴리스 구분은 별개이며 실제 manifest의 상태를 확인한다.

R108의 0.17.1 공개는 완료했다. R120에서 0.17.6 공개를 요청해 R113의 보류를 해제했고 2026-10-13 17:03 KST 게시를 완료했다. R123에서 R119/R121의 여백 작업도 재개했다. 아래 단계는 이후 새 버전에 적용하며 이미 공개한 릴리스를 다시 게시/덮어쓰지 않는다. 저장소 루트에서 실행한다. Xcode가 다른 위치에 있으면 DEVELOPER_DIR만 바꾼다. 실행 중 개발 앱은 설치/재실행하지 않는다.

```sh
export DEVELOPER_DIR=/Applications/Develop/Xcode-beta.app/Contents/Developer
./scripts/test.sh
python3 scripts/release.py prepare
python3 scripts/release.py verify
```

- `prepare`는 깨끗한 커밋의 `git archive` 소스에서 빌드하고 버전/소스 SHA를 번들에 기록한다. 작업 트리가 수정 중이면 중단한다.
- `~/Library/Developer/TileLauncher/releases/v1.1.5/downloads`에 ZIP, `release-metadata.json`, `SHA256SUMS.txt`를 생성한다. prepare/sign 단계는 `Tile-Launcher-1.1.5-arm64-unnotarized.zip`, 공증/티켓 검증 후는 `Tile-Launcher-1.1.5-arm64.zip`이다. ZIP에는 앱과 라이선스/설치 안내가 포함된다.
- `verify`는 앱 서명, 리소스·실행 권한, 플랫폼, 아이콘/Focus 정보, 버전/소스, 체크섬을 확인한다. ZIP도 다시 풀어 같은 앱인지 검사한다. 앱을 실행하거나 사용자 권한을 변경하지 않는다.
- 최종 릴리스 설명은 `~/Library/Developer/TileLauncher/releases/v1.1.5/release-notes.md`에 생성한다. manifest의 실제 서명·공증 상태에 맞는 안내가 자동으로 포함된다.
- 수정 중 리허설에는 `prepare --local-check --output /tmp/tile-release-rehearsal`을 사용한다. 이 출력은 local_only로 기록되어 서명 승격/GitHub 업로드가 거부된다. 출력 폴더는 비어 있어야 하며 기존 결과를 자동 삭제하지 않는다. 기본 출력은 동기화 밖의 `~/Library/Developer/TileLauncher/releases/v1.1.5`이다. Desktop/문서/클라우드 저장소를 서명 출력으로 지정하면 중단한다.

## GitHub 초안과 정식 게시

### 누적 변경 범위 · R130

릴리스 설명은 마지막 커밋/패치만 요약하지 않는다. **직전 실제 공개 릴리스 → 이번 공개 버전** 사이의 모든 앱 버전을 포함한다. `gh api repos/colaH16/tile-launcher/releases`의 공개 시각/정식 상태와 태그를 확인하며 가장 가까운 로컬 빌드나 가장 최근 커밋을 기준으로 삼지 않는다.

- `release/notes-range.json`에 `previous_release`와 오름차순 `included_versions`를 둔다. 첫 공개만 `previous_release: null`이다. `release/notes.md`의 제목/업데이트 범위와 각 `### 버전` 변경 항목을 함께 맞춘다.
- `CHANGELOG.md`, 요청/실제 검증 기록과 두 태그 사이 Git 변경을 대조한다. 미게시 중간 버전의 기능 추가/변경·버그/UI 수정도 모두 반영한다. 같은 기능은 합쳐 설명하되 버전별 도입/최종 동작을 구별한다. 되돌린 탭/크기 같은 임시 단계는 현재 상태로 오인되지 않게 연결한다.
- 최초 공개는 당시 포함된 기능 전체를 설명한다. 소급 분류 표의 번호를 별도로 공개했던 릴리스처럼 쓰지 않는다. 미채택 시안·미구현 계획은 제외한다.
- `prepare`는 CHANGELOG 범위와 포함 버전/본문을 확인한다. `draft`/`publish`는 GitHub의 직전 정식 공개 태그까지 재확인해 기준이 달라졌거나 중간 버전/변경 섹션이 빠지면 중단한다. 이 검사는 범위/버전 누락을 막으며 각 기능 설명의 정확성은 위 자료 대조로 검토한다.
- 서명·공증 파일을 이미 만든 뒤 **설명만** 보완했다면 노트를 검토·커밋한 후 `python3 scripts/release.py refresh-notes`를 사용한다. 기존 설명/manifest를 notes-history에 보존하고 앱/ZIP/메타데이터/체크섬은 다시 만들지 않는다. 이미 공개된 릴리스/초안에는 이 명령을 쓰지 않는다.
- 과거 공개 노트의 오탈자/누락을 승인받아 보완할 때는 `release/history/<태그>.md`에 설명 원문을 버전 관리하고 `gh release edit <태그> --notes-file ...`로 설명만 갱신한다. 최초 공개 시각·정식 상태·태그·소스·모든 자산/해시와 최신 릴리스 표시를 전후 대조한다. 공개 당시 패키지 안의 설명/manifest는 변경하지 않는다.

2026-10-14에 네 공개 설명을 보완했다. 범위와 본문 원본은 [과거 공개 노트](../release/history/README.md)에 있다. R137에서는 1.0.0 이후 모든 변경을 포함한 1.1.3을 공개했다. R141에서는1.1.3 이후1.1.4/1.1.5 전체를 포함한1.1.5를 공개했다. 다음 공개 범위의 기준은v1.1.5다.

아래 명령은 원격 태그/릴리스를 변경한다. **v0.16.3, v0.17.1, v0.17.6, v1.0.0, v1.1.3, v1.1.5는 게시 완료했으므로 재실행하지 않는다.** 다음 버전의 새 산출물에 사용한다. 소스는 origin/main에 푸시되어 있어야 하며 GitHub CLI의 로그인(`gh auth login`)이 필요하다. 저장소가 PUBLIC인지 확인하고 공개 범위를 자동 변경하지 않는다.

```sh
# 개발용 서명/공증 없음으로 배포하기로 정했을 때
python3 scripts/release.py draft --allow-unnotarized
python3 scripts/release.py publish --allow-unnotarized
```

초안은 검증한 소스 커밋에 해당 버전 태그를 연결하고 지정한 세 파일만 올린다. 인증된 릴리스 목록을 페이지별로 조회해 기존 초안도 확인하며 태그 조회 API의 404를 초안 부재로 해석하지 않는다. 기존 릴리스/다른 커밋의 태그는 덮어쓰지 않는다. 설명·자산 목록을 확인하고 asset ID로 내려받은 파일의 체크섬까지 일치해야 release ID로 정식 공개한다. 중단된 업로드나 다른 초안을 자동 덮어쓰지 않는다.

[GitHub CLI 릴리스 생성](https://cli.github.com/manual/gh_release_create) · [GitHub 릴리스 관리](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)

## Developer ID 서명·공증

**Developer ID Application 서명 완료·검증 첫 빌드는 1.0.0**이다. 후보를 준비할 때 버전/빌드/노트를 맞추고 실제 서명 검증 전에는 완료/공개로 기록하지 않는다. 가입·인증서 생성·ad-hoc 서명만으로 전환하지 않는다. 공증은 서명 뒤 별도로 수행한다.

먼저 개발자 등록을 마치고 Xcode에서 Developer ID Application 인증서를 만든다. 아래 SHA1은 `security find-identity -v -p codesigning`에서 확인하는 인증서 식별자이며 개인 키/암호가 아니다. Team ID도 개발자 계정에서 확인한다.

```sh
python3 scripts/release.py sign --identity CERTIFICATE_SHA1 --team-id TEAM_ID

# 민감한 값은 이 도구의 보안 프롬프트에 직접 입력한다.
xcrun notarytool store-credentials tile-launcher-notary
python3 scripts/release.py notarize --keychain-profile tile-launcher-notary
```

- Apple ID 방식에서는 API private key 경로를 빈 채로 Enter를 누른다. 앱 암호는 [Apple 계정 웹사이트](https://account.apple.com)의 로그인 및 보안 → 앱 암호에서 생성한다. 계정의 일반 로그인 암호를 대신 쓰지 않으며 생성한 앱 암호는 터미널의 보안 프롬프트에 직접 입력한다. Team ID를 확인하고 `Credentials saved to Keychain` 성공 뒤 같은 프로필 이름을 사용한다. [Apple 앱 암호 안내](https://support.apple.com/ko-kr/102654)
- 공증된 1.0.0 이후 배포는 `python3 scripts/release.py draft` → `python3 scripts/release.py publish`를 사용한다. 위 개발용 배포 예시의 `--allow-unnotarized`를 붙이지 않는다.
- sign은 Developer ID Application 유형·팀·강화된 런타임·보안 타임스탬프와 지정 권한을 검사한다. 실패 시 기존 개발용 앱을 보존하도록 임시 사본에 서명한다.
- 현재 선언하는 권한은 Finder의 통합 휴지통을 여는 Apple Events 요청을 위한 항목이다. get-task-allow/JIT/라이브러리 검증 해제 같은 예외는 넣지 않는다. 실제 Developer ID 환경에서 Finder/접근성/Space/Focus 동작을 재검증해야 한다. [Apple Events 권한](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events)
- 공증을 한 번 제출하면 ID를 저장한다. 진행 중에는 같은 notarize 명령을 다시 실행하여 그 제출만 조회한다. 제출 응답이 끊긴 경우 자동 재업로드하지 않으며, `notarytool history`에서 ID를 확인한 뒤 `--submission-id`로 복구한다.
- Accepted 후에만 티켓을 붙이고 Gatekeeper 검사를 통과한 앱을 다시 ZIP으로 만든다. 이전 사본은 pre-sign.app/pre-staple.app으로 보존한다. 공증 후 다운로드 폴더에 이전 ZIP이 남을 수 있지만 게시 도구는 manifest에 기록된 최종 파일만 사용한다.
- 공증된 결과는 `--allow-unnotarized` 없이 draft/publish할 수 있다. 이미 0.x를 개발용 서명으로 공개했더라도 최초 Developer ID 서명본은 1.0.0으로 별도 준비한다. 공개된 자산을 조용히 바꾸지 않는다.
- 로컬 manifest/log/인증 정보는 공개하지 않는다. 공개 메타데이터에는 버전·아키텍처·소스 SHA·도구 버전·서명 상태만 담는다.

## 가입 경로 안내 정정 · 2026-10-14

앱 가입만 안내했던 기존 절차는 웹 경로를 함께 제시하지 않은 누락이었다. 사용자는 앱 신분 확인에 실패한 뒤 웹에서 가입을 완료했다. [웹 가입](https://developer.apple.com/help/account/membership/program-enrollment)과 [Apple의 신원 확인 조건](https://developer.apple.com/help/account/membership/identity-verification/)을 먼저 확인하며, 웹 경로가 모든 계정에서 신분 확인을 생략한다고 보장하지 않는다. 아래 앱 경로는 선택지 중 하나다.

가입 후 GitHub 앱 배포에는 Developer ID Application 인증서와 로컬 개인 키가 필요하다. Xcode Settings의 Apple Accounts/Accounts에서 유료 팀 → Manage Certificates → + → Developer ID Application을 생성한다. [공식 인증서 안내](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/). 같은 Mac에서 만들면 인증서·개인 키를 내보낼 필요가 없다. 실제 local identity를 확인한 후 서명한다.

## 사용자가 진행하는 등록

1. Mac/iPhone/iPad의 [Apple Developer 앱](https://apps.apple.com/kr/app/apple-developer/id640199958)을 연다.
2. 계정 → 로그인 → 지금 등록하기를 선택한다. 이중 인증이 켜진 Apple 계정을 사용한다.
3. 개인 제작 기준으로 개인을 선택하고 법적 이름/연락처와 요청받은 신원 확인을 완료한다. 한국어 이름은 로마자 표기도 요구될 수 있다. 신분증 종류 등은 해당 화면 안내를 따른다.
4. 약관을 검토하고 멤버십을 결제한다. 앱을 통한 가입은 연간 자동 갱신 구독이다.
5. 등록 승인을 받은 뒤 Xcode의 Apple 계정 설정에서 해당 팀이 보이는지 확인한다.

상세 절차와 기기 요건: [Apple Developer 앱 등록 안내](https://developer.apple.com/kr/help/account/membership/enrolling-in-the-app/). 로그인·신원 확인·결제는 사용자가 직접 진행한다. 계정 비밀번호나 인증서 개인 키를 채팅/저장소에 남기지 않는다.

## 등록 후 배포 작업

목표 순서: **릴리스 빌드 → Developer ID Application 서명 → Apple 공증 → 티켓 첨부·검증 → GitHub Release**.

- Xcode 또는 개발자 계정에서 **Developer ID Application** 서명 인증서를 만든다. 로컬 build.sh는 `codesign --sign -`인 ad-hoc 서명이며 공개한 1.0.0의 Developer ID 서명과 구별한다.
- 배포 버전/빌드 번호를 정하고 해당 소스 커밋에 연결한다. 같은 코드에 서명만 바꾸는 첫 전환에서도 앱의 교체 판단이 분명하도록 빌드 번호를 갱신한다.
- 현재 `scripts/build.sh`는 로컬 개발용이다. `scripts/release.py`는 이를 독립 소스/출력 경로에서 호출하고 서명·공증·검증·GitHub 초안/게시를 분리한다. Developer ID 경로에서는 강화된 런타임과 보안 타임스탬프를 적용하고 필요한 권한만 선언한 뒤 기능을 다시 검증한다. 인증서 이름을 하드코딩하거나 키를 저장소에 넣지 않는다.
- 배포 파일은 ZIP 또는 DMG로 패키징한다. `notarytool`로 공증을 제출하고 승인 결과를 확인한 뒤 `stapler`로 앱/DMG에 티켓을 첨부한다. 공증 후 바뀐 파일은 최종 형태로 다시 패키징한다.
- 코드 서명/공증 티켓/Gatekeeper와 실제 다운로드·첫 실행·업데이트를 검증한다. 통과한 파일, 체크섬, 지원 macOS/CPU, 변경 내용으로 GitHub Release를 만든다.

공증은 Apple의 자동 보안 검사다. App Store 제출 심사와 구분하며 서명/공증만으로 앱 기능의 호환성을 보장하지 않는다. [Apple의 서명·강화된 런타임·공증 절차](https://developer.apple.com/kr/developer-id/)

## 공개 후에도 남은 플랫폼 실기 확인

- 현재 개인용 빌드는 Apple Silicon/macOS 27.2 beta 환경에서 주로 확인했다. 선언된 최소 macOS 26과 지원할 실제 OS/CPU에서 시험하고, 공개 배포 빌드에 사용할 정식 Xcode/SDK를 정한다.
- 집중 모드 필터 추가·프로필 변경·필터 해제·앱 재시작을 실제 시스템에서 확인한다. 메타데이터가 있다는 사실만으로 추종 성공이라고 하지 않는다.
- Developer ID/강화된 런타임 적용 상태에서 접근성·전역 Option 입력·메뉴 실행·Finder 휴지통·로그인 항목·여러 데스크탑 선택을 확인한다. 내부 Space API의 지원 범위도 릴리스 노트에 반영한다.
- 배포 앱 설치 위치를 정리하고 개발/테스트 사본의 등록 충돌을 피한다. 향후 개발용 앱을 동시에 유지하려면 별도 번들 ID와 설정/권한 이전 방식을 설계한다. 현재 사용자의 기본 앱 ID를 임의로 변경하지 않는다.
- 유효한 Developer ID, 공증 인증 수단, 지원 범위와 최종 버전이 준비되기 전에는 지금의 ad-hoc 파일을 정식 서명 릴리스로 게시하지 않는다.

## 집중 모드 진단 기록과 다음 확인

**R103에서 확인된 새 증거:** GitHub 0.16.3을 Applications 아래에서 실행했지만 Focus 필터 로딩이 시간 초과됐다. linkd는 `Unable to get teamId from dev.cola16.TileLauncher`를 반복했고 실제 서명은 TeamIdentifier 없음이었다. 아이콘 파일·NSWorkspace 아이콘 로딩·메타데이터 읽기는 정상이다. 당시 유효한 코드 서명 identity는 0개였다. R123에서 Team ID 있는 Developer ID 서명/공증을 완료했으나 실제 Focus 필터의 전환/해제는 별도 확인이 남는다. 자세한 근거와 다음 검증은 [Focus 진단](focus-diagnostics.md)을 따른다. 아래 R91 당시의 캐시/설정 점검은 이 오류가 해결됐다는 기록이 아니다.

2026-10-13 읽기 점검에서 현재 개발 앱에는 AppIcon.icns, LauncherFocusIntent, ProfileEntity, 프로필 query 메타데이터가 모두 있었다. 서명은 ad-hoc이며 Team ID는 없었다.

같은 앱 ID로 등록된 12개 경로 중 11개는 이전 테스트/작업 폴더 사본이었다. 해당 경로만 등록 해제하고 현재 `~/Library/Developer/TileLauncher/build/Tile Launcher.app`을 재등록하여 한 경로만 남겼다. 파일이나 집중 모드 연결을 삭제하지 않았다. 시스템 설정의 아이콘/필터 캐시가 즉시 갱신됐는지는 UI를 조작하지 않아 확인하지 못했다.

저장 설정에서 **집중 모드에 따른 프로필 자동 선택은 꺼져 있었다**. 사용자의 선택을 임의로 바꾸지 않았다. 확인 순서는 다음과 같다.

1. Tile Launcher 설정 → 등록 항목·프로필 → ‘집중 모드 필터에 따라 프로필 자동 선택’을 켠다.
2. 시스템 설정을 다시 열고 집중 모드 → 해당 모드 → 앱 필터에서 Tile Launcher의 원하는 프로필을 고른다.
3. 해당 집중 모드를 켠 다음 오버레이를 닫았다가 다시 열어 등록 목록을 확인한다. 이번 오버레이의 임시 프로필 선택은 다음 호출에서 해제되는 정책이다.
4. 집중 모드 해제 후 마지막 수동 프로필로 돌아오는지 확인한다. 필터가 삭제된 프로필을 참조할 때도 수동 구성을 우선하도록 코드를 보완했다.

앱 필터 아이콘은 앱 아이콘을 쓰며, 실행 중 앱의 perform 호출과 current 조회가 연동 경로다. [Apple Focus filters 설명](https://developer.apple.com/videos/play/wwdc2022/10121/). 아이콘 부재의 원인이 인증서 미등록이라고 단정하지 않는다.
