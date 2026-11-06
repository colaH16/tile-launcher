# R367 · 회사 Numbers dev79 로그 분석

2026-11-06, Asia/Seoul. 사용자가 회사 MacBook의 진단 로그를 첨부했고, Numbers에서 성공하면 다른 앱도 시험하려 했지만 Numbers에서 실패해 모든 비교를 Numbers에서만 했다고 확인했다. 이번 단계는 읽기 전용 분석이다. 제품·버전·빌드/설치·공개 변경은 없다.

## 자료와 범위

첨부 파일은22,756bytes(22.22KiB), 유효 JSON75기록, ordinal1–75, 마지막 상대시각39,472ms다. SHA256 f146f1b821da53879e5169f5f6cfcf91200c4b4664391abbdf5b70122ee29499. 원본은 수정하지 않았고 같은 해시의 사본과 실제 Claude 응답을 공개 제외 evidence에 보존했다. 200기록/10분/1MiB 한도에는 도달하지 않았지만 비동기 pending 누락 가능성을 완전히 배제하지 않는다. 아래 판단은 실제 성공/실패 기록에 근거한다.

로그에 앱 이름/명령 제목은 없다. 모두 Numbers였다는 사실은 사용자 확인이고, 실제 company 앱 bundle/build는 별도 조회하지 않았다. dev79에 도입한 deferred 경로가 실행된 것은 로그로 확인된다.

## 관측한 흐름

| 동작 | 근거 | 결과 |
| --- | --- | --- |
| Help 검색 결과 클릭 | #17–22, seq5/6, generation5 | 입력 큐 나이2ms, strict rowAccepted, hit5ms, rowHeld, 실제 release sealed |
| 선택 후 별도 조회 | #30–32 | 봉인588ms 뒤 시작, 조회109ms 뒤 childrenReadFailure, 요청 전체 나이698ms, generation 변경 없음 |
| Enter | #46–49, generation9 | gate accepted → queued → recorded |
| 일반 메뉴 클릭 | #64–72, generation9 | mouseUp gate accepted → queued → recorded |

클릭 처리에서 전체 catalog를 실행하던 경로는 빠져 있고 행 보관/물리 확정/별도 조회 시작까지 작동했다. 이번 첫 실패는 완전 탐색 중 generic readFailure(children)다. 2초 마감·취소·노드/깊이 한도·행 parser 거절·저장 gate 거절이 이번 최초 실패라는 기록은 없다.

nodeCount43/depth4/childCount28은 중단 시점 통계다. childCount28은 성공해 traversal에 전달된 배열의 최대 크기이며 실패 노드의 개수나 상한을 뜻하지 않는다. leafCount0/matchedCount0도 incomplete 결과에서 부분 목록을 숨긴 기본값이므로 실제 메뉴가 없다는 뜻이 아니다.

588ms 시작 지연은 one-shot settle 타이머가 observation 큐에서 늦게 처리됐는지, 닫힘 조건이 먼저 충족됐는지 이 로그로 구분되지 않는다. 이번 childrenReadFailure가 698ms에 발생한 것을 2초 만료로 해석하지 않는다. 109ms는43노드 조기 실패 시간이며 전체 탐색 완료 성능이 아니다. 집 Mac의 이전372ms와 회사 Mac109ms를 전체 성능 향상으로 비교하지 않는다.

## 아직 한 이름으로 묶인 실패

현재 MenuHelpDeferredResolver.elements의 같은 failure 반환은 아래를 포함한다.

1. GetAttributeValueCount의 지원 부재 외 AX 오류 또는 음수 count.
2. CopyAttributeValues의 AX 오류.
3. 반환 nil/배열 변환 실패.
4. requestedCount와 returnedCount 불일치.
5. 반환 원소의 CF 타입이 AXUIElement가 아님.

noValue는 childrenUnavailable이고 명시적 attributeUnsupported는 알려진 AXMenuItem에 한해 leaf로 정규화하므로 이번 childrenReadFailure와 다르다. deadline/cancel은 generic read 직후 checkpoint에서 별도 실패로 전환되므로 이번 이유의 주된 설명이 아니다.

새 exact-count/원소 타입 검사가 이전 reader보다 엄격한 것은 사실이지만 그 조건이 이번 실패인지 알 수 없다. 이전 catalog는 자식 읽기 실패를 만난 뒤에도 형제를 계속 탐색했고 예전 로그의 IPC5건도 API별로 나뉘지 않았으므로 같은 오류가 이미 있었을 수 있다. 특정 시스템 메뉴나 Services 하위라고 확정하지 않는다. 앞선 배열들이 통과해 전반적인 CF bridging 불능도 근거가 없다.

## 공동 결론과 다음 제안

실제 기존 Claude 세션과 Codex 독립 읽기 리뷰 모두 위 증거와 불확실성에 동의했다. 먼저 기존 read 결과만으로 실패 분기·API별 AXError 코드·reported/requested/returned 개수·배열/원소 타입 실패를 분리하는 최소 진단을 권한다. 새 AX probe나 제목/문서/원시값 수집 없이 typed enum/정수로 기록할 수 있다. 실패 위치의 깊이/순서와 필요시 one-shot settle 처리 시각도 수치로 나눌 수 있다.

개수 읽기와 배열 읽기 사이의 변화가 확인되면 한 번의 AXChildren 값 읽기를 검토할 수 있다. 그 경우 전체 배열을 한 번 받는 비용과 개수/타입/완전성 검사를 같이 검토해야 한다. 현재는 그 분기가 관측되지 않았으므로 수정안으로 확정하지 않는다. 오류 노드를 건너뛰거나 부분 목록으로 유일성을 추정하는 안, 시간만 늘리거나 무조건 재시도하는 안은 선택할 증거가 없다.

분석은 완료했고 다음 세부 진단 구현/dev 전달은 사용자 진행 지시를 기다린다. 현재 추가 재현·다른 앱 시험·인증을 요청하지 않는다. Claude/서브에이전트가 코드 구현 중인 상태가 아니다.
