# CloudKit 배포 권한 준비안

현재 공개 앱과 설치본은 변경하지 않았다. 사용자는 기존 App ID의 CloudKit/푸시 활성화와 지정 컨테이너/Developer ID 프로파일 생성·갱신을 승인했다. 2026-10-19 Xcode 재로그인 후 CLI의 Apple 계정 연결을 확인했고, 자동 Developer ID export로 실제 CloudKit/production 푸시 프로파일을 받아 2.0.0(58) 별도 사본의 서명·ZIP 재추출 검증까지 완료했다. 팀·앱·컨테이너·기존 인증서가 일치한다. 원래 ad-hoc 준비본은 보존했고 설치·실행·공증·공개는 하지 않았다.

- 기존 App ID: `dev.cola16.TileLauncher`, Team: `VV2W9U5XT3`
- 사용할 개인 CloudKit 컨테이너: `iCloud.dev.cola16.TileLauncher`
- 필요한 서비스: CloudKit, Apple Push Notifications
- 필요한 배포 자산: 이 서비스가 포함된 Developer ID provisioning profile
- 제안 entitlement: `Cloud.entitlements`

Xcode의 자동 프로비저닝은 Apple Developer 계정의 앱 서비스와 서명 자산을 생성/갱신할 수 있다. 사용자 명시 승인 뒤에만 `xcodebuild -allowProvisioningUpdates`로 준비한다. 승인 전 계정·컨테이너·프로파일을 변경하지 않는다. 앱을 설치하거나 실행하는 과정과는 별개다. `release/entitlements.plist`는 기존 AppleEvents 기본 권한을 유지한다. `scripts/release.py sign --cloud-profile <Developer ID profile>`은 프로파일의 팀/App ID/컨테이너/production 환경/인증서/만료·디버그 권한을 검사하고, 프로파일을 `Contents/embedded.provisionprofile`에 넣으며 필요한 서명 권한을 함께 생성한다. 2.0 이상의 Developer ID 서명은 일치하는 프로파일 없이는 진행하지 않는다. `Cloud.entitlements`는 서비스 네 가지를 표시한 참조용이며, 이를 그대로 서명에 쓰는 대신 프로파일에서 앱·팀 식별 권한까지 검증한다.

실제 프로파일의 서비스 허용값은 배열 대신 scalar `*`였으므로 배포 검증기는 iCloud 서비스 키에 한해서 이 형식을 허용한다. 서명되는 앱의 서비스는 명시적인 `['CloudKit']`으로 제한하고 container ID 등 다른 키에는 이 예외를 적용하지 않는다. Python 배포 검사30개와 실제 프로파일 검증이 통과했다.

서명 검증은 CloudKit 실통신 검증이 아니다. development 스키마 생성 및 production 배포, 두 Mac의 비활성 앱에서 알림에 따른 fetch/UI 반영, 오프라인 병합/계정 변경 대기는 정식 공개 전에 별도 확인한다. 실제 프로파일과 로그·산출물의 운영 경로는 ignored evidence에 보존한다.
