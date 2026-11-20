import CoreGraphics

/// Squarified treemap layout (Bruls, Huizing & van Wijk, 2000).
/// Returns one rectangle per weight, in input order; areas are proportional to the weights
/// and aspect ratios are kept close to 1 so icons stay legible.
public enum Treemap {
    public static func layout(weights: [Double], in rect: CGRect) -> [CGRect] {
        guard !weights.isEmpty, rect.width > 0, rect.height > 0 else { return weights.map { _ in .zero } }
        let total = weights.reduce(0) { $0 + max(0, $1) }
        guard total > 0 else { return weights.map { _ in .zero } }

        // Work on items sorted by size (the algorithm needs descending order), then restore order.
        let scale = Double(rect.width * rect.height) / total
        let order = weights.indices.sorted { weights[$0] > weights[$1] }
        let areas = order.map { max(0, weights[$0]) * scale }

        var result = [CGRect](repeating: .zero, count: weights.count)
        var remaining = rect
        var row: [Int] = [] // positions in `order`
        var index = 0

        func worst(_ row: [Int], side: Double) -> Double {
            let values = row.map { areas[$0] }
            let sum = values.reduce(0, +)
            guard sum > 0, let maxV = values.max(), let minV = values.min(), minV > 0 else { return .infinity }
            let s2 = side * side
            return max(s2 * maxV / (sum * sum), (sum * sum) / (s2 * minV))
        }

        func place(_ row: [Int]) {
            let sum = row.reduce(0) { $0 + areas[$1] }
            guard sum > 0 else { return }
            if remaining.width >= remaining.height {
                // Column on the left
                let width = CGFloat(sum) / remaining.height
                var y = remaining.minY
                for i in row {
                    let h = CGFloat(areas[i]) / width
                    result[order[i]] = CGRect(x: remaining.minX, y: y, width: width, height: h)
                    y += h
                }
                remaining = CGRect(x: remaining.minX + width, y: remaining.minY,
                                   width: max(0, remaining.width - width), height: remaining.height)
            } else {
                // Row on the top
                let height = CGFloat(sum) / remaining.width
                var x = remaining.minX
                for i in row {
                    let w = CGFloat(areas[i]) / height
                    result[order[i]] = CGRect(x: x, y: remaining.minY, width: w, height: height)
                    x += w
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + height,
                                   width: remaining.width, height: max(0, remaining.height - height))
            }
        }

        while index < areas.count {
            let side = Double(min(remaining.width, remaining.height))
            let candidate = row + [index]
            if row.isEmpty || worst(candidate, side: side) <= worst(row, side: side) {
                row = candidate
                index += 1
            } else {
                place(row)
                row = []
            }
        }
        if !row.isEmpty { place(row) }
        return result
    }
}
