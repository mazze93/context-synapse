//
// WeightGridView.swift
// Context Synapse
//

import SwiftUI

struct WeightGridView: View {
    let weights: [[Double]]
    let labels: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bayesian Prior Weights")
                .font(.headline)
            
            ScrollView([.horizontal, .vertical]) {
                VStack(spacing: 4) {
                    ForEach(0..<weights.count, id: \.self) { row in
                        HStack(spacing: 4) {
                            Text(labels[row])
                                .frame(width: 100, alignment: .leading)
                                .font(.caption)
                            
                            ForEach(0..<weights[row].count, id: \.self) { col in
                                Text(String(format: "%.2f", weights[row][col]))
                                    .frame(width: 60)
                                    .padding(4)
                                    .background(colorForWeight(weights[row][col]))
                                    .cornerRadius(4)
                                    .font(.caption)
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }
    
    private func colorForWeight(_ weight: Double) -> Color {
        let normalized = min(max(weight, 0.0), 1.0)
        return Color(red: normalized, green: 0.5, blue: 1.0 - normalized)
    }
}
