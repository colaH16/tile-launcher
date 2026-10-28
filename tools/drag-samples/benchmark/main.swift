import Foundation
import CoreGraphics

let bounds = CGRect(x: 0, y: 0, width: 1600, height: 900)
@inline(never) func scene(_ count: Int, offset: Int = 0) -> [CGRect] {
    (0..<count).map { i in CGRect(x: (i % 20) * 76 + 8, y: (i / 20) * 16 + 8 + offset, width: 60, height: 12) }
}
@inline(never) func queries(_ controls: [CGRect], _ points: [CGPoint], count: Int) -> Int {
    var accepted = 0
    for i in 0..<count {
        if OverlayDragGeometry.canBegin(at: points[i & 255], bounds: bounds, excluding: controls) { accepted += 1 }
    }
    return accepted
}
@inline(never) func rebuild(_ count: Int, iterations: Int) -> Int {
    var total = 0
    let outer = bounds.insetBy(dx: 4, dy: 4), scroll = bounds.insetBy(dx: 0, dy: 24)
    for i in 0..<iterations {
        let source = scene(count, offset: i % 17)
        let result = source.compactMap { OverlayDragGeometry.clipped($0, to: [outer, scroll]) }
        total += result.count
    }
    return total
}
func stats(_ ns: [Double]) -> [String: Double] {
    let sorted = ns.sorted(), mean = ns.reduce(0,+)/Double(ns.count)
    return ["medianUS": sorted[sorted.count/2]/1000, "p95US": sorted[Int(Double(sorted.count-1)*0.95)]/1000,
            "minUS": sorted[0]/1000, "maxUS": sorted.last!/1000, "meanUS": mean/1000]
}
var rows: [[String: Any]] = [], checksum = 0
for count in [0, 3, 20, 50, 100, 200, 1000] {
    let rects = scene(count)
    var cases: [(String, [CGPoint])] = []
    let empty = (0..<256).map { i in CGPoint(x: 1530 + i % 60, y: 820 + i % 70) }
    cases.append(("fullScanEmptySpace", empty))
    if let first = rects.first, let last = rects.last {
        cases.append(("firstTileHit", (0..<256).map { i in CGPoint(x: first.midX + CGFloat(i % 5), y: first.midY) }))
        cases.append(("lastTileHit", (0..<256).map { i in CGPoint(x: last.midX + CGFloat(i % 5), y: last.midY) }))
    }
    for (name, points) in cases {
        checksum += queries(rects, points, count: 10000) // Warm up.
        var samples: [Double] = []
        for _ in 0..<21 {
            let start = DispatchTime.now().uptimeNanoseconds
            checksum += queries(rects, points, count: 10000)
            samples.append(Double(DispatchTime.now().uptimeNanoseconds-start)/10000)
        }
        var row: [String: Any] = ["rectangles": count, "case": name, "queriesPerBatch": 10000, "batches": 21,
                                 "rectStorageBytes": count * MemoryLayout<CGRect>.stride]
        row["perQuery"] = stats(samples); rows.append(row)
    }
    if count > 0 {
        var samples: [Double] = []
        for _ in 0..<21 {
            let start = DispatchTime.now().uptimeNanoseconds
            checksum += rebuild(count, iterations: 500)
            samples.append(Double(DispatchTime.now().uptimeNanoseconds-start)/500)
        }
        rows.append(["rectangles": count, "case": "buildAndClipAllRects", "rebuildsPerBatch": 500, "batches": 21, "perRebuild": stats(samples)])
    }
}
let data: [String: Any] = ["os": ProcessInfo.processInfo.operatingSystemVersionString,
                         "logicalCPUs": ProcessInfo.processInfo.processorCount,
                         "physicalMemoryBytes": ProcessInfo.processInfo.physicalMemory,
                         "optimization": "swiftc -O -whole-module-optimization",
                         "scope": "actual OverlayDragGeometry CPU geometry only; no SwiftUI anchor resolution, rendering, IPC, or physical dragging",
                         "rows": rows, "checksum": checksum]
let output = try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys])
if CommandLine.arguments.count > 1 { try output.write(to: URL(fileURLWithPath: CommandLine.arguments[1])) }
FileHandle.standardOutput.write(output); print("")
