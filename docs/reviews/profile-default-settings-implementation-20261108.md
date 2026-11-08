# R390–R391 프로필 기본값·편집 UI 구현

기준일: 2026-11-08 (Asia/Seoul). 코드 구현·집중 native 검증을 완료하고 전체 격리 matrix 검증을 준비한다. 실제 사용자 앱·설정·배포를 변경하지 않았다. canonical cdf17e95를 기반으로 별도 R390 clean source에서 작업한다. R389 회사 오마 자동 선택의 실제 원인은 미확정이다.

## 사용자 요청과 이번 정책

- 설정에 기본값 지정 버튼을 추가한다.
- 빈 프로필 추가/현재 구성 복제 버튼을 누른 뒤에만 이름을 입력한다.
- 저장된 기본값 프로필을 새 Focus 필터 후보에서 제외하고 이미 남은 연결도 앱 최종 적용 시 제한한다. 기존 OS 연결을 자동 삭제한다고 약속하지 않는다.
- 기본값 역할과 현재 수동 선택은 별개다. 필터 없는 자동 선택 구간의 지정 기본 복귀는 이번 새 요청에 따른 정책 변경이며 진단84의 ‘정책 변경 없음’과 구분한다.

OS의 raw Focus ID는 기본 역할 경계에서 nil로 지우지 않는다. RAM에서만 관측 값을 유지하고 저장·로그에는 넣지 않는다. 실제 선택·아이콘 미리 읽기·진단 상태 해석은 공통 ProfileSelection eligibility를 따른다. 따라서 기본 역할을 오마에서 기본 구성으로 되돌리면 새 OS 조회 없이 기존 Work→오마 관측을 다시 평가할 수 있다. perform/current 값을 nil로 정규화하는 이전 설계는 사용하지 않는다.

## UI와 편집 상태

실제 Claude 기존 세션을 사용자 context 인증으로 재사용했다. 파일 도구만으로 SettingsView/ProfileNameSheet를 작성했고 명령·앱·배포 도구는 제공하지 않았다. Codex는 SettingsEditingSession과 실제 UI native 검증을 맡았다. 모델/Core와 Focus API 담당은 별도 파일 소유로 협업했다.

창 로컬 editorProfileID는 등록 탭의 편집 대상이며 default/manual/follow 역할과 dirty/persistence에서 제외한다. 초기 활성 프로필에서 시작하되 Focus 변경으로 편집 중 목록이 이동하지 않는다. 대상이 삭제되면 유효한 기본값 프로필로 보정한다.

Picker뿐 아니라 등록 목록·삭제·드래그/버튼 순서·여는 방식·앱/폴더/다운로드/휴지통 추가·Dock 시작/미리보기/적용/메시지/되돌리기를 동일한 명시적 profileID로 연결했다. Dock 비동기 작업은 시작 때의 대상을 보관한다.

‘기본값으로 설정’은 선택한 편집 프로필의 draft.defaultProfileID만 바꾸고 이미 기본값이면 비활성이다. 프로필 목록의 기본값 표시와 현재 기본값 삭제/마지막 한 개 삭제 보호를 제공한다. 변경은 등록 탭 저장 전에는 실제 설정·Focus 후보·오버레이에 반영하지 않는다.

## 이름 입력과 모달

추가/복제 버튼은 이름 시트를 연다. 입력 FocusState, Enter 확인, Esc 취소, 앞뒤 공백 제거와 공백 이름 확인 비활성을 사용한다. 취소는0변경이고 확인은 draft에 새 프로필을 만든 뒤 editorProfileID만 새 ID로 바꾼다. manual/default/follow 역할은 바꾸지 않는다.

복제 요청은 버튼을 누른 시점의 편집 ID·이름·items 값을 불변 요청으로 보관한다. 시트가 열린 뒤 Focus나 원본 목록이 변해도 다른 구성을 복사하지 않는다. Dock 확인과 이름 입력은 단일 sheet 모델로 표시하고 동시 진입을 막는다.

## Save/Cancel과 확인한 기존 결함

등록 탭의 저장/변경 취소와 다른 탭으로 이동할 때 미저장 보존을 유지한다. 다른 탭 저장은 등록 편집을 반영하지 않는다. 등록 Draft의 rebase에는 profiles/default/manual/follow만 포함하며 editorProfileID는 포함하지 않는다.

기존 registeredPane(settings:)에서 `$settings.followFocus`는 draft 매개변수의 투영값이 아니라 struct의 실제 @ObservedObject 저장소를 가리켰다. 이 토글이 등록 탭 저장을 거치지 않던 결함을 확인했다. 생산 Toggle은 이제 editor.followFocusBinding을 사용한다. 같은 Binding을 native 검사에서 직접 조작해 draft만 바뀌고 실제 저장소/UserDefaults는 저장 전 불변, Cancel 폐기, Save 반영을 확인한다. 실제 키/마우스·전역 접근성 입력을 보냈다고 주장하지 않는다. 이 결함을 R389 오버레이 자동 선택 원인으로 단정하지 않는다.

## 현재 검증 범위

- 모델 담당의 Core 집중5검사와 정책 native, 독립 Focus native는 통과 보고를 받았다.
- 최종 집중 UI native는 editor 격리·생산 Toggle Binding·Save/Cancel·탭 보존·빈 이름/취소·clone snapshot·역할 기반 삭제 보호·명시적 Dock 적용/되돌리기에서 exit0이다. 탭 보존은 같은 session/navigation 상태 조작으로 확인했으며 실제 UI 키 입력 전송 검사로 확대하지 않는다.
- SettingsView가 실제 사용하는 RegisteredProfileSettingsPane과 SettingsEditorPane footer/이름 창/Dock 확인 창을 offscreen NSHostingView로 출력했다. 투명 배경과 TabView 선택 탭 캡처 문제는 실제 pane 공유·windowBackground/colorScheme·같은 outer padding으로 해결했다. 전체 TabView 표시/실제 물리 입력의 검증은 아니다.
- 기본 폭580·최소 폭540에서 일반/긴 가짜 이름을660높이로 출력했다. outer16+pane16을 양쪽 적용해 GroupBox 전 가용 폭516/476을 확인했다. 기본 badge·버튼·footer가 잘리지 않고 긴 이름은 native popup 말줄임으로 표시된다. 설명 두 Text는 vertical fixedSize로 끝까지 줄바꿈한다. 총12PNG를 직접 확인했고 독립 리뷰도8개 기본 렌더를 확인했다.
- 합성 전용 UserDefaults와 가짜 등록 항목만 사용한다. 실제 OS Focus 조회·Dock 읽기·권한 변경·실행 앱·사용자 설정·A11y 전역 입력은 사용하지 않는다.
- 실제 Claude 읽기 교차 리뷰와 Codex 독립 UI 리뷰는 차단점 없음이다. 모든 소유자의 코드 동결 뒤 전체 matrix 검증은 root가 진행한다.

## 남은 단계와 보존

최종 집중 UI 근거는 `/private/tmp/tile-launcher-r390-ui-native-20261108-minwidth-final/`의 native.log(exit0), receipt.json과 rendered12PNG다. 초기 캡처는 보존하고 최종 결과와 구분한다. 전체 격리 회귀는 아직 실행 전이며 결과를 외부 영수증으로 연결한다. 버전/config/릴리스 노트·서명·공증·Homebrew·원격 main/태그·설치 앱은 이번에 변경하지 않는다. 별도 사용자 시험 배포본은 다음 작업이며 현재 새 빌드/배포가 진행 중이라고 안내하지 않는다. 기존 R389 재검토와 원본 증거는 유지한다.
