# 다른 앱의 설정 탐지 비교 · build51

> 과거 시험 빌드용 안내입니다. 1.9.4(53) 배포 후보에서는 compare/probe/임시 로그 옵션을 제거했습니다. 아래 명령을 53 이상에 적용하지 마세요.

이번 시험본은 **1.9.4(51)**이다.**한 번 실행할 때 앱 하나를 7개 경로로 병렬 비교**한다. 각 경로는 독립 AX 객체를 만들고 회차별 공통2초 마감 안에서 전체 설정 탐지를 수행한다. 한 경로가 먼저 성공해도 다른 경로 결과를 모두 남긴다. 모든 경로가 끝난 뒤0.2초 후 다음 회차를 시작한다. 자동 다중 앱 조사나 집계기는 넣지 않았다. 서명·미공증 시험본이며 기존 설치 앱을 덮어쓸 필요가 없다.

## 사용자가 직접 실행할 순서

1. 기존 Tile Launcher와 **시험할 앱을 ⌘Q로 완전히 종료**한다.
2. ZIP을 풀고 그 안의 **`Music 비교 실행.command`**, **`Safari TP 비교 실행.command`**, **`Dia 비교 실행.command`** 중 하나를 더블클릭한다. 터미널에 `Comparing target: … Mode: parallel; routes: 7`와 로그 경로가 나와야 한다.
3. **그다음 해당 앱을 직접 실행하고 활성 상태로 둔다.** 진단이 먼저 켜지고 대상 앱이 나중에 켜지는 순서다. 메뉴를 열거나 설정을 누를 필요는 없다.
4. 선택한 앱의 모든 경로가 각각 연속3회 전체 탐지에 성공하거나, 측정 시작 후 최대약60초가 지나면 진단 프로세스가 자동 종료된다. 대상 앱 실행을 기다리는 시간을 포함해 전체90초 상한이며 macOS 스케줄링으로 종료 이벤트가 늦게 처리될 수 있다. 측정 중 다른 앱으로 전환하거나 대상 앱을 종료해도 중단된다.
5. `~/Library/Logs/TileLauncher/`에 생긴 이번 JSONL을 전달한다. 파일은 실행마다 따로 만들고 이전 로그에 이어 쓰지 않는다. 다른 앱을 시험하려면1번부터 해당 실행 파일로 반복한다.

**메뉴 막대 아이콘과 Option 오버레이는 만들지 않는다.** 이번에는 타일 표시가 아니라 앱 메뉴를 읽을 수 있는 시점을 측정한다. `.app`을 그냥 더블클릭하는 대신 ZIP 안의 위 `.command`를 사용한다. 이미 실행 중인 TileLauncher가 있으면 실행 파일은 그 프로세스를 종료하지 않고 안내 후 중단한다.

**도중에 종료하려면 실행한 터미널에서 Control+C.** 진단이 종료 메시지와 shutdown을 남기고 끝난다. 터미널과 분리해 실행했다면 활성 상태 보기의 해당 `TileLauncher` 프로세스를 종료한다. 미완료/취소 기록은 성공 또는 설정 없음으로 해석하지 않는다.

## Orion 등 다른 앱 지정

ZIP의 **`다른 앱 직접 지정.command`**를 실행해 앱 번들 ID 또는 `.app`의 실제 경로를 입력한다. 경로는 Finder에서 앱을 선택하고 Option+Command+C로 복사해 붙여넣을 수 있다. 선택한 앱을 먼저 종료해 둔 뒤, 터미널에 `Comparing target`이 나온 다음 그 앱을 실행한다.

CLI를 직접 쓰려면 압축 푼 폴더에서 다음처럼 실행한다. **이번에는 build51 실행 파일을 사용한다. 기존50은 직렬 비교였다.**

```sh
./"Tile Launcher.app"/Contents/MacOS/TileLauncher --app-settings-compare --app-settings-target com.apple.Music
```

```sh
./"Tile Launcher.app"/Contents/MacOS/TileLauncher --app-settings-compare --app-settings-target com.apple.SafariTechnologyPreview
```

```sh
./"Tile Launcher.app"/Contents/MacOS/TileLauncher --app-settings-compare --app-settings-target company.thebrowser.dia
```

Orion 등은 실제 앱 경로를 지정할 수도 있다. 아래는 경로 형식의 예이므로 설치 위치에 맞게 바꾼다.

```sh
./"Tile Launcher.app"/Contents/MacOS/TileLauncher --app-settings-compare --app-settings-target "/실제 설치 위치/Orion.app"
```

`--app-settings-target`을 생략하면 이전처럼 Messages다. `--app-settings-probe`는 기존 Messages 반복 진단이고7경로 비교가 아니므로 이번에는 사용하지 않는다. 실행 파일들은 올바른 compare 옵션을 넣어 둔 것이다. `open … --args`는 앱과 별개로 CLI가 바로 반환하므로, 실행 상태가 보이는 위 직접 실행 방식을 사용한다.

## 로그 해석

비교 모드 session_start의 appID와 workspace/개별 API/route의 appID·appName이 선택 대상을 식별한다. 선택하지 않은 다른 앱 정보는 기록하지 않는다. 메뉴·대화·창 제목·AX 반환 값은 쓰지 않는다.

- `bar_resolved`: 그 경로로 메뉴바를 얻고 소유 PID를 확인한 시점.
- `route_end.reason=found`: 실제 앱 메뉴의 설정 후보·활성·AXPress 지원까지 확인한 시점. 실행 동작은 하지 않는다.
- 전체 found가 있는 경로만 속도 순위에 넣는다. 실패 시도는 원본에 보존하고 정상 미발견/AX 오류/마감/취소를 구분한다.
- 조회 자체가 없으면 미측정이며0% 성공이나 실패로 분류하지 않는다. `finishedLaunching=false` 활성화와 이후 didLaunch 기록으로 신규 실행 순서를 확인한다.
- `session_start.fields.parallel=true` 및 `round_start/round_end`로 병렬 모드를 확인한다. 각 `route_start/route_end`의 실제 uptime과 고유 requestID, 공통 parentRequestID/round로 겹친 구간을 확인한다. 병렬에서는 직렬 순서인 `order`를 쓰지 않는다.
- 첫 성공까지 시간과 성공 요청 처리시간은 구분한다. 병렬로 요청해도 대상 앱/macOS가 내부적으로 직렬 처리하거나 자원을 공유할 수 있으므로 독립 성능이라고 단정하지 않는다.
- 병렬 모드에서는 정적 앱 리소스 audit를 하지 않는다. 선택된 앱의 AX 경로와 전체 설정 탐지만 비교한다.
- 비교용51은 먼저 성공해도 나머지 경로를 취소하지 않는다. 3경로·첫 성공 시 나머지 중단·탐색 중 비활성 설정 타일은 비교 결과 후 실제 앱 적용 단계다. 이번51의 일반 제품 동작/캐시는 바꾸지 않았다.
- 이전 방식과 대조하려면 CLI 끝에 `--app-settings-serial`을 추가한다. 이 옵션이 없으면 build51의 compare는 기본 병렬이며 `--app-settings-route` 단독 경로 대조도 유지한다.
