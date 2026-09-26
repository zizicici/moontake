import CoreGraphics

/// Computes labels in viewport coordinates, independent of image zoom/rotation.
enum MoonAtlasLabelLayout {
    struct Placement {
        let index: Int
        let anchor: CGPoint
        let frame: CGRect
        let endpoint: CGPoint
    }

    static func arrange(_ anchors: [CGPoint], in bounds: CGRect, labelSize: CGSize) -> [Placement] {
        let margin: CGFloat = 8
        let height = max(44, labelSize.height)
        let gap: CGFloat = 4
        let width = min(labelSize.width, bounds.width / 2 - margin * 2)
        let capacity = max(0, Int((bounds.height - margin * 2 + gap) / (height + gap)))
        guard capacity > 0, width > 0 else { return [] }
        var placements: [Placement] = []
        for right in [false, true] {
            var indices = anchors.indices.filter { (anchors[$0].x >= bounds.midX) == right }
                .sorted { anchors[$0].y == anchors[$1].y ? $0 < $1 : anchors[$0].y < anchors[$1].y }
            // When the viewport is very short, keep an even spread of features
            // rather than squeezing labels or reducing their touch targets.
            if indices.count > capacity {
                indices = (0..<capacity).map { indices[Int((Double($0) + 0.5) * Double(indices.count) / Double(capacity))] }
            }
            guard !indices.isEmpty else { continue }
            let ys = spacedCenters(indices.map { anchors[$0].y }, height: height + gap,
                                   minimum: bounds.minY + margin + height / 2,
                                   maximum: bounds.maxY - margin - height / 2)
            let x = right ? bounds.maxX - margin - width : bounds.minX + margin
            let frames = ys.map { CGRect(x: x, y: $0 - height / 2, width: width, height: height) }
            let endpoints = frames.map { CGPoint(x: right ? $0.minX : $0.maxX, y: $0.midY) }
            let assignment = minimumLengthAssignment(indices.map { anchors[$0] }, endpoints)
            for (row, index) in indices.enumerated() {
                let column = assignment[row]
                placements.append(Placement(index: index, anchor: anchors[index], frame: frames[column], endpoint: endpoints[column]))
            }
        }
        return placements
    }

    /// Isotonic regression spreads crowded labels in both directions, minimizing
    /// vertical displacement while maintaining the minimum touch-target spacing.
    private static func spacedCenters(_ desired: [CGFloat], height: CGFloat, minimum: CGFloat, maximum: CGFloat) -> [CGFloat] {
        var blocks: [(sum: CGFloat, count: Int)] = []
        for (index, y) in desired.enumerated() {
            blocks.append((y - CGFloat(index) * height, 1))
            while blocks.count > 1 {
                let a = blocks[blocks.count - 2], b = blocks[blocks.count - 1]
                guard a.sum / CGFloat(a.count) > b.sum / CGFloat(b.count) else { break }
                blocks.removeLast(2)
                blocks.append((a.sum + b.sum, a.count + b.count))
            }
        }
        let upper = maximum - CGFloat(desired.count - 1) * height
        var result: [CGFloat] = []
        for block in blocks {
            let base = max(minimum, min(upper, block.sum / CGFloat(block.count)))
            for _ in 0..<block.count { result.append(base + CGFloat(result.count) * height) }
        }
        return result
    }

    /// Hungarian assignment, O(n³), with Euclidean leader length as cost.
    /// Crossing straight leaders cannot be optimal: swapping their endpoints
    /// makes the total length strictly shorter. Each side occupies its own half
    /// of the viewport, so the two independently matched groups cannot cross.
    /// Unlike sorting by Y alone, this also handles anchors at different X values.
    private static func minimumLengthAssignment(_ anchors: [CGPoint], _ endpoints: [CGPoint]) -> [Int] {
        let count = anchors.count
        let costs = anchors.map { anchor in endpoints.map { hypot(anchor.x - $0.x, anchor.y - $0.y) } }
        var rowPotential = [CGFloat](repeating: 0, count: count + 1)
        var columnPotential = rowPotential
        var matching = [Int](repeating: 0, count: count + 1)
        var previous = matching
        for row in 1...count {
            matching[0] = row
            var column = 0
            var minimum = [CGFloat](repeating: .infinity, count: count + 1)
            var used = [Bool](repeating: false, count: count + 1)
            repeat {
                used[column] = true
                let currentRow = matching[column]
                var delta = CGFloat.infinity, nextColumn = 0
                for candidate in 1...count where !used[candidate] {
                    let cost = costs[currentRow - 1][candidate - 1] - rowPotential[currentRow] - columnPotential[candidate]
                    if cost < minimum[candidate] { minimum[candidate] = cost; previous[candidate] = column }
                    if minimum[candidate] < delta { delta = minimum[candidate]; nextColumn = candidate }
                }
                for candidate in 0...count {
                    if used[candidate] {
                        rowPotential[matching[candidate]] += delta
                        columnPotential[candidate] -= delta
                    } else { minimum[candidate] -= delta }
                }
                column = nextColumn
            } while matching[column] != 0
            repeat {
                let next = previous[column]
                matching[column] = matching[next]
                column = next
            } while column != 0
        }
        var result = [Int](repeating: 0, count: count)
        for column in 1...count { result[matching[column] - 1] = column - 1 }
        return result
    }
}
