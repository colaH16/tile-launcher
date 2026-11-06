# R364 · Numbers Help 검색 클릭 진단

2026-11-06, Asia/Seoul. 사용자가 일반 메뉴 클릭 → Help 검색 결과 클릭 → Help 검색 결과 Enter의 세 시험을 완료했다고 보고했다. 현재 단계는 로그 분석과 후속 수정 방향 검토다. 제품 수정·새 빌드·설치·배포는 진행하지 않는다.

## 확인한 입력

- 이 Mac의 실행 인자에서 opt-in 진단 실행을 확인했고, 설치 앱은 2.1.11(78)이다. 실행 파일 SHA256 c9ff7f20b465af52780db4a7dddbe9466d4cb36240299b13b5d179fe39f92382는 공증 dev78과 일치한다.
- 관련 MenuUsageMonitor/MenuCapture/MenuHelpSearchRow/MenuCaptureDiagnostics 소스는 dev 소스 08ca97d7과 바이트 동일하다.
- 원본을 수정하지 않고 완결된 JSONL 기록을 로컬 사본으로 읽었다. 34,206바이트, 107개 기록, ordinal1–107, 마지막 상대시각195,690ms, 미완결 마지막 줄 없음. SHA256 0f073d8f7f12d5ac53c63a6518eff6c5831bee16438809c312bd5f3b8d1c1afc.
- 기록은 200개/10분/1MiB 한도 안이다. 비동기 pending 한도로 누락 가능성 자체를 배제하지는 않는다. 아래 결론은 로그 부재가 아닌 실제 실패/성공 기록에 근거한다.
- 로그에는 명령 제목·검색어가 없으므로 같은 PDF 명령이라는 정보는 사용자 시험 순서에 의존한다. 로그만으로 제목을 독립 확인한 것은 아니다.

## 세 경로 비교

| 사용자 시험 순서 | 기록 | 확인한 결과 |
| --- | --- | --- |
| 일반 메뉴 클릭 | ordinal39–47, input28/29 | 실제 menuItem hit, mouseUp gate accepted, record queued/recorded |
| Help 검색 결과 클릭 | ordinal59–71, input38/39 | 행 구조 인식 rowAccepted, catalog incomplete, resolution unresolved, mouseUp에서는 다른 role로 더 이상 후보를 찾지 못함 |
| Help 결과 Enter | ordinal91–94, input44 | confirm accepted, gate accepted, record queued/recorded |

클릭 경로 상세:

1. ordinal59: mouseDown 입력 큐 나이2ms. 세대와 Help session 변경 없음.
2. ordinal60: Help 행 parser 성공. cellCount1/labelCount1/rowFailure none. 행 구조나 Help 소속 거절이 이 시도의 최초 실패는 아니다. helpActive=false여도 엄격한 행 parser는 통과했다.
3. ordinal61: 전체 메뉴 catalog가372ms 뒤 incomplete. 350ms budget 초과, nodeCount185/depth6/최대 childCount33, ipcFailures5/missingValues25. node/depth/child 개수 한도가 이번 실패 원인이라는 증거는 없다.
4. ordinal62: 후보0/identity0으로 unresolved. catalog nil을 빈 배열로 치환한 뒤 resolveHelp가 빈 배열을 받은 것이다. count0은 중간에 발견한 메뉴가 하나도 없었다는 뜻이 아니다.
5. ordinal63–68: fresh hit 없음, 상호작용 reset과 메뉴 close 처리. Help hit 전체 경과391ms.
6. catalog가 호출자 reader의180ms 예산도 소진해 후속 menuPath 조회가 실패하고 reset으로 이어지는 코드 경로와 일치한다. resetInteraction이 빈 helpCache도 지우므로 실패 캐시가 남아 반복 사용됐다고 해석하지 않는다.
7. ordinal69–71: mouseUp 큐 나이508ms로 1초 입력 나이 guard를 통과했지만, hit role other/freshHit false. 실제 메뉴가 닫힌 뒤여서 회복하지 못했다. down 단계에서 해결된 후보도 보존되지 않았다.

## 결론의 범위

이번 시도의 직접 실패 경로는 전체 catalog 미완료 → 빈 목록으로의 연결 실패 → down 후보 없음 → 닫힌 뒤 up hit도 없음이다. 입력 전체 누락, 행 parser 거절, 동명 충돌, gate 정책 거절이 이 기록의 최초 실패라고 볼 근거는 없다.

