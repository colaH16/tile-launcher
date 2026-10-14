import AppKit
import SwiftUI

/// R177–R179 comparison only. Production callers retain the current chrome.
enum ChromeProposalPreview {
    case current, inlineTitle, opticalBalance, largerTitle
    var proposed: Bool { self != .current }
    var optical: Bool { self == .opticalBalance || self == .largerTitle }
    var titleScale: CGFloat { self == .largerTitle ? 1.15 : 1 }
    var footerExtraInset: CGFloat {
        switch self {
        case .current, .largerTitle: 0
        case .inlineTitle: 16
        case .opticalBalance: 8
        }
    }
    // Current footer: 16 gap + 18 line + 24 outside + 4 sizing reserve.
    // Proposal: 12 gap + 14 line + 8 outside; no duplicated reserve.
    var heightReduction: CGFloat { proposed ? 28 : 0 }
}

enum ChromeCapture {
    case title, footer, footerRight, footerLeftCompact, footerRightCompact
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
        case .footerLeftCompact, .footerRightCompact:
            let width = min(350, size.width)
            let x = self == .footerLeftCompact ? 0 : size.width - width
            return CGRect(x: x, y: size.height - 64, width: width, height: 64)
        }
    }
}

struct InlineHeaderProposal: View {
    let iconURL: URL?
    let appName: String
    let windowName: String
    var opticalBalance = false
    var sizeScale: CGFloat = 1

    var body: some View {
        HStack(spacing: (opticalBalance ? 6 : 8) * sizeScale) {
            Icon(url: iconURL, size: (opticalBalance ? 26 : 20) * sizeScale)
                .environment(\.deckScale, 1).accessibilityHidden(true)
            Text(appName).font(.system(size: 18 * sizeScale, weight: .semibold))
                .lineLimit(1).truncationMode(.middle).layoutPriority(1)
            Text("—").foregroundStyle(.secondary)
            Text(windowName).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
        }
        .font(.system(size: 13 * sizeScale))
        .offset(y: opticalBalance ? 3 : 0)
        .help("\(appName) — \(windowName)")
        .accessibilityElement(children: .combine)
    }
}

struct LargerChromeComparison: View {
    let directory: URL
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("이전 시안 · 상단")
            capture("before-title", width: 700, height: 84)
            Text("새 시안 · 비율은 그대로, 제목과 아이콘 15% 확대")
            capture("after-title", width: 700, height: 84)
            Text("이전 시안 · 하단 양끝")
            corners("before")
            Text("새 시안 · 좌우는 1.4.2 위치, 줄인 아래 여백 유지")
            corners("after")
        }
        .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
        .padding(16).frame(width: 740)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    private func corners(_ name: String) -> some View {
        HStack(spacing: 8) {
            capture("\(name)-left", width: 350, height: 64)
            capture("\(name)-right", width: 350, height: 64)
        }
    }
    private func capture(_ name: String, width: CGFloat, height: CGFloat) -> some View {
        Group {
            if let image = NSImage(contentsOf: directory.appendingPathComponent("chrome-179-\(name).png")) {
                Image(nsImage: image).resizable().frame(width: width, height: height).background(Color.black)
            }
        }
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
