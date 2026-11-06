# R365 · Help 클릭 선택 후 지연 메뉴 해석

2026-11-06, Asia/Seoul. 사용자가 원인 분석에 동의하고 수정 구현과 Homebrew dev 시험 배포를 승인했다. 이번 범위는 수정·검증·서명/공증·dev 게시까지이며 정식2.1.10과 이 Mac 실행 중 앱·설정은 유지한다. 다음 dev 버전은2.1.11(79)이다. 실제 여러 앱 시험은 사용자 후속 확인 전까지 미확정이다.

## 구현 분담과 기준

실제 기존 Claude 세션이 MenuUsageMonitor와 native resolver/제한 진단을 작성하고, Codex 서브에이전트가 순수 완전 탐색(MenuCatalogTraversal)과 확정 요청 수명(MenuDeferredCapture)/각 검사를 작성했다. 서로 상대의 코드를 읽기 검토하고 루트가 격리 검증·빌드·배포를 수행한다. 같은 파일을 두 작성자가 동시에 수정하지 않는다.

행 label/frame 검증과 물리적 선택 확정을 입력 경로에서 처리하고, 무거운 실제 메뉴 조회를 분리한다. 정상 메뉴 닫힘이 선택을 지우지 않도록 미확정 행과 확정 요청 수명을 분리한다. 요청의 취소/앱 전환·프로세스 시작 시간·세대·만료·정책·suppression과 중복 완료를 검증한다. 부분 catalog의 유일성 추정이나 오래된 selected leaf 우회는 사용하지 않는다.

## 현재 검증

- 격리 snapshot에서 새 순수 검사16개(탐색8·수명8) 컴파일/실행 성공, 실패0.
- 이 검사는 native 코드의 동시성 보호나 Numbers 실제 성공을 대신하지 않는다. native 통합·최종 회귀 검증은 아직 진행 중이다.
- 기존 공증 프로필 이력 조회와 GitHub CLI 읽기 연결이 정상이다. 인증 재등록/브라우저/화면 공유를 요청하지 않았다.

## 교차 검토에서 확인할 경계

조회 완료 후 observation→main 저장까지 만료·취소·앱/프로세스와 새 메뉴 입력을 다시 확인해야 한다. 테스트한 순수 정책을 실제 경로에 연결하고 정상 close와 cancel을 구분한다. 필수 role/title/children 실패를 조용히 건너뛰어 complete로 만들지 않는다. 일치하는 동일 경로의 모든 identifier를 확인하고, 잘못된 타입을 단순 nil로 치환하지 않는다. metadata 조회 후에도 전체 deadline을 확인한다.

## 최종 구현 검증 완료 · dev 빌드 준비

- 진단 ON 전체 Swift346개, OFF338개, Python30개 실패0. ON/OFF actual ledger/cancel 검사와 Option/native 메뉴 진단·인자 누락 exit2가 통과했다.
- actual ledger의 최종 checks가 끝난 뒤 lock 안에서 시각을 샘플링해 take한다. 검사 중 만료되는 fixture, 정상 닫힘·취소/교체·중복/동시 완료·잘못된 자식 부재 해석의 native 검사가 통과했다. 실행 중 앱·AX·문서에는 테스트 입력을 보내지 않았다.
- Release OFF에서 메뉴 진단/새 validator/기존 일반 debug flag·validator 문자열이 제거됐다. 검증211입력과 현재 소스의 SHA256이 모두 일치한다.
- 실제 Claude 두 구현 응답·최종 읽기 리뷰와 Codex 독립 두 리뷰를 대조했다. 최종 만료 시각 보완을 Claude가 수용했고 남은 차단 이견은 없다. child noValue 경계를 추가로 좁혔다.
- [Apple AXChildren 문서](https://developer.apple.com/documentation/applicationservices/kaxchildrenattribute)와 설치 SDK의 하위 요소에 필요한 속성 계약을 확인했다. 알려진 AXMenuItem의 명시적 attributeUnsupported만 현재 노출된 AX tree의 leaf로 정규화하며, noValue/IPC 오류/타입·배열 개수 오류는 incomplete다. 미래에 lazy 생성될 메뉴까지 완전성을 보장하지 않는다.
- 조회는 별도 큐의 한 in-flight/최신 pending1개, 요청별1시도·기한2초·3000노드/자식100/깊이12·개별 메시지25ms 한도다. 3000은 실제 Numbers 규모의 측정값이 아닌 새 off-input 작업의 유한 상한이다. 이미 시작된 IPC 즉시 중단이나 원자적 AX snapshot은 보장하지 않는다.
- 일치한 모든 후보의 identifier를 확인하고 대표 shortcut만 읽는다. 정상 메뉴 close·선택 후 dialog Esc/무관 입력은 확정 요청을 유지한다. 새로운 메뉴 선택·실제 앱/프로세스/설정 전환·stop·suppression은 무효화한다.

실제 여러 앱의 클릭→완전 조회→저장 성공, 지연 메뉴/커스텀뷰/선택 후 앱 전환 명령은 사용자 dev 실기로 확인한다. 정식 배포는 하지 않는다. 지금은 새 공증 dev 게시 진행 중이며 공증/공개 자산 영수증은 완료 뒤 갱신한다.
