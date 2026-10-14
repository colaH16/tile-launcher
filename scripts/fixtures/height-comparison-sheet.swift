import AppKit
import SwiftUI

struct HeightSheet: View {
    let directory: URL
    let part: String
    let height: CGFloat
    let records: [(String, String, String)] = [
        ("a-base", "① 기존 1.0배", "확대 전 크기 재구성"),
        ("b-old-140", "② 당시 1.4배", "큰 여백 · 1.4.0"),
        ("c-now-130", "③ 지금 1.3배", "확정한 새 여백"),
        ("d-tile-140", "④ 타일만 1.4배", "③과 같은 여백")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(part == "left" ? "왼쪽 · 닫기 버튼부터 하단까지" : part == "center" ? "가운데 · 앱·창 이름부터 하단까지" : "오른쪽 · 설정 버튼과 하단 단축키")
                .font(.system(size: 20, weight: .semibold))
            HStack(alignment: .top, spacing: 12) {
                ForEach(records, id: \.0) { record in
                    if let image = NSImage(contentsOf: directory.appendingPathComponent("\(record.0)-\(part).png")) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(record.1).font(.system(size: 17, weight: .semibold))
                            Text(record.2).font(.system(size: 13)).foregroundStyle(.secondary)
                            Text("높이 \(Int(image.size.height))pt").font(.system(size: 13)).monospacedDigit().foregroundStyle(.secondary)
                            Image(nsImage: image).frame(width: 220, height: image.size.height).background(Color.black)
                                .frame(height: height, alignment: .top)
                        }.frame(width: 220, alignment: .leading)
                    }
                }
            }
            Text("동일 축척 · 윗변 정렬 · 39개 등록 항목 · 화면 작업 영역 2560 × 1056pt 가정")
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .padding(20).background(Color(red: 0.035, green: 0.045, blue: 0.055))
        .environment(\.colorScheme, .dark)
    }
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
app.appearance = NSAppearance(named: .darkAqua)
let names = ["a-base", "b-old-140", "c-now-130", "d-tile-140"]
let height = names.compactMap { NSImage(contentsOf: directory.appendingPathComponent("\($0)-full.png"))?.size.height }.max()!
for part in ["left", "center", "right"] {
    let host = NSHostingView(rootView: HeightSheet(directory: directory, part: part, height: height))
    host.appearance = app.appearance
    let size = host.fittingSize
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.05)); host.layoutSubtreeIfNeeded()
    let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.appearance?.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: bitmap) }
    try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("comparison-\(part).png"))
    window.contentView = nil; window.close()
}
