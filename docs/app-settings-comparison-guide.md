# Messages 설정 탐지 경로 비교 · 1.9.4(49)

> 과거 시험 빌드용 안내입니다. 1.9.4(53) 배포 후보에서는 compare/probe/임시 로그 옵션을 제거했습니다. 아래 명령을 53 이상에 적용하지 마세요.

다른 앱을 지정하는 build50은 [별도 안내](app-settings-other-apps-guide.md)를 사용한다. 아래는 보존한49 안내다.

파일: `Tile-Launcher-1.9.4-build49-ax-comparison-arm64-unnotarized.zip`.
Developer ID 서명·미공증 시험본입니다. 공증/정식 배포/기존 앱 설치 교체는 하지 않았습니다.47 로그와 구별해49로 분석합니다.48은 전달하지 않았습니다.

## 먼저 할 실험

1. 기존 **Tile Launcher와 Messages를 모두 완전히 종료**합니다. Messages 창만 닫는 것이 아니라 앱 종료(⌘Q)입니다. 다른 Tile Launcher가 함께 돌아가면 그 조회가 실험에 영향을 줄 수 있습니다.
2. ZIP을 풀고, 아래 APP에 **압축 푼 앱의 실제 경로**를 넣습니다. 이 실험을 위해 기존 앱을 덮어쓸 필요는 없습니다.
3. 터미널에서 실행한 뒤 **Messages를 직접 실행**합니다. 자동 클릭/키 입력/앱 실행은 하지 않습니다.

```sh
APP="/압축 푼 위치/Tile Launcher.app"
"$APP/Contents/MacOS/TileLauncher" --app-settings-compare
```

4. Messages를 활성 상태로 최대60초 둡니다. 다른 앱으로 전환하면 중단됩니다. **이 모드는 오버레이나 메뉴 막대 아이콘을 만들지 않습니다.** 타일 표시 여부를 확인하려고 Option을 누르거나 다른 앱으로 전환할 필요가 없습니다. 대화 내용·메뉴 원문을 수집하지 않습니다.
5. 모든 선택 경로의 전체 설정 확인이 각각 연속3회 성공하거나,60초가 지나면 진단이 종료됩니다. Messages를 기다리는 시간을 포함해 전체90초 상한입니다. 터미널 명령이 끝나면 이번 로그를 보냅니다. 시작 시 터미널에 정확한 로그 경로가 표시됩니다.

로그 폴더: `~/Library/Logs/TileLauncher/`.
파일: `app-settings-숫자-PID-고유번호.jsonl`.
한 파일에 API 이름/고정 속성/경로 식별자/시작·끝 시간/오류/메뉴바 획득/전체 설정 확인을 기록합니다. **진단 결과는 제품 캐시나 타일에 반영하지 않습니다.** 이 모드를 쓰지 않고 앱을 다시 실행하면 일반 런처로 돌아옵니다.

권한 없음(`noAppOrTrust`)으로 즉시 끝나면 이 실행본의 접근성 허용 상태를 먼저 확인합니다. 그 로그를 설정 메뉴 미발견으로 해석하지 않습니다. 이 Mac에서 실행한 합성 검사는 집 Mac의 접근성 허용이나 최초 실행 성공을 입증하지 않습니다.

## 한 경로만 대조하기

처음에는 위 전체 비교 로그 하나로 충분합니다. 결과를 보고 유망한 경로를 골라, **매번 Messages를 종료한 상태에서** 별도 실행합니다. 첫 실행의 성공 캐시나 순서 영향을 섞지 않습니다.

```sh
"$APP/Contents/MacOS/TileLauncher" --app-settings-compare --app-settings-route multiple
```

가능한 값:

| 값 | 조회 |
|---|---|
| direct | 기존 AXMenuBar 직접 조회 |
| multiple | AXMenuBar/AXRole 일괄 조회 |
| children | 앱 하위 요소에서 메뉴바 역할 탐색 |
| pagedChildren | 하위 개수·부분 목록 API로 메뉴바 탐색 |
| hitTest | 메뉴바 예상 위치에서 앱 한정 요소·부모 탐색 |
| roleFirst | 앱 역할을 먼저 읽고 메뉴바 조회 |
| namesFirst | 지원 속성 목록을 먼저 읽고 메뉴바 조회 |

`all` 또는 route 옵션 생략은 전체 비교입니다. 전체 비교는 직렬이며 순회마다 시작 경로를 바꿉니다. 다음 순회까지는 **앞 순회 응답 완료 후0.2초**입니다.7개 경로를 동시에 시작하거나 정확한0.2초마다 실행하는 것은 아닙니다. 같은 시작 조건에서 더 빠른지 판정하려면 단독 경로로 새 Messages 실행을 여러 번 비교해야 합니다.

hitTest는 자동 숨김·다중 모니터·가려진 메뉴바 때문에 실패할 수 있습니다. 이 경로만 실패한 것을 ‘설정이 없는 앱’으로 해석하지 않습니다. 정적 리소스 감사의 후보 수도 참고 정보이며 설정 지원 판정이 아닙니다.

## 관찰자를 먼저 등록하는 별도 실험

필요할 때 위 기본 실험과 **다른 실행**으로 비교합니다. Messages를 완전히 종료한 뒤 명령을 시작하고 Messages를 직접 켭니다.

```sh
"$APP/Contents/MacOS/TileLauncher" --app-settings-compare --app-settings-route direct --app-settings-observer-first
```

메뉴바를 먼저 읽지 않고 앱에 AX 관찰자/알림을 등록해 봅니다. 등록·첫 응답·첫 설정 확인의 시간과 오류를 구별합니다. 등록이 조회 준비를 유발했다고 한 번의 시간 차이만으로 결론내리지 않습니다. 옵션 없는 기본 비교에서는 이 관찰자를 만들지 않으며 제품 자동 수집도 실행하지 않습니다.

## 분석자에게 전달할 사항

- 이번 ZIP이1.9.4(49)인지, Messages를 새로 켰는지/이미 켜져 있었는지, route와 observer-first 옵션, 다른 런처가 종료돼 있었는지를 함께 적습니다.
- `session_start.comparisonEnabled=true`, `shutdown`, `log_limit` 유무를 확인합니다. 강제 종료/앱 전환/권한 실패는 정상 완료와 구별합니다.
- route_start/end를 requestID로 묶고, parentRequestID를 probe_queued의 requestID와 연결합니다. workspace.didActivate 또는 probe_begin을 기준으로 `bar_resolved`와 `route_end.reason=found`를 각각 계산합니다. 이미 활성 상태에서 시작한 경우 실제 앱 활성화 시각을 소급 추정하지 않습니다.
- 일괄 API의 외부 성공과 속성별 AXValue 오류를 구분합니다. AXMenuBar의 첫 성공과 전체 후보/활성/실행지원 확인 성공은 다른 결과입니다.
- 호출 순서·실제 API 소요 시간·선행 요청의 영향을 함께 보고, -25204만으로 시간 초과나 OS 내부 원인을 확정하지 않습니다.

자세한 설계와 제한: [비교 검토 기록](reviews/1.9.4-settings-comparison.md).
