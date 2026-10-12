# Tile Launcher

Option을 누르면 커서 근처에 열리는 macOS 네이티브 런처. 최근 앱과 개별 창을 따로 보여주며, 앱·폴더를 직접 등록합니다. SwiftUI와 AppKit의 Liquid Glass를 사용합니다.

개인용 **0.1 개발 버전**입니다. 실제 외관과 입력 동작을 검증하는 첫 빌드이며, App Store·Homebrew 배포와 Sites 게시를 진행한 상태가 아닙니다.

## 빌드와 실행

- macOS 26 이상. 현재 검증 대상은 Apple Silicon / macOS 27.2 베타입니다.
- Swift 6 이상과 해당 macOS SDK. 단위 테스트는 XCTest가 포함된 전체 Xcode를 사용합니다.
- 외부 패키지 의존성 없음. 로컬 빌드는 ad-hoc 서명하며 공증된 배포 앱이 아닙니다.

```sh
./scripts/build.sh
open "$HOME/Library/Developer/TileLauncher/build/Tile Launcher.app"
./scripts/test.sh
```

Xcode가 별도 위치에 있으면 `DEVELOPER_DIR`를 해당 Xcode의 `Contents/Developer`로 지정합니다. 전역 `xcode-select`를 변경할 필요는 없습니다.

```sh
DEVELOPER_DIR="/Applications/Develop/Xcode-beta.app/Contents/Developer" ./scripts/build.sh
DEVELOPER_DIR="/Applications/Develop/Xcode-beta.app/Contents/Developer" ./scripts/test.sh
```

기본 앱 출력 경로는 `~/Library/Developer/TileLauncher/build`입니다. Desktop/iCloud 등의 동기화 폴더가 `.app`에 메타데이터를 덧붙여 서명을 깨뜨리는 것을 피합니다. `TILE_LAUNCHER_OUTPUT_DIR` 환경 변수로 출력 위치를 바꿀 수 있습니다.

`Package.swift`를 Xcode에서 열어 소스를 편집할 수 있습니다. 권한 검증과 실제 사용에는 위 스크립트가 만든 같은 경로의 `.app`을 사용하세요. 개발용 서명/앱 경로가 바뀌면 macOS 접근성 권한 재등록이 필요할 수 있습니다.

## 사용

1. 실행하면 메뉴 막대에 격자 아이콘이 생깁니다. ‘설정’에서 앱·폴더·다운로드·휴지통을 등록합니다. 화살표 또는 목록 이동으로 순서를 바꿉니다.
2. ‘접근성 권한 요청’을 누르고 시스템 설정에서 Tile Launcher를 허용합니다. 시스템 입력 감지와 다른 앱의 창 조회/전환에 사용합니다. 앱이 권한을 자동으로 허용하지 않습니다.
3. 좌/우 Option만 0.25초 누르면 패널이 열립니다. 항목을 클릭하고 Option을 놓으면 실행합니다. 선택하지 않고 놓으면 닫힙니다. 메뉴 막대의 ‘열기’로는 키를 누르지 않고 사용할 수 있습니다.
4. 폴더 타일을 누르면 패널 안에서 탐색합니다. 하위 폴더와 뒤로 가기, 추가된 날짜순·이름순, Finder에서 열기를 제공합니다. 파일·앱을 선택하면 기본 연결 앱으로 엽니다.
5. 최근 창은 행 우선·두 줄이며, 설정에서 자동 개수 또는 6 이상의 수동 개수를 선택합니다. 넘치는 항목은 최근 창 영역만 세로로 스크롤합니다.

입력 문자를 저장하지 않으며 창 이력은 실행 중 메모리에만 유지합니다. 앱 시작 전의 사용 순서를 복원하지 않습니다. 등록 항목과 표시 설정은 이 앱의 UserDefaults에 로컬 저장합니다.

## 첫 버전의 범위와 제한

- 최근 창은 접근성 API가 제공하는 **OS 창**입니다. 같은 앱의 여러 창은 분리하지만 iTerm의 탭·분할은 각각의 창으로 만들지 않습니다.
- 최근 앱은 실행 중인 앱을 중복 제거하여 최대 3개, 최근 창은 현재 창을 포함합니다. 패널을 연 동안 순서는 고정하고 재호출 시 갱신합니다.
- 접근성 정보를 제공하지 않는 앱, 다른 Space·전체 화면·최소화 창의 동작은 실제 앱별 검증이 필요합니다. 조회는 백그라운드에서 시간 제한을 두고 수행합니다.
- 폴더 권한은 macOS 설정에 따릅니다. 휴지통은 현재 사용자의 `~/.Trash`이며 외장 볼륨까지 합친 Finder의 통합 휴지통은 아닙니다. 읽기 불가 시 안내와 Finder 열기를 제공합니다. 파일 삭제/휴지통 비우기는 제공하지 않습니다.
- 추가 날짜 메타데이터가 없는 파일은 생성일을 사용합니다. 폴더는 열거나 새로고침할 때 조회하고 백그라운드 감시·재귀 색인은 하지 않습니다.
- 앱별 고정 메뉴와 메뉴 순서 편집, 집중 모드 연동은 **다음 단계**입니다. 현재 메뉴 영역은 준비 상태로 표시합니다.
- 정상 패널 760–1,040 × 620–720pt, 목표 비율 5:4, 허용 1.2–1.5, 화면 여백 24pt. 작은 작업 영역은 간격·배치를 줄이며 512×420pt 패널을 담을 수 없는 화면은 지원 안내를 표시합니다.
- 전역 키 감지는 원래 앱의 입력을 차단하지 않습니다. Option 조합 입력은 패널을 취소합니다. Escape도 패널을 닫지만 원래 앱에 전달될 수 있습니다.

## 개발 기록

- [현재 요구사항](docs/requirements.md)
- [요청 기록](docs/request-log.md)
- [조작·크기 설계 근거](docs/interaction-design.md)
- [macOS 업그레이드 지침](docs/macos-upgrade-guide.md)
- [검증 결과](docs/validation.md)

새로운 요청은 요청 기록과 요구사항에 함께 반영하고, 단위 테스트·실제 UI 검증·성능 측정을 구분하여 남깁니다.
