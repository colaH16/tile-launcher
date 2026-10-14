# 0.16.3 Focus 필터 연결 실패

## 2026-10-14 · R126 사용자 확인

사용자가 Developer ID 서명·공증 이후 Focus가 된다고 확인했다. 캡처에서 Tile Launcher의 프로필 선택 화면과 추가 버튼이 정상 로딩되며 0.16.3의 연결 시간 초과가 재현되지 않는다. 앱 아이콘은 여전히 기본 아이콘으로 표시된다. 이 결과는 필터 설정 로딩/사용자 성공 보고이며 모든 Focus 자동 전환·해제·재시작 조합을 에이전트가 직접 확인한 것은 아니다.

확인일: 2026-10-13 (Asia/Seoul), R103. 현재 환경은 Apple Silicon / macOS 27.2 beta다.

## 2026-10-14 · R123 서명 이후 상태

1.0.0(14)을 TeamIdentifier VV2W9U5XT3의 유효한 Developer ID Application으로 서명하고 Apple 공증 Accepted·티켓·Gatekeeper를 통과했다. 같은 번들 ID와 Focus 메타데이터를 유지한 채 /Applications/launch at Login/Tile Launcher.app에 설치했다. 아직 사용자 앱을 자동 재시작하거나 시스템 Focus를 조작하지 않았다. 아래의 identity 0개/Team ID 없음은 0.16.3 당시 증거이며 현재 배포 앱의 상태가 아니다. 실제 필터 로딩·프로필 적용·해제는 서명 이후 별도 실기 확인이 남는다.

## 사용자 증상

GitHub에서 받은 0.16.3(6)을 `/Applications/launch at Login/Tile Launcher.app`에 넣고 실행했다. 시스템 설정의 Focus 앱 필터에 아이콘이 없고, 필터를 선택하면 로딩 후 **Could not load Focus Filter**가 표시됐다.

## 확인한 사실

- 해당 Applications 경로의 프로세스가 실행 중이며 번들 ID는 `dev.cola16.TileLauncher`, 버전은 0.16.3(6)이다. 코드 서명 무결성 검사는 통과한다.
- 서명 종류는 `Signature=adhoc`, `TeamIdentifier=not set`이다. 사용 가능한 코드 서명 identity는 0개였다. 인증서/개인 키를 생성하거나 권한을 변경하지 않았다.
- 앱의 Info.plist가 AppIcon을 가리키고 ICNS가 있다. `NSWorkspace.urlForApplication(withBundleIdentifier:)`도 위 설치 경로를 반환한다. 같은 경로에 `NSWorkspace.icon(forFile:)`를 호출하면 유효한 아이콘(32개 표현)이 반환됐으며 최종 계단/분리 타일 모양을 PNG로 직접 확인했다. 호스트 창이나 Finder를 열지 않았다.
- LauncherFocusIntent/ProfileEntity/ProfileQuery 메타데이터가 존재하고 `com.apple.link.systemProtocol.FocusConfiguration`으로 추출돼 있다. linkd가 새 Applications 경로의 extract.actionsdata를 읽고 등록하는 로그도 있다.
- 설치 앱 시작 시 App Intents가 `LauncherFocusIntent matching LauncherFocusIntent registered with AppManager`를 기록했다. 따라서 메타데이터 파일 부재나 Swift 타입을 전혀 찾지 못한 상태는 아니다.
- 14:02–14:04의 linkd 로그에 다음 오류가 반복됐다.

```text
Failed to generate bundleIdentity:
 -Unable to get teamId from dev.cola16.TileLauncher
```

- FocusSettingsExtension이 실행 중인 앱에 연결하려고 한 뒤 약 32초에 다음 오류가 발생했고 한 번 재시도해도 같았다.

```text
linkd openApplicationAndConnect failed:
Error Domain=LinkDaemon.ProcessRegistry.Errors Code=0
Unable to get connection interface
```

- BackgroundShortcutRunner에도 해당 앱의 definition을 읽지 못했다는 오류가 있다. 사용자 스크린샷의 최종 오류와 같은 시점이다.
- Launch Services에는 설치 앱·개발 앱·휴지통의 과거 사본 총 3개가 남아 있지만, 현재 canonical 경로와 실행 프로세스는 모두 새 설치 앱이다. 이번에는 등록을 지우거나 시스템 캐시를 초기화하지 않았다.

## 판단과 남은 검증

현재 환경에서 **Team ID를 얻지 못해 앱 식별 정보를 만들지 못하는 문제**가 확인됐다. 이어지는 App Intents 연결 시간 초과와 관련된 직접적인 차단점이다. 이 사례를 모든 macOS 버전/모든 ad-hoc 앱에서 동일하다는 보편 규칙으로 확대하지 않는다.

Focus의 빈 아이콘도 앱 definition/identity 조회 실패와 관련됐을 가능성이 있다. 다만 아이콘 누락과 Team ID의 인과관계를 별도 A/B 검사한 것은 아니다. 아이콘 파일 자체와 일반 AppKit 아이콘 로딩은 정상이다. 폴더 위치를 바꾸거나 앱/접근성 권한을 반복 재등록하면 해결된다고 안내하지 않는다.

다음 검증에는 실제 Team ID가 있는 유효한 Apple 서명이 필요하다. 공개 배포에는 준비한 Developer ID Application 경로를 사용한다. 유료 등록 또는 인증서 생성만으로 Focus가 고쳐졌다고 선언하지 않는다. 사용자가 정한 기준대로 Developer ID 서명 완료·검증 첫 버전은 1.0.0이다.

1. 실제 Apple 서명 후 codesign에서 Authority와 TeamIdentifier를 확인한다. Team ID를 plist나 ad-hoc entitlement에 임의로 넣는 방식으로 신원을 대신하지 않는다.
2. 동일 앱의 Focus 필터 로딩/프로필 목록, 추가/켜기/끄기, 실행 중 perform 전달, 재시작 후 current 조회를 검사한다. 기존 프로필·수동 선택·설정은 보존한다.
3. linkd의 Team ID 오류가 사라졌는데도 연결이 실패하면 런타임 등록·메타데이터와 해당 macOS 베타 문제를 별도로 좁힌다. 서명만으로 전체 해결을 보장하지 않는다.
4. Focus 아이콘을 다시 확인한다. 사용자 작업 중 자동 UI 조작으로 검증하지 않는다.

서명 비교가 가능해질 때까지 앱 안의 수동 프로필 선택, 가로 쓸기, Option+A/S/D/F 전환은 기존 방식으로 사용한다. 이번에는 앱 코드/설정/버전을 바꾸거나 새 바이너리를 만들지 않았다.

원시 진단은 저장소 밖 `/tmp/tile-focus-diagnostic.log`, `/tmp/tile-focus-lsregister.txt`, `/tmp/tile-focus-resolved-icon.png`에만 뒀다. 공개 문서에는 이 앱의 필요한 오류만 발췌했다.

관련 공식 자료: [Focus 개요](https://developer.apple.com/documentation/appintents/focus), [Focus 필터 샘플](https://developer.apple.com/documentation/AppIntents/defining-your-app-s-focus-filter). 샘플 구조나 메타데이터 존재 자체는 실제 시스템 연결 검증을 대신하지 않는다.
