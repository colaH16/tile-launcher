# 앱 실행 대기와 중복 요청 방지 · 1.4.0(24)

R167에서 요청한 Dock과 비슷한 대기를 앱 실행 상태로 판단한다. Dock의 튀는 애니메이션 자체를 읽거나 앱 안의 문서/네트워크 로딩 완료를 보장하지 않는다.

- 같은 앱 URL을 정규화해 등록 앱/창 없는 앱 타일/숫자 요청을 함께 차단한다. 다른 앱·창·오버레이 닫기는 가능하다.
- 요청 후3초 안에 프로세스가 없으면 대기를 해제한다. NSWorkspace의 실행 결과와 runningApplications 목록을 같이 본다. 새 프로세스의 bundle ID 대조는 translocation 보완용이며 이전 PID 목록과 구별한다.
- 시작이 확인되면 isFinishedLaunching까지 유지한다. 실행 오류/종료는 즉시, 완료 알림이 없는 앱은 시작 확인 후60초에 해제한다. 지연된 이전 콜백이 재시도 상태를 해제하지 못하게 요청 ID로 구별한다.
- 목록/앱 KVO와0.2초 타이머는 요청이 있는 동안만 유지하고 끝나면 해제한다. UI 업데이트는 메인 큐에서 수행한다. 오버레이 재열기로 요청 상태를 지우지 않는다.
- 기존 앱 선택은 이미 완료된 상태라 대기 없이 활성화된다. 메뉴 실행/개별 창 포커스까지 전체 잠금을 확대하지 않는다.

근거: Apple의 [isFinishedLaunching](https://developer.apple.com/documentation/appkit/nsrunningapplication/isfinishedlaunching), [willLaunchApplicationNotification](https://developer.apple.com/documentation/appkit/nsworkspace/willlaunchapplicationnotification). 로컬 Xcode SDK의 NSRunningApplication.h는 일부 앱이 완료 알림을 내지 않을 수 있음을 명시한다. willLaunch는 background/LSUIElement 앱에 오지 않을 수 있어 runningApplications KVO를 사용한다.

검증은 실행 정책 단위 테스트와 네이티브 모니터의 가짜 opener/시계 테스트로 나눈다. 후자는 실제 사용자 앱을 실행하지 않고 중복 차단·다른 앱 허용·타임아웃·이전 콜백·오류 재시도·실제 NSRunningApplication.current의 완료 상태 전달을 검사한다. Dock과 사용자 앱 전체의 실사용 성공을 자동 테스트로 단정하지 않는다.
