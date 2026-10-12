# 첫 네이티브 빌드 검증

검증일: 2026-10-12, Asia/Seoul. 제품명 Tile Launcher, 개인용 0.1.0.

## 확인한 환경

- macOS 27.2 베타, 빌드 26B5101f / Apple Silicon arm64.
- Xcode 27.2 베타, 빌드 27B5028f: `/Applications/Develop/Xcode-beta.app`.
- Swift 6.4. 프로젝트별 `DEVELOPER_DIR`로 사용했으며 전역 xcode-select는 변경하지 않음.
- 최소 배포 버전 macOS 26. macOS 26 실기·Intel에서는 검증하지 않음.

## 통과

- Swift/SwiftUI/AppKit 네이티브 앱 컴파일과 로컬 릴리스 패키징.
- 자동 테스트 **10개, 실패 0개**. 사용자 최근 앱/창 예시 3종, 닫힌 항목 정리, 다양한 화면 비율/음수 원점/경계, 초광폭 크기 불변, 수동 개수 및 실제 창 수 제한, Option 조합키 취소, 실제 임시 폴더의 자연 정렬·숨김 항목 제외·앱 패키지 구별·읽기 실패, 날짜순 및 누락 날짜 정렬.
- 동기화 폴더 밖에서 만든 `.app`의 ad-hoc 서명 및 `codesign --verify --deep --strict` 검증.
- macOS LaunchServices로 실제 앱 실행. 약 30분 뒤 프로세스 생존 확인. 해당 시점 `ps` 스냅샷은 CPU 0.0%, RSS 약 88MiB였음. **접근성 권한 미허용 상태의 단일 표본**이며 다수 창/반복 호출/장시간 성능 보장이 아님.
- 자체 NSHostingView 렌더 결과에서 초기 권한 안내 화면의 제목·구획·푸터가 패널 안에 배치됨을 확인. 이 이미지는 앱 자신의 콘텐츠만 렌더한 것으로 WindowServer의 실제 유리 배경 합성을 검증하지 않음.

## 아직 확인하지 못한 항목

- 접근성 허용 후 실제 Option 단독 호출·클릭 후 해제·앱/창 전환. 권한은 사용자가 시스템 설정에서 허용해야 함.
- iTerm 실제 여러 창, Safari/Chrome, 최소화·다른 Space·전체 화면·Stage Manager 전환.
- UI를 통한 폴더 등록·순서 변경·파일 실행·휴지통 접근 허용/거부. 파일 목록·정렬의 자동 테스트와 실제 사용자 조작 검증은 다름.
- 실제 배경 위의 Liquid Glass, Light/Dark·투명도 줄이기·VoiceOver, 물리적 다중 모니터.
- 유휴 상태와 5/20/50개 창의 CPU·메모리·호출 지연을 Instruments로 비교하는 성능 측정.
- 앱별 메뉴·메뉴 순서 변경·집중 모드 연동은 다음 구현 단계.

## 환경 이슈와 재현 방법

- 명령줄 도구만으로 앱은 컴파일할 수 있지만 현재 CLT에는 XCTest가 없어 테스트는 설치된 전체 Xcode를 사용함.
- 빌드 캐시는 프로젝트 `.build`에 둠. 코드 서명 전에 생성물의 Finder 메타데이터를 제거하고 서명을 검증함.
- Desktop 작업 경로는 File Provider 메타데이터가 `.app`에 다시 붙는 것이 확인됨. 기본 앱 출력 경로를 `~/Library/Developer/TileLauncher/build`로 분리함. 소스 저장 위치는 변경하지 않음.
- 로컬 릴리스 스크립트는 최적화된 코드에 별도 dSYM을 생성하지 않음. Instruments에서 상세 소스 단위 분석이 필요하면 디버그 심벌을 포함한 별도 프로파일 빌드를 사용할 것.
- 컴퓨터 사용 도구의 앱 선택이 시간 초과하여 클릭 기반 UI QA를 완료하지 못함. 성공으로 기록하지 않음.
- 기본 실행은 메뉴 막대 앱. `--show` 인자를 주면 패널을 즉시 열어 확인할 수 있음. 개발 검증용 `--render-check <PNG 경로>`는 자체 콘텐츠를 저장하고 종료하며 다른 앱/화면 전체를 캡처하지 않음.

```sh
DEVELOPER_DIR="/Applications/Develop/Xcode-beta.app/Contents/Developer" ./scripts/test.sh
DEVELOPER_DIR="/Applications/Develop/Xcode-beta.app/Contents/Developer" ./scripts/build.sh
open "$HOME/Library/Developer/TileLauncher/build/Tile Launcher.app"
```

## 다음 사용 확인

1. 메뉴 막대 격자 → 설정 → 앱·폴더 추가, 순서를 바꾸고 재실행해 유지 확인.
2. 접근성 설정에서 Tile Launcher 허용 후 Option 단독/Option+다른 키 비교.
3. 실제 OS 창 6개 이상에서 순서·두 줄·수동 개수·스크롤 확인.
4. 다운로드와 휴지통의 읽기 권한, 폴더 진입/뒤로/파일 열기 확인.
5. 실제 외관 피드백과 Instruments 결과를 바탕으로 다음 변경을 기록.
