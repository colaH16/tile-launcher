# 개별 타일 드래그 예외의 계산 비용 · R268 · 2026-10-17

M2 Pro / 32GiB / macOS27.2(26B5112a), Swift5 언어 모드·arm64 macOS26타깃·-O·whole-module-optimization으로 실행했다. 제품 OverlayDragGeometry 함수 본문을 사용하고 별도 컴파일을 위한 CoreGraphics import만 추가했다.

| 사각형 수 | 클릭 위치 판정 중앙값(µs) | 좌표 전체 생성+클리핑 중앙값(µs) |
|---:|---:|---:|
| 3 | 0.0104 | 0.414 |
| 20 | 0.0450 | 1.141 |
| 50 | 0.0873 | 2.234 |
| 100 | 0.1498 | 4.253 |
| 200 | 0.2935 | 8.236 |
| 1000 | 1.4540 | 39.893 |

1µs=0.001ms. 판정은 타일에 걸리지 않는 빈자리에서 목록 전체를 검사하는 경우다.21배치×10000회 판정의 배치당 평균 시간 중 중앙값이며 단일 사용자 클릭의 지연 통계가 아니다. 좌표 생성+클리핑은21배치×500회 재구성이다. 첫 타일/마지막 타일 적중과 사각형0개 기준도 JSON에 보존했다. 결과를 checksum으로 사용해 최적화로 전체 계산이 제거되지 않게 했다.

사각형100개는 단순 좌표 저장3200바이트이고 검사1회는약0.00015ms다. 순수 사각형 판정은 이 Mac에서 충분히 처리할 수 있다. 이 측정에는 SwiftUI anchor 해석/전체 레이아웃/뷰 생성/GPU 렌더링/WindowServer 지연/물리 마우스 입력이 없다. 과거 낮은프레임의 원인을 이번 수치로 확정하거나 전체앱60fps를 보장하지 않는다.

실제 제품도 이미 타일·컨트롤별 anchor를 받아 제외 사각형 목록으로 만들고 클릭 때 검사한다. 매번 앱/창/화면을 탐색하는 방식이 아니다. B의 문제는 좌표 검사 성능이 아니라 금지 판정을 실제 AppKit 이동 차단으로 연결하지 못한 것이다.

독립 샘플v2에서 원본mouseDown을 AppKit에 전달하기 전에 NSPanel.isMovable/isMovableByWindowBackground를 함께 제한하고, 금지뷰의mouseDown/mouseDragged도 상위 전달하지 않게 했다. C는 캐시한 개별 타일/설정/핀 사각형만 제외하며 타일이 없는 섹션 내부 빈자리도 허용한다. 실제 물리 차단 성공은 사용자의 집 Mac 검증 대상이다. A의 미세 이동 클릭 문제는 이번에 바꾸지 않았다.

재현 명령: DEVELOPER_DIR를 Xcode로 지정한 환경에서 tools/drag-samples/benchmark/run.sh OUTPUT_JSON.
원본 JSON은 전달 ZIP의geometry-benchmark.json이다.

## 전달 결과

소스a8d80a7의독립샘플0.2.0(2), Developer ID 서명·미공증이다.최종화면밖AppKit검사는이동가능플래그게이트/클릭중복취소/단발길게/우클릭/핀을통과했고,실제마우스드래그는실행하지않았다.검사중sandbox_extension_issue_file_to_process 경고가있었으나검사/렌더링exit0이다.

iCloud:Tile-Launcher-drag-samples-v2-ABC.zip
ZIP226065바이트,SHA256 e47abfac9a6056f449f479bca0897eb4fe67e8dde9f756ea5fa133c7eb72351c.
ZIP재추출서명/영역검사를통과했다.원본순수기하벤치마크JSON/소스/성능설명/실행안내/A·B·C PNG를동봉했다.기존샘플을종료한뒤v2의C항목이있는지확인해사용한다.제품앱/설치/정식배포는변경하지않았다.
