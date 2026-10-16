# Messages 앱 설정 타일 진단

> 과거 시험 빌드용 안내입니다. 1.9.4(53) 배포 후보에서는 compare/probe/임시 로그 옵션을 제거했습니다. 아래 명령을 53 이상에 적용하지 마세요.

새49 대체 경로 비교는 [별도 실행 안내](app-settings-comparison-guide.md)를 사용합니다. 아래는47의 기존 반복 probe 안내이며 두 실험은 다릅니다.

대상: 1.9.4 빌드47 반복 진단본(빌드45·46에도 기존 --app-settings-log 옵션은 있습니다). 기본 실행에서는 로그를 기록하지 않습니다. 기존1.9.3과 시험43에는 이 옵션이 없습니다.

## 실행과 재현

1. **Tile Launcher와 Messages를 모두 완전히 종료**한 뒤 수정 ZIP의 앱으로 집 Mac의 Tile Launcher를 교체합니다. 이미 실행 중인 같은 빌드에 옵션을 붙여 다시 열면 기존 프로세스가 유지돼 진단이 켜지지 않습니다.
2. 터미널에서 실행합니다. 다른 폴더에 설치했다면 앱 경로만 바꿉니다.

```sh
open -n "/Applications/launch at Login/Tile Launcher.app" --args --app-settings-probe
```

3. Messages를 새로 실행하고 **다른 앱으로 전환하지 말고 최대1분간** 둡니다. 관찰은 연속3회 전체 설정 탐지 성공 또는60초에 자동으로 끝납니다. ‘앱 설정 타일 표시’는 켜 둡니다. 메뉴 자동 수집은 현재 설정대로 유지되며, 꺼져 있으면 관찰자 연결 이벤트도 생기지 않습니다. 이번 probe 결과는 제품 캐시를 바꾸지 않으므로 타일이 계속 없어도 로그에는 첫 읽기 성공이 남을 수 있습니다. 메시지 대화/메뉴를 조작할 필요가 없습니다.
4. 재현 후 Tile Launcher를 종료하면 대기 중 로그를 모두 씁니다. Finder에서 다음 폴더를 엽니다.

```sh
open "$HOME/Library/Logs/TileLauncher"
```

이번 실행 시각의 `app-settings-날짜숫자-PID-고유번호.jsonl` 한 파일을 전달하면 됩니다. 다음 실행에 `--app-settings-log`를 빼면 기록하지 않습니다. 기존 파일은 덮어쓰지 않습니다.

## 빌드47 반복 진단과 판독

--app-settings-probe가 로그도 자동으로 켭니다. 기존 제품 탐지는 build46 그대로이며 probe만5회 한도를 넘어 정상 미발견/오류 후에도 계속 읽습니다. 실제 finder와 동일 직렬 AX 큐를 사용하고 다음 요청은 응답 완료 후0.2초 뒤에 보냅니다. 동시 요청은1개이고 전환·종료·권한 취소·프로세스 변경 때 중단합니다. 완료한 같은 프로세스는 자동 재시작하지 않으며 새 실험은 런처 또는 Messages를 재실행합니다.

`fields.component`는 `settings`(일반 제품 탐지), `probe`(반복 실험), `menuCapture`(메뉴 자동 수집)입니다. probe_begin/probe_queued/probe_read_start/probe_read_end/probe_end와 probeID/requestID/attempt를 묶어 봅니다. probe_read_start는 실제 AX 큐에서 읽기 시작한 시점이며 probe_queued와 구별합니다.

- AXMenuBar의 첫 성공: component=probe, attribute=AXMenuBar, api=AXUIElementCopyAttributeValue, axCode=0인 첫 ax_read.
- 전체 설정 탐지의 첫 성공: probe_read_end.reason=found. 메뉴바 읽기 성공과 설정 후보/활성/실행지원 확인 완료는 다른 시점입니다.
- API 시간: apiStartedMS/apiEndedMS는 같은 단조 증가 uptime 기준입니다. API 이름·속성 이름·소요 시간·오류 코드만 기록하고 반환 값은 기록하지 않습니다. 타임아웃 설정/로컬 application 객체 생성의 성공은 대상 앱 메뉴가 준비됐다는 뜻이 아닙니다.
- 자동 수집: capture_connect/capture_retry, AXMenuBar 읽기, AXObserverCreate/AXObserverAddNotification/CFRunLoopAddSource와 고정 메뉴 알림 이벤트를 첫 probe 성공과 비교합니다. 자동 수집을 켜거나 연결 API를 추가 호출하는 실험은 이번에 하지 않습니다.

