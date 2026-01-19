//
// HeatmapView.swift
// Context Synapse
//

import SwiftUI

struct HeatmapView: View {
    let data: [[Double]]
    let rowLabels: [String]
    let columnLabels: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weight Heatmap Visualization")
                .font(.headline)
            
            ScrollView([.horizontal, .vertical]) {
                VStack(spacing: 0) {
                    // Column headers
                    HStack(spacing: 0) {
                        Color.clear
                            .frame(width: 100)
                        
                        ForEach(0..<columnLabels.count, id: \.self) { col in
                            Text(columnLabels[col])
                                .frame(width: 60)
                                .font(.caption2)
                                .rotationEffect(.degrees(-45))
                                .padding(.vertical, 4)
                        }
                    }
                    
                    // Heatmap grid
                    ForEach(0..<data.count, id: \.self) { row in
                        HStack(spacing: 0) {
                            Text(rowLabels[row])
                                .frame(width: 100, alignment: .leading)
                                .font(.caption)
                            
                            ForEach(0..<data[row].count, id: \.self) { col in
                                Rectangle()
                                    .fill(colorForValue(data[row][col]))
                                    .frame(width: 60, height: 40)
                                    .border(Color.gray.opacity(0.3), width: 0.5)
                                    .overlay(
                                        Text(String(format: "%.2f", data[row][col]))
                                            .font(.caption2)
                                            .foregroundColor(textColorForValue(data[row][col]))
                                    )
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }
    
    private func colorForValue(_ value: Double) -> Color {
        let normalized = min(max(value, 0.0), 1.0)
        // Blue (low) to Red (high) gradient
        return Color(red: normalized, green: 0.3 * (1.0 - abs(normalized - 0.5)), blue: 1.0 - normalized)
    }
    
    private func textColorForValue(_ value: Double) -> Color {
        // Use white text for dark backgrounds, black for light
        return value > 0.5 ? .white : .black
    }
}
