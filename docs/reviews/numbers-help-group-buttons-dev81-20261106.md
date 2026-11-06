# Numbers Help 클릭 · dev81 Group/Button 분석 (R377, 2026-11-06)

사용자가 현재 집 Mac에서 직접 시험했다고 정정했다. 앞선 회사 Mac 가정과 파일 첨부 대기는 철회하고 이 Mac의 새 dev81 로그를 직접 확보했다. 현재 범위는 읽기 전용 분석·수정 방안 공동 검토이며 코드/앱/배포 변경은 없다.

## 실제 증거

- 설치 2.1.11(81), source a2d5095b2d3adb200fae56ec00ea27039b941885.
- 설치 실행파일 SHA256 5752946beed48f6da00a4619e7612fc16bbf87a90029cbb7f75a4f0a2f69da40: 공증 게시본과 동일.
- PID4615의 실제 실행 인자에 --menu-capture-log / --menu-capture-structure 모두 있음.
- 새 로그 XFCSlt의 사본 13,062bytes / 40 JSONL records.
- SHA256 43e967ca82462997946c583ad3f7012c4e89325954b1b4afa89b8c2571351cde.
- 생성 2026-11-06 20:27:01 KST, 실패 이벤트는 새실행24.126초 뒤로 기록기간 안이다. 이전 dev80/78 로그와 분리했다.
- Numbers/Export TSV는 사용자 보고다. 로그에 앱/메뉴 이름·문서 내용은 없으며 root7을 특정 메뉴 이름이나 버튼 기능으로 해석하지 않는다.

| 기록 | 결과 |
| --- | --- |
| 17 / 19 | rowAccepted / rowHeld |
| 21 | sealed, request1 / generation7 |
| 29 | started, request age526ms |
| 31 | incomplete / roleReadFailure / unsupportedKnownRole / group |
| catalog | 54ms,500노드,request age610ms(추가진단 포함) |
| 실패 위치 | parent menu, 실제depth4,rootIndex7,siblingIndex5(0기준6번째),siblingCount9 |
| structure | 30ms, overall/subtree/sibling 모두 complete |

관측 가지는 `AXMenu → AXGroup → AXGroup → AXButton 7개`다. 두 Group은 자식1/7개이며 모든 Button은 자식 count0을 정상 확인했다. 실패 노드와 하위9노드, 형제8개의 역할을 관측했고 형제는 모두 MenuItem이다. 하위에는 Menu/MenuItem이 없고 형제에는 Menu가 없다. 잘림/오류/취소/시간 초과 없이 관측 범위를 완료한 결과다.

전체 최대depth6/children40은 실패노드의 실제 맥락과 구분한다. leaf/matched/identity0은 불완전 목록의 결과일 뿐 메뉴가 실제로 없다는 의미가 아니다. 54ms는 첫500노드까지 중단된 시간,30ms는 추가 구조 진단 시간으로 전체 메뉴 탐색 성능을 예측하지 않는다.

## 직접 실패 원인

현재 지연 해석기의 역할 허용 목록은 MenuBarItem/MenuItem/Menu뿐이다. 일반 메뉴 사이에 있는 Group에 도달해 목록 전체가 incomplete로 끝났다. 실제 AXRole API 오류·nil·잘못된 값이 아니라 성공 응답의 알려진 Group 역할을 코드가 거부한 것이다. 클릭 행 검증/보관/release 확정은 성공했고2초 마감 문제가 아니다.

dev81은 의도대로 기존 실패 판정을 유지한 진단본이므로 이 결과 자체가 제품 수정 성공은 아니다. 회사 dev79의 별도 childrenReadFailure가 같은 원인이라고 단정하지 않는다.

## 선택한 수정안 — 에이전트 합의, 구현 전

- 전체 현재 메뉴 탐색은 유지한다. 첫 일치만 찾거나 모르는 가지를 통째로 생략하면 실제 메뉴 중복을 놓칠 수 있다.
- 관측된 메뉴 내부 Group을 경로 성분 없는 구조로 허용하고 모든 자식을 기존 한도 안에서 순회하는 안을 검토한다.
- 자식0을 정상 확인한 Button을 기존 AXMenuItem 후보 범위 밖의 제어 요소로 처리하는 안과, 버튼의 이름까지 별도 중복 차단자로 읽는 안을 대조했다.
- 기존 hit는 최종 AXMenuItem을 요구하고 menuPath는 MenuItem/MenuBarItem만 이름으로 더하며 두 catalog 모두 MenuItem 잎만 후보로 내보낸다. 독립적인 Button을 후보로 확장하는 것은 별도 동작 변경이다.
- Group의 메뉴 문맥 제한, 자식 있는/읽기 불확실한 Button의 실패 유지, 실제 MenuItem의 전체 중복/identifier 검증, 한도/취소 보존을 조건으로 좁힌다. 진단 snapshot을 이후 캡처의 캐시/허용 근거로 사용하지 않고 매 요청의 실제 구조를 확인해야 한다.

