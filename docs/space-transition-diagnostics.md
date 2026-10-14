# 다른 데스크탑 창이 겹쳐 보이는 현상

2026-10-14 · R165 · 코드 원인 후보 확인 및 안전한 경로로 교체

## 사용자 보고와 확인된 사실

- 사용자는1.3.0을 별도 Mac에서 시험하다 다른 데스크탑 창을 누르면 애니메이션 없이 바뀌고 이전 데스크탑 창이 남아 두 데스크탑이 함께 보인다고 보고했다. macOS 베타 문제일 수 있다고 했으며 재현되지 않으면 다음에 영상을 제공할 수 있다고 했다.
- 기존 DesktopWindows.revealDesktop은 CGSManagedDisplaySetCurrentSpace를 호출했다. 이 함수의 반환 형태는 void이며 호출 이후 전환 성공을 확인하지 않고0.18초 뒤 창을 올렸다.
- [SpacesManager의 작성자 확인 기록](https://github.com/michaeltorbert/spaces-manager#tahoe-private-api-findings)은 macOS26.3.1에서 이 함수가 Dock의 정상 전환 없이 대상 Space 창을 기존 데스크탑 위에 드러낸다고 설명한다. 현재 코드의 호출과 사용자 증상이 일치하므로 유력한 원인 후보로 판단했다. 이는 이 Mac에서 직접 재현한 증거가 아니다.
- [Apple의 앱 활성화 옵션 문서](https://developer.apple.com/documentation/appkit/nsapplication/activationoptions/activateallwindows)는 기본 활성화와 모든 창 올리기를 구별한다. 이번 수정은 모든 창 활성화 옵션이나 창의 Space 이동을 사용하지 않는다.

## 1.4.0 변경

- 직접 current Space 값을 쓰는 함수 포인터/심벌 조회/호출 경로를 제거했다. 기존 Space 읽기 API는 크기 판정과 상태 확인용으로만 남겼다. SLSShowSpaces/HideSpaces 같은 추가 쓰기 API로 우회하지 않는다.
- 가능한 경우 선택한 AX 창을 main/raise 대상으로 먼저 지정하고 NSRunningApplication.activate(options: [])를 요청한다. macOS에 전환 조정을 맡기고 잠시 후 같은 창을 다시 올린다.
- 앱 전면 상태, 정확한 대상 AXFocusedWindow, 확인 가능한 Space 상태를 최대8회 확인한다. 다른 창이 포커스됐거나 대상이 여전히 다른 Space이면 성공을 선언하지 않는다. 닫힌 창·시간 초과는 기존 오류 경로로 알린다.
- 새 창 선택은 이전 요청을 취소해 늦은 재시도/오류가 사용자의 다음 선택을 방해하지 않게 한다. AX가 없는 냉시작 창은 해당 앱을 한 번 활성화한 후 선택한 창 ID만 재조회한다. 해당 앱이 정보를 제공하지 않으면 수동으로 그 데스크탑을 확인하도록 안내한다.

## 검증 경계와 후속 확인

- 앱/창 포커스 판정, 닫힘·시간 초과·알 수 없는 Space의 fallback을 단위 검사한다. 비공개 Space 쓰기 심벌이 실행 코드에 남지 않는지도 확인한다.
- 사용자의 작업 창을 다른 Space로 옮기거나, 재현을 위해 문제 함수로 WindowServer 상태를 강제 변경하지 않았다. 데스크탑 겹침의 로컬 실기 재현은 미완료다.
- 사용자의 별도 Mac에서 정상 데스크탑 이동 후 다른 앱/같은 앱의 다른 Space 창/최소화/전체 화면 창을 확인한다. 애니메이션 유무만으로 성공을 판단하지 않으며 이전 Space의 창이 사라지고 선택한 창이 실제로 포커스되는지가 기준이다.
- macOS의 동작 줄이기·Mission Control 앱 전환 설정, 앱별 AX 지원, OS 버전에 따라 동작이 다를 수 있다. 시스템 설정을 자동 변경하거나 Dock을 재시작하지 않는다. 여전히 겹치면 영상과 당시 앱/OS 조건으로 이어서 확인한다.
