import AppKit
import SwiftUI

/// R177 comparison only. Production callers retain the current chrome.
enum ChromeProposalPreview {
    case current, inlineTitle
    var proposed: Bool { self == .inlineTitle }
    // Current footer: 16 gap + 18 line + 24 outside + 4 sizing reserve.
    // Proposal: 12 gap + 14 line + 8 outside; no duplicated reserve.
    var heightReduction: CGFloat { proposed ? 28 : 0 }
}

enum ChromeCapture {
    case title, footer
    func rect(in size: CGSize) -> CGRect {
        switch self {
        case .title:
            let width = min(700, size.width)
            return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: 84)
        case .footer:
            return CGRect(x: 0, y: size.height - 100, width: min(600, size.width), height: 100)
        }
    }
}

struct InlineHeaderProposal: View {
    let iconURL: URL?
    let appName: String
    let windowName: String

    var body: some View {
        HStack(spacing: 8) {
            Icon(url: iconURL, size: 20)
                .environment(\.deckScale, 1).accessibilityHidden(true)
            Text(appName).font(.system(size: 18, weight: .semibold))
                .lineLimit(1).truncationMode(.middle).layoutPriority(1)
            Text("—").foregroundStyle(.secondary)
            Text(windowName).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
        }
        .font(.system(size: 13))
        .help("\(appName) — \(windowName)")
        .accessibilityElement(children: .combine)
    }
}

struct ChromeProposalComparison: View {
    let directory: URL
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            panel("현재 · 상단", file: "current-title", width: 700, height: 84)
            panel("제안 · 아이콘 + 앱 이름 18pt — 창 이름", file: "proposed-title", width: 700, height: 84)
            panel("현재 · 왼쪽 아래", file: "current-footer", width: 600, height: 100)
            panel("제안 · 아래 여백 8pt / 좌우 안내 40pt 안쪽", file: "proposed-footer", width: 600, height: 100)
        }
        .padding(16)
        .frame(width: 732)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    private func panel(_ label: String, file: String, width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            if let image = NSImage(contentsOf: directory.appendingPathComponent("chrome-177-\(file).png")) {
                Image(nsImage: image).resizable().frame(width: width, height: height)
            }
        }
    }
}