budgetExceeded는 관측됐지만, 이것만 없애면 성공한다고 확정할 수 없다. ipcFailures5는 API별 원인이 구분되지 않고, 자식 구조 읽기 오류는 별도로 catalog를 incomplete로 만들 수 있다. missingValues에는 정상적인 선택 속성 부재도 포함된다. catalog 실패를 빈 캐시로 저장하는 코드는 확인했지만 이번 로그에서 실패 캐시의 후속 cacheHit는 관측되지 않았다.

Enter는 catalog 이벤트 없이 저장됐다. 현재 키보드 경로의 focused/selected/highlighted 중 어느 후보가 최종 사용됐는지는 이 로그만으로 구분되지 않는다. 직접 메뉴 경로를 이용했을 가능성을 확정 사실로 적지 않는다.

## 공동 검토

실제 기존 Claude 세션의 읽기 전용 분석과 후속 반론 대조, Codex 서브에이전트의 독립 분석을 마쳤다. 직접 실패 연쇄와 아래 방향에 남은 차단 이견이 없다. Claude가 초안에서 제시한 별도 측정 전용 배포 선행 요구는 철회했다. 다음 구현 자체에 한정 측정을 포함하면 되며 현재 사용자에게 추가 시험을 요구하지 않는다.

권장 흐름:

1. down에서는 검증된 Help 행의 label/frame만 보존한다. 무거운 전체 catalog를 입력 처리 안에서 돌리지 않는다.
2. 실제 release가 보존한 행 영역과 맞는지 확인해 자체 단조 요청ID를 발급한다. 현재 gate의 mouseUp 이후 시간 의미를 유지하고 down→up에 새로운0.8초 제한을 만들지 않는다.
3. 정상 메뉴 닫힘과 미확정 down 수명, 확정 요청 수명을 분리한다. 진단 Help 세션 번호를 그대로 요청 유효성 기준으로 쓰지 않는다.
4. 입력 처리와 분리한 단일 in-flight resolver에서 닫힌 뒤 현재 메뉴의 완전한 구조를 읽는다. 요청별 시도1회, 전체 마감/노드·자식·깊이·개별 IPC timeout/취소 검사를 둔다. 이미 시작된 개별 AX 호출은 timeout 전 즉시 취소되지 않는 한계가 있다.
5. monitor 큐로 결과를 돌려 process/generation/요청ID·새 요청 우선·설정·suppression·정책을 재확인한 뒤 완전하고 유일한 연결만 저장한다. 실패/모호/만료/취소면 저장하지 않는다. 전역 stale cache/selected leaf 우회/부분 목록 유일성 판단은 사용하지 않는다.

필수 role/children/메뉴 명령 title 실패는 명시적으로 불완전 결과로 다룬다. 빈 제목의 구분선·이름 없는 컨테이너와 정체를 읽지 못한 명령을 구분해야 하며, noValue/unsupported를 모두 무해하다고 묶지 않는다. 현재 catalog의 빈 role/title 치환은 정적 안전 검토 대상이며 이번 IPC5건이 실제로 그 결함을 일으켰다는 뜻은 아니다. 제목/구조 전용 완전 탐색 뒤 일치 후보에만 단축키/식별자를 읽는 최적화도 검토할 수 있지만 실제 비용 분포를 아직 측정하지 않았다.

검증은 timeout/필수값 실패/한도/모호한 동명 및 literal > 충돌/정상 close/새 요청·앱 전환·취소/중복 기록/정책 변경과 일반 메뉴·Enter·기존 다른 앱 Help 클릭 회귀를 포함해야 한다. 현재 Numbers 실패 시도만으로 다른 경로의 회귀 위험이 없다고 주장하지 않는다. 닫힌 메뉴의 조회 완료 여부·시간은 다음 구현의 진단으로 검증하며 성공을 보장하지 않는다. 노드185개 대비372ms를 단순 나눠 노드당 비용이라고 단정하지 않는다.

다음 단계는 사용자가 진행을 지시한 후의 수정 구현이다. 현재 앱·설정·버전·릴리스·Homebrew에는 변경이 없다.
