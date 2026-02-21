import SwiftUI
import SynapseCore

struct HeatmapView: View {
    @Binding var weights: Weights
    @Binding var regions: [Region]
    @Binding var matrix: [[Double]]

    @State private var selected: (row: Int, col: Int)? = nil

    var body: some View {
        GeometryReader { geometry in
            VStack {
                if regions.isEmpty {
                    Text("No regions configured").foregroundColor(.secondary)
                } else {
                    Canvas { context, size in
                        let n = regions.count
                        guard n > 0 else { return }
                        let cellW = size.width / CGFloat(max(1, n))
                        let cellH = size.height / CGFloat(max(1, n))

                        for row in 0..<n {
                            for col in 0..<n {
                                let value = matrix[safe: row]?[safe: col] ?? 0.0
                                let color = colorFor(value: value)
                                let rect = CGRect(x: CGFloat(col) * cellW, y: CGFloat(row) * cellH, width: cellW, height: cellH)
                                context.fill(Path(rect), with: .color(color))

                                if selected?.row == row && selected?.col == col {
                                    context.stroke(Path(rect.insetBy(dx: 2, dy: 2)), with: .color(.primary), lineWidth: 2)
                                }

                                if row == col {
                                    let name = regions[row].name
                                    let text = Text(name)
                                        .font(.system(size: min(12, cellW * 0.14)))
                                        .foregroundColor(.white)
                                    context.draw(text, in: rect.insetBy(dx: 4, dy: 4))
                                }
                            }
                        }
                    }
                    .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                        let n = regions.count
                        let w = geometry.size.width / CGFloat(n)
                        let h = geometry.size.height / CGFloat(n)
                        let col = min(n - 1, max(0, Int(value.location.x / w)))
                        let row = min(n - 1, max(0, Int(value.location.y / h)))
                        selected = (row, col)
                    })
                    .overlay(alignment: .bottom) {
                        if let selected, regions.indices.contains(selected.row), regions.indices.contains(selected.col) {
                            HStack {
                                Text("cell: \(regions[selected.row].name) <-> \(regions[selected.col].name)")
                                Spacer()
                                Text(String(format: "sim: %.3f", matrix[selected.row][selected.col]))
                            }
                            .padding(8)
                            .background(.regularMaterial)
                        }
                    }
                }
            }
        }
    }

    private func colorFor(value: Double) -> Color {
        let v = max(0.0, min(1.0, value))
        if v < 0.5 {
            let t = v / 0.5
            return Color(.sRGB, red: CGFloat(0.0 + t * 1.0), green: CGFloat(0.0 + t * 0.9), blue: CGFloat(0.8 - t * 0.8), opacity: 1.0)
        }
        let t = (v - 0.5) / 0.5
        return Color(.sRGB, red: 1.0, green: CGFloat(0.9 - t * 0.8), blue: 0.0, opacity: 1.0)
    }
}

private extension Array {
    subscript(safe idx: Int) -> Element? {
        (idx >= 0 && idx < count) ? self[idx] : nil
    }
}