실제 기존 Claude 세션과 Codex 독립 리뷰가 아래 조건의 좁은 안에 합의했고 차단 이견은 없다. 새 구현/시험 배포는 사용자 다음 단계 지시 전에는 시작하지 않는다. 추가 사용자 클릭·파일 업로드·인증은 필요 없다. 원본 사본/영수증/실제 Claude 응답은 ignored evidence의 r377-home-dev81에 보존한다.

## 최종 규칙과 선택 이유

1. Group은 부모가 검증된 Menu이거나 이미 허용한 Group일 때만 구조로 허용한다. 이름을 경로에 더하거나 제목을 읽지 않고 모든 자식을 정상 전역 탐색에 포함한다. root/메뉴 막대 항목 직하/메뉴 항목 직하 Group은 이번 근거 범위를 넘어 계속 실패로 둔다.
2. Button은 허용 Group 안에서만, 자식 count가0으로 정상 확인된 때만 비후보로 인정한다. 자식이 있거나 unsupported/noValue/오류·반환 형식 불일치면 incomplete다. 버튼 제목·설명·값·액션은 조회하지 않는다.
3. 실제 MenuItem이 Group 안에 있으면 경로를 보존해 끝까지 수집하고 기존 중복·literal ` > `·identifier 충돌 검증에 포함한다. 다른 미지 역할이나 불완전한 가지는 계속 전체 결과를 incomplete로 만든다.
4. 한 번의 현재 메뉴 탐색을 사용하고 기존2초/3000노드/100자식/12깊이/25ms IPC 설정과 호출 전후 취소·마감, 현재 설정·suppression·저장 직전 검사를 유지한다. 요청별 진단 후 재탐색/캐시/재시도를 추가하지 않는다. 각 요청의 실제 count0을 확인하며 이번 진단 결과를 재사용해 허용하지 않는다.

버튼의 이름까지 차단 후보로 추가하자는 대안은 실제 후보 계약을 대조한 뒤 채택하지 않았다. 기존 hit는 최종 MenuItem, 두 catalog는 MenuItem 잎만 대상으로 한다. 자식0인 독립 Button은 유효 후보가 아니고 그 아래에 MenuItem도 없다는 증거가 있으므로 기존 후보 영역의 유일성을 보존한다. 모든 실행 가능한 접근성 요소로 수집 범위를 넓히는 별도 기능은 이번 수정이 아니다. 사용자 Help 결과가 비MenuItem 요소인 경우의 해석 한계는 기존 후보 범위의 한계이며 이번 설계로 새 범위를 보장하지 않는다.

처음부터 후보가 발견된 곳만 읽거나 모르는 하위 가지를 통째로 무시하면 실제 MenuItem 중복을 숨길 수 있다. 모든 SDK 역할을 container로 허용하는 안은 관측 근거보다 넓다. 사전 캐시나 시간 확대는 이번 역할 거부를 해결하지 못하고 비용·수명 문제를 더하므로 선택하지 않았다.

## 구현 후 필요한 검증 (아직 실행 전)

- 관측된 Menu→Group→Group→자식0 Button7개와 뒤쪽 TSV MenuItem을 포함한 전체 탐색.
- Group 안의 실제 Menu/MenuItem, 다른 위치의 같은 이름 MenuItem, literal경로·identifier 충돌을 누락하지 않는지.
- Button과 MenuItem 이름이 같아도 Button이 기존 후보 영역 밖이라는 규칙, 서로 다른 MenuItem 두개는 여전히 모호한지. 실제 Button title provider는 호출하지 않는지.
- Group 위치 제한, Group/Button의 자식 오류·미지원·형식 불일치/자식 있는 Button, 다른 role은 incomplete인지.
- 모든 허용 구조가 깊이/개수/시간/취소 한도에 포함되고 API 후 경계를 넘은 성공 응답도 거부하는지.
- 실제 native 역할 매핑과 ON 진단 helper가 같은 새 정책을 적용하고 기존 메뉴 클릭·Enter·Option 동작을 보존하는지.

부분 탐색54ms나 추가 진단30ms에서 전체 탐색 시간을 계산하지 않는다. 500번째 뒤에 다른 실패가 있는지, 전체 목록이 한도 안에 완료되는지, TSV label이 유일하게 해석되는지는 구현 후 실기로 확인해야 한다. 다른 Mac의 dev79 children 오류도 이번 결과만으로 해결했다고 보지 않는다.

현재 대기 대상은 사용자의 다음 수정 구현/시험dev 진행 지시다. 추가 재현·첨부·인증이 필요한 상태가 아니며 실제 Claude나 서브에이전트가 제품 코드를 작성 중이지 않다.
