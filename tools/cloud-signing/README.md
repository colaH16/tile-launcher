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

## 첫 실통신에서 확인한 서버 준비 항목

2026-10-19 첫 앱 업로드가 실패했다. 동일 Production 서명·컨테이너의 읽기 전용 진단에서 iCloud 계정 사용 가능(accountStatus=1), private DB의 `TileSettings` 질의가 `CKErrorDomain 11: Did not find record type: TileSettings`를 반환했다. 서명/계정 연결과 별개로 운영 schema가 없었다.

CloudKit Console에서 Development에 `TileSettings`를 만들고 `payload`를 **Bytes**로 추가했다. 현재 앱은 `CKRecord["payload"] = Data`를 사용하므로 Encrypted Bytes나 Asset이 아니다. 앱의 CKSyncEngine은 record query를 사용하지 않아 인덱스를 추가하지 않는다. 공개 DB를 사용하지 않으므로 Console이 자동 추가한 해당 타입의 `_world` 읽기와 `_icloud` 생성 권한을 해제했다. 기존 Users 타입/권한은 변경하지 않았다. Private DB는 기본 소유자 읽기·쓰기를 사용한다.

운영 배포 버튼은 자동 승인 검토에서 되돌릴 수 없는 Production 변경의 명시 승인이 부족하다고 차단돼 사용자 확인을 요청했다. 사용자가 **‘허용 · Production 스키마 배포’**로 승인한 뒤 배포했고, Console의 `Schema promoted to production` 알림을 확인했다. 변경 목록과 스크린샷은 ignored evidence에 보존한다. 반영 후 기존 진단 query는 타입 미존재 대신 인덱스 없음 오류를 반환했다. 이는 앱에서 사용하지 않는 질의용 인덱스 문제이므로 추가하지 않았다.

기존 앱의 ‘지금 동기화’가 거부 기록의 보존된 전송 대기를 다시 등록하므로 재빌드 없이 회복했다. 앱의 native 조작 연결이 응답하지 않아 사용자가 버튼을 한 번 실행했고 빨간 오류 해제와 최신 설정 반영 화면을 확인했다. 실행 전 알려진 설정4개의 서버 메타데이터 조회는0/4였고, 실행 후 동일 조회는 **4/4 성공**했다. 설정 필드값은 요청하지 않았으며, 이 Mac의 실제 업로드 회복은 확인됐지만 전체 값의 정확성·두 Mac 간 병합·백그라운드 수신 검증은 별도다.

근거: [Apple의 schema 배포 절차](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema), [private DB와 public DB 권한 구분](https://developer.apple.com/icloud/cloudkit/designing/). 운영에 배포한 타입/필드 삭제·형식 변경은 불가능하므로 배포 전에 현재 코드의 이름/형식을 대조한다.