관찰 간격은 **읽기 시간+0.2초**입니다.300ms 오류가 나면 다음 요청까지약0.5초이며 정확한0.2초 정밀도를 보장하지 않습니다. 서로 다른 큐의 sequence는 기록 큐에 도착한 순서라 API 선후관계는 uptime과 시작/끝 시각으로 비교합니다. 앞선 호출이 준비의 원인인지, OS 내부 준비가 언제 완료됐는지까지 로그의 선후관계만으로 확정하지 않습니다. 반복 조회 자체가 타이밍에 영향을 줄 수도 있습니다.

## 기존 진단 기록

빌드46은 시작 중이면 `launch_deferred`를 남기고, 완료 알림 또는 최대1초 단발 대기 후 `launch_ready` → `read_start`를 남깁니다. origin은 각각 `launchCompletion`/`launchFallback`입니다. 이 대기만으로 실패 횟수가 늘지 않습니다. `cache_published.reason`은 이제 실제 읽기 결과를 따라 `readerError`/`notFound`를 구별합니다. 빌드45의 `cache_published.notFound`는 앞선 read_end와 함께 해석해야 합니다.

- Messages 실행·활성화·종료 알림, 조회 요청 원인, 요청ID, 조회 시작·끝, 개별 AX 속성의 상태 코드·소요 시간·읽기 예산.
- 정상 미발견의 이유(메뉴바/앱 메뉴 미준비, 후보 없음·모호함, 비활성 항목 등), 오류, 취소, 프로세스 변경에 따른 결과 폐기.
- 캐시 게시와 알려진 지원/실패5회 도달에 따른 생략. 조회 요청부터 게시까지 같은 requestID로 연결합니다.
- 표시 갱신 요청·숨김/입력 중 보류, 표시용 snapshot의 `cachedSupport`, `optionEnabled`, `trusted`, `snapshotSupport`, `tileIncluded`, `targetContext`.
- 세션 시작에 앱 버전·빌드가 있으며 `instance_reused`로 끝났다면 새 로그 프로세스가 기존 실행본에 자리를 넘긴 것입니다. 기존 앱을 완전히 종료한 후 위 명령으로 실행합니다.

메뉴·창 이름, 대화, 검색어, AX 반환 값, 오류의 설명문, 다른 앱의 이름·ID·PID는 기록하지 않습니다. 다른 앱으로의 전환은 식별 정보 없는 이벤트만 남깁니다. 파일은 소유자만 읽고 쓸 수 있는0600 권한입니다. --app-settings-log는4MiB, --app-settings-probe는32MiB에 도달하면 `log_limit`을 남기고 기록을 중단합니다.

AX `cannotComplete`(-25204)는 오류 코드이며 시간 초과를 단독으로 입증하지 않습니다. 개별 읽기의 실제 시간/예산과 전체 마감(`deadline`)을 함께 봅니다. `snapshot`은 렌더링 입력의 포함 여부로, 실제 화면 픽셀이나 타일 클릭 성공을 검증하지 않습니다.

빌드45의 진단 자체는 AX 조회를 추가하지 않습니다. 빌드46 수정은 시작 중의 첫 조회를 최대1초 단발 예약으로 미룹니다. 주기 폴링이나 완료된 조회 뒤 연속 재시도는 하지 않습니다. 미발견 앱은 전환당1회/누적5회 실패 중단, 개별AX300ms/전체조회2초입니다. 성공한 앱의 지원 여부는 대상 앱 재실행 후에도 유지하고 Tile Launcher 재실행 때 초기화합니다. 따라서 **처음 발견하기 전 문제**를 다시 관찰하려면 Tile Launcher부터 새로 실행해야 합니다. 진단 활성화 시에는 시간 측정·비동기 파일 기록 비용이 추가됩니다.

## 검증과 배포 상태

Release 빌드, XCTest215개·Python23개, 전체 비표시 네이티브 검사를 통과했습니다. 합성 읽기로 미발견/오류/성공, 요청 연결, 캐시 유지/5회 중단, 취소된 결과, 동시 기록, 비밀 문자열 미포함, 권한/덮어쓰기 방지와 용량 제한을 검증했습니다. 실제 집 Mac 최초 누락 원인은 재현 로그를 받아야 판단할 수 있습니다.

빌드47은 관찰용이며 일반 오류 재시도 수정본으로 해석하지 않습니다. probe를 켜지 않으면 일반 제품의 조회/캐시는46과 같습니다. 진단 ZIP은 Developer ID 서명·미공증입니다. 정식 최신1.9.3과 기존 시험test.1/43, 개발 Mac 설치본은 이번 작업으로 바꾸지 않습니다.
