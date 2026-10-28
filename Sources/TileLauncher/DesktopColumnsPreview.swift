#if TILE_LAUNCHER_DIAGNOSTICS
import SwiftUI
import DeckCore

/// R148–R153 comparisons only. No live inventory, ordering, or keyboard behavior.
struct DesktopColumnsPreviewData {
    struct Column {
        let title: String
        let modules: Int
        let groups: [[Int]]
        var applications: [Int] = []
    }
    let columns: [Column]
    var referenceModules: Int? = nil
    var relaxedSpacing = false
    var fixedModule: CGFloat? = nil

    var preferredWidth: CGFloat? {
        guard let unit = fixedModule else { return nil }
        return columns.reduce(CGFloat(0)) { $0 + CGFloat($1.modules) * unit + CGFloat($1.modules - 1) * 8 }
            + CGFloat(max(0, columns.count - 1)) * 24
    }

    /// Preview proposal: fit each column's widest app group, cap at four modules,
    /// then wrap excess followers vertically. App-only tiles use at most three.
    func fittingGroups(sizes: [RecentTileSize], module: CGFloat) -> Self {
        let fitted = columns.map { column in
            let groupWidth = column.groups.map { indices -> Int in
                var width = 0, pendingSmall = false
                for index in indices {
                    let size = sizes[index]
                    if size == .application {
                        if !pendingSmall { width += 1 }
                        pendingSmall.toggle()
                    } else {
                        width += size.width
                        pendingSmall = false
                    }
                }
                return width
            }.max() ?? 2
            let applicationWidth = min(3, (column.applications.count + 1) / 2)
            return Column(title: column.title, modules: max(2, min(4, max(groupWidth, applicationWidth))),
                          groups: column.groups, applications: column.applications)
        }
        var result = Self(columns: fitted, referenceModules: referenceModules ?? 12)
        result.fixedModule = module
        result.relaxedSpacing = relaxedSpacing
        return result
    }

    init(visible: [[Int]], other: [[Int]], applications: [Int]) {
        columns = [Column(title: "보이는 데스크탑", modules: 6, groups: visible),
                   Column(title: "다른 데스크탑", modules: 6, groups: other, applications: applications)]
    }

    init(columns: [Column], referenceModules: Int) {
        self.columns = columns
        self.referenceModules = referenceModules
    }
}

struct DesktopColumnsPreview<Tile: View>: View {
    let data: DesktopColumnsPreviewData
    let sizes: [RecentTileSize]
    let width: CGFloat
    var expanded = false
    let tile: (Int, RecentTileSize) -> Tile
    private let gap: CGFloat = 8
    private var micro: CGFloat {
        if let unit = data.fixedModule { return unit }
        if let modules = data.referenceModules {
            return (width - CGFloat(modules - 1) * gap) / CGFloat(modules)
        }
        let modules = data.columns.map(\.modules).reduce(0, +)
        let insideGaps = modules - data.columns.count
        return (width - CGFloat(data.columns.count - 1) * 24 - CGFloat(insideGaps) * gap) / CGFloat(modules)
    }
    private func columnWidth(_ modules: Int) -> CGFloat { CGFloat(modules) * micro + CGFloat(modules - 1) * gap }
    private var gutter: CGFloat {
        let total = data.columns.map { columnWidth($0.modules) }.reduce(0, +)
        return (width - total) / CGFloat(max(1, data.columns.count - 1))
    }

    var body: some View {
        HStack(alignment: .top, spacing: gutter) {
            ForEach(data.columns.indices, id: \.self) { index in column(data.columns[index]) }
        }.frame(width: width, alignment: .topLeading)
    }

    private func column(_ column: DesktopColumnsPreviewData.Column) -> some View {
        VStack(alignment: .leading, spacing: data.relaxedSpacing ? 16 : 12) {
            Text(column.title).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(data.fixedModule == nil ? Color.secondary : Color.primary)
            if expanded {
                contents(column)
            } else {
                ScrollView(.vertical) { contents(column) }
                    .scrollIndicators(.visible)
            }
        }.frame(width: columnWidth(column.modules), alignment: .topLeading)
    }

    private func contents(_ column: DesktopColumnsPreviewData.Column) -> some View {
        VStack(alignment: .leading, spacing: data.relaxedSpacing ? 20 : 12) {
            ForEach(column.groups.indices, id: \.self) { index in group(column.groups[index], modules: column.modules) }
            if !column.applications.isEmpty {
                Text("창 없는 앱").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary).padding(.top, 4)
                group(column.applications, modules: column.modules)
            }
        }.frame(width: columnWidth(column.modules), alignment: .topLeading)
    }

    private struct Placement {
        let index: Int
        let row: Int
        let column: Int
        let size: RecentTileSize
    }

    // The production packer intentionally reserves at least four modules.
    // This comparison also supports three, without changing that live policy.
    private func placements(_ indices: [Int], modules: Int) -> [Placement] {
        var band = 0, column = 0
        var pendingSmall: Int?
        return indices.map { index in
            let size = sizes[index]
            precondition(size.width <= modules)
            if size == .application, let pending = pendingSmall {
                pendingSmall = nil
                return Placement(index: index, row: band + 1, column: pending, size: size)
            }
            pendingSmall = nil
            if column + size.width > modules { band += 2; column = 0 }
            let result = Placement(index: index, row: band, column: column, size: size)
            if size == .application { pendingSmall = column }
            column += size.width
            return result
        }
    }

    private func group(_ indices: [Int], modules: Int) -> some View {
        let placements = placements(indices, modules: modules)
        let bottom = placements.map { $0.row + $0.size.height }.max() ?? 0
        return ZStack(alignment: .topLeading) {
            ForEach(placements, id: \.index) { place in
                tile(place.index, place.size)
                    .frame(width: CGFloat(place.size.width) * micro + CGFloat(place.size.width - 1) * gap,
                           height: CGFloat(place.size.height) * micro + CGFloat(place.size.height - 1) * gap)
                    .offset(x: CGFloat(place.column) * (micro + gap), y: CGFloat(place.row) * (micro + gap))
            }
        }.frame(width: columnWidth(modules), height: CGFloat(bottom) * (micro + gap) - gap, alignment: .topLeading)
    }
}
#endif
