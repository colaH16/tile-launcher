# Tile Launcher

한손 키보드를 쓰다 보니, 두 손이 필요한 키 조합을 누르거나 마우스에서 손을 떼는 일을 줄이고 싶어서 만든 macOS 런처입니다. 메뉴 하나를 고르려고 커서를 메뉴 막대까지 옮겼다가 돌아오는 것도, 최근 앱과 최근 창이 따로 나뉘어 있는 것도 불편했습니다.

그래서 **마우스가 있는 자리에서 메뉴를 실행하고, 앱과 창을 함께 찾아 전환할 수 있도록** 만들었습니다. Option 키를 잠깐 누르면 커서 근처에 타일이 열리고, 원하는 항목을 클릭하면 바로 실행됩니다.

## 다운로드와 설치

[최신 릴리스 다운로드](https://github.com/colaH16/tile-launcher/releases/latest) · [설치 안내](docs/installation.md)

- Apple Silicon Mac · macOS 26 이상
- 배포 앱은 Developer ID 서명과 Apple 공증을 완료했습니다.
- 창 조회·전환과 Option 입력 감지에는 macOS 접근성 권한이 필요합니다.

업데이트 내용은 [릴리스 노트](https://github.com/colaH16/tile-launcher/releases)와 [CHANGELOG](CHANGELOG.md)에서 확인할 수 있습니다.

## 할 수 있는 일

- **앱과 창 전환:** 여러 앱의 열린 창을 한 목록에서 찾고, 창 없이 실행 중인 앱도 선택할 수 있습니다. 타일의 크기와 색으로 데스크탑 위치와 같은 앱의 창을 구분합니다.
- **앱별 메뉴 실행:** 메뉴 막대에서 사용한 명령을 자동으로 모으거나 직접 추가합니다. 자주 쓰는 메뉴는 앞에 고정하고, 지원하는 앱에서는 공통 ‘앱 설정’ 타일로 설정을 엽니다.
- **앱·폴더 등록:** 자주 쓰는 앱과 폴더를 등록하고, 폴더는 오버레이 안에서 탐색하거나 Finder로 열 수 있습니다. 휴지통은 Finder의 통합 휴지통으로 엽니다.
- **프로필 전환:** 용도별 등록 목록을 만들고, 원하는 경우 macOS 집중 모드 필터에 연결합니다.
- **Handoff:** Dock에 나타난 Handoff 항목을 런처에서도 이어 열 수 있습니다.
- **모양 설정:** 유리·파스텔과 클래식·직각 테마를 고르고, 메뉴·최근 창·Handoff·등록 항목의 색을 조절합니다.
- **iCloud 설정 동기화:** 같은 iCloud 계정의 Mac끼리 직접 추가·편집한 메뉴와 모양, 지정한 일반 설정을 공유합니다. 설정 → 일반에서 Mac마다 켤 수 있으며 기본값은 꺼짐입니다. 등록 앱·폴더·프로필과 자동 수집 설정·사용 기록은 Mac별로 유지합니다.

## 사용 방법

1. 앱을 실행하고 메뉴 막대의 Tile Launcher 아이콘에서 설정을 엽니다. 접근성 권한 안내에 따라 시스템 설정에서 앱을 허용합니다.
2. **등록 항목·프로필**에서 앱과 폴더를 추가합니다. **Dock에서 가져오기**는 목록을 먼저 확인한 뒤 편집본에 넣으며, 탭의 **저장**을 눌러 적용합니다.
3. 좌우 어느 쪽이든 **Option만 약 0.25초** 누르면 커서 근처에 오버레이가 열립니다. 원하는 타일을 클릭하면 바로 실행되고, 선택 없이 Option을 놓으면 닫힙니다. 메뉴 막대 좌클릭·메뉴의 ‘열기’·실행 중인 앱 다시 열기는 처음부터 고정 상태로 엽니다.
4. Option으로 연 오버레이를 계속 열어 두려면 왼쪽 위의 핀을 누릅니다. 고정한 오버레이는 Option을 놓아도 유지되며, 닫기 버튼이나 Esc로 닫습니다. 타일과 버튼을 제외한 빈 배경을 드래그하면 위치를 옮길 수 있습니다.
5. **메뉴** 탭에서는 고정 메뉴의 순서를 직접 정합니다. 자동 수집 메뉴는 메뉴 막대와 런처의 누적 사용 횟수가 많은 순서로 표시합니다. 메뉴별 아이콘을 지정하거나 저장된 앱 리소스 아이콘을 새로고침할 수도 있습니다.

일반 설정은 즉시 저장합니다. **모양·메뉴·등록 항목·프로필**은 각 탭의 **저장 / 변경 취소**로 적용하며, 탭을 옮겨도 미저장 편집은 유지됩니다. 앱을 종료하면 미저장 편집은 사라집니다.

마우스 대신 숫자로 고를 수도 있습니다. 기본 배치는 다음과 같고, 설정 → 일반에서 등록 항목과 최근 창의 배치를 서로 바꿀 수 있습니다.

| 키 | 동작 |
|---|---|
| `⌥1–9, 0` | 등록 항목 선택, Option을 놓으면 실행 |
| `⌥⌘1–9, 0` | 최근 창 선택, Option을 놓으면 실행 |
| `⌥X` | 오버레이 고정 |
| `⌥W` | 오버레이 닫기 |
| `⌥,` | Tile Launcher 설정 열기 |
| `Esc` | 선택 취소·오버레이 닫기 |

숫자는 각 목록의 첫 10개에 표시되며, 0은 열 번째 항목입니다. 선택 없이 닫은 뒤 Option을 빠르게 다시 누르면 직전 위치로 복원하는 보정 기능도 있습니다.

## 권한과 제한

입력 문자와 메뉴 검색어는 저장하지 않습니다. 창 이력은 실행 중 메모리에만 유지하고, 등록 항목·메뉴·표시 설정은 이 Mac에 로컬 저장합니다. iCloud 동기화를 켜면 지정한 메뉴·표시 설정은 사용자의 iCloud 개인 데이터베이스에도 저장합니다. 화면 녹화 권한이나 창 이미지는 사용하지 않습니다.

창 목록은 macOS가 제공하는 개별 창을 기준으로 합니다. 앱 내부의 탭·분할 화면을 각각의 창으로 표시하지는 않습니다. 다른 데스크탑의 창 처리와 Dock의 Handoff는 일부 macOS 내부 구조에 의존하므로 OS 변경이나 앱의 접근성 지원에 따라 동작이 제한될 수 있습니다.

메뉴 자동 수집은 앱의 메뉴 막대와 Help 검색 결과를 대상으로 합니다. 단축키 직접 실행·리본·우클릭 메뉴는 수집하지 않으며, 앱에 따라 알림이나 메뉴 구조를 제공하지 않으면 누락될 수 있습니다. 전체 수집 중단, 앱별 중단, 메뉴별 제외가 가능합니다. [자동 수집의 동작과 제한](docs/menu-observation-design.md)

## 소스 빌드와 검증

전체 Xcode와 Swift 6 이상이 필요합니다. 현재 검증 환경은 Apple Silicon / macOS 27.2 베타이며, 외부 패키지 의존성은 없습니다.

```sh
bash scripts/build.sh
open "$HOME/Library/Developer/TileLauncher/build/Tile Launcher.app"
bash scripts/test.sh
```

Xcode가 별도 위치에 있다면 명령 앞에 `DEVELOPER_DIR`를 지정합니다. 전역 `xcode-select`를 바꿀 필요는 없습니다.

```sh
DEVELOPER_DIR="/Applications/Develop/Xcode-beta.app/Contents/Developer" bash scripts/build.sh
```

기본 출력은 `~/Library/Developer/TileLauncher/build`이며 `TILE_LAUNCHER_OUTPUT_DIR`로 바꿀 수 있습니다. 로컬 빌드는 개발용 ad-hoc 서명으로, 공증된 다운로드 앱과 구별합니다. 서명 작업은 메타데이터가 덧붙을 수 있는 Desktop·문서·클라우드 동기화 폴더 밖에서 진행합니다.

`Package.swift`를 Xcode에서 열어 편집할 수 있습니다. 실제 사용자 앱이나 설정을 건드리지 않는 샘플 미리보기는 다음 명령으로 생성합니다.

```sh
DEVELOPER_DIR="/Applications/Develop/Xcode-beta.app/Contents/Developer" bash scripts/preview.sh /tmp/tile-launcher-previews
```

비표시 미리보기는 실제 Liquid Glass 합성·키 입력·드래그 검증을 대신하지 않습니다. 배포 버전과 빌드 번호는 `release/config.json`에서 관리하며, 서명·공증·GitHub 배포 절차는 [배포 가이드](docs/release-guide.md)를 참고하세요.

## 문서

- [릴리스 노트](https://github.com/colaH16/tile-launcher/releases) · [버전 이력](CHANGELOG.md)
- [설치 안내](docs/installation.md)
- [현재 요구사항](docs/requirements.md) · [사용자 요청 기록](docs/request-log.md)
- [검증 기록](docs/validation.md) · [macOS 업그레이드 지침](docs/macos-upgrade-guide.md)
- [조작·크기 설계](docs/interaction-design.md) · [아이콘 원본](Resources/Brand/README.md)

## 라이선스

[MIT](LICENSE)
