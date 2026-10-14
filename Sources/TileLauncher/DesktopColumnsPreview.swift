import SwiftUI
import DeckCore

/// R148 comparison only. No live inventory, ordering, or keyboard behavior.
struct DesktopColumnsPreviewData {
    let visible: [[Int]]
    let other: [[Int]]
    let applications: [Int]
}

struct DesktopColumnsPreview<Tile: View>: View {
    let data: DesktopColumnsPreviewData
    let sizes: [RecentTileSize]
    let width: CGFloat
    var expanded = false
    let tile: (Int, RecentTileSize) -> Tile
    private let gap: CGFloat = 8
    private let gutter: CGFloat = 24
    private var columnWidth: CGFloat { (width - gutter) / 2 }
    private var micro: CGFloat { (columnWidth - gap * 5) / 6 }

    var body: some View {
        HStack(alignment: .top, spacing: gutter) {
            column(title: "보이는 데스크탑", groups: data.visible, applications: [])
            column(title: "다른 데스크탑", groups: data.other, applications: data.applications)
        }.frame(width: width, alignment: .topLeading)
    }

    private func column(title: String, groups: [[Int]], applications: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            if expanded {
                contents(groups: groups, applications: applications)
            } else {
                ScrollView(.vertical) { contents(groups: groups, applications: applications) }
                    .scrollIndicators(.visible)
            }
        }.frame(width: columnWidth, alignment: .topLeading)
    }

    private func contents(groups: [[Int]], applications: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(groups.indices, id: \.self) { index in group(groups[index]) }
            if !applications.isEmpty {
                Text("창 없는 앱").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary).padding(.top, 4)
                group(applications)
            }
        }.frame(width: columnWidth, alignment: .topLeading)
    }

    private func group(_ indices: [Int]) -> some View {
        let placements = RecentTileArrangement.place(sizes: indices.map { sizes[$0] }, columns: 6)
        let bottom = placements.map { $0.row + $0.height }.max() ?? 0
        return ZStack(alignment: .topLeading) {
            ForEach(placements, id: \.index) { place in
                let index = indices[place.index]
                tile(index, sizes[index])
                    .frame(width: CGFloat(place.width) * micro + CGFloat(place.width - 1) * gap,
                           height: CGFloat(place.height) * micro + CGFloat(place.height - 1) * gap)
                    .offset(x: CGFloat(place.column) * (micro + gap), y: CGFloat(place.row) * (micro + gap))
            }
        }.frame(width: columnWidth, height: CGFloat(bottom) * (micro + gap) - gap, alignment: .topLeading)
    }
}
