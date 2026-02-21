import SwiftUI
import SynapseCore

struct WeightGridView: View {
    @Binding var weights: Weights

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Intents").font(.subheadline).bold()
                    ForEach(weights.intents.keys.sorted(), id: \.self) { key in
                        HStack {
                            Text(key).frame(width: 120, alignment: .leading)
                            Slider(value: Binding(
                                get: { weights.intents[key] ?? 1.0 },
                                set: { weights.intents[key] = $0 }
                            ), in: 0.1...3.0)
                            Text(String(format: "%.2f", weights.intents[key] ?? 1.0)).frame(width: 50)
                        }
                    }
                }
                VStack(alignment: .leading) {
                    Text("Tones").font(.subheadline).bold()
                    ForEach(weights.tones.keys.sorted(), id: \.self) { key in
                        HStack {
                            Text(key).frame(width: 120, alignment: .leading)
                            Slider(value: Binding(
                                get: { weights.tones[key] ?? 1.0 },
                                set: { weights.tones[key] = $0 }
                            ), in: 0.1...3.0)
                            Text(String(format: "%.2f", weights.tones[key] ?? 1.0)).frame(width: 50)
                        }
                    }
                }
                VStack(alignment: .leading) {
                    Text("Domains").font(.subheadline).bold()
                    ForEach(weights.domains.keys.sorted(), id: \.self) { key in
                        HStack {
                            Text(key).frame(width: 120, alignment: .leading)
                            Slider(value: Binding(
                                get: { weights.domains[key] ?? 1.0 },
                                set: { weights.domains[key] = $0 }
                            ), in: 0.1...3.0)
                            Text(String(format: "%.2f", weights.domains[key] ?? 1.0)).frame(width: 50)
                        }
                    }
                }
            }
        }
    }
}
