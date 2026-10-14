import AppKit
import SwiftUI

/// R177–R178 comparison only. Production callers retain the current chrome.
enum ChromeProposalPreview {
    case current, inlineTitle, opticalBalance
    var proposed: Bool { self != .current }
    var optical: Bool { self == .opticalBalance }
    var footerExtraInset: CGFloat { optical ? 8 : proposed ? 16 : 0 }
    // Current footer: 16 gap + 18 line + 24 outside + 4 sizing reserve.
    // Proposal: 12 gap + 14 line + 8 outside; no duplicated reserve.
    var heightReduction: CGFloat { proposed ? 28 : 0 }
}

enum ChromeCapture {
    case title, footer, footerRight
    func rect(in size: CGSize) -> CGRect {
        switch self {
        case .title:
            let width = min(700, size.width)
            return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: 84)
        case .footer:
            return CGRect(x: 0, y: size.height - 100, width: min(600, size.width), height: 100)
        case .footerRight:
            let width = min(500, size.width)
            return CGRect(x: size.width - width, y: size.height - 180, width: width, height: 180)
        }
    }
}

struct InlineHeaderProposal: View {
    let iconURL: URL?
    let appName: String
    let windowName: String
    var opticalBalance = false

    var body: some View {
        HStack(spacing: opticalBalance ? 6 : 8) {
            Icon(url: iconURL, size: opticalBalance ? 26 : 20)
                .environment(\.deckScale, 1).accessibilityHidden(true)
            Text(appName).font(.system(size: 18, weight: .semibold))
                .lineLimit(1).truncationMode(.middle).layoutPriority(1)
            Text("—").foregroundStyle(.secondary)
            Text(windowName).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
        }
        .font(.system(size: 13))
        .offset(y: opticalBalance ? 3 : 0)
        .help("\(appName) — \(windowName)")
        .accessibilityElement(children: .combine)
    }
}

struct OpticalChromeComparison: View {
    let directory: URL
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            panel("이전 시안 · 상단", file: "before-title", width: 700, height: 84)
            panel("조정 · 제목을 조금 아래로, 아이콘은 더 크게", file: "after-title", width: 700, height: 84)
            panel("이전 시안 · 오른쪽 아래", file: "before-footer", width: 500, height: 180)
            panel("조정 · 눈에 보이는 곡선에 맞춘 위치", file: "after-footer", width: 500, height: 180)
        }
        .padding(16).frame(width: 732)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    private func panel(_ label: String, file: String, width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            if let image = NSImage(contentsOf: directory.appendingPathComponent("chrome-178-\(file).png")) {
                Image(nsImage: image).resizable().frame(width: width, height: height)
                    .background(Color.black)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
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
