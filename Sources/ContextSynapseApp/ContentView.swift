import SwiftUI
import SynapseCore

struct ContentView: View {
    @EnvironmentObject var vm: AppViewModel
    
    var body: some View {
        HStack(spacing: 16) {
            // Left controls
            VStack(alignment: .leading, spacing: 12) {
                Text("ContextSynapse Matrix Control").font(.title2).bold()
                
                GroupBox("Query & Prompt") {
                    VStack(alignment: .leading) {
                        TextEditor(text: $vm.queryText)
                            .frame(height:100)
                            .overlay(RoundedRectangle(cornerRadius:6).stroke(Color.gray.opacity(0.25)))
                        HStack {
                            Button("Assemble Prompt") { vm.assemblePrompt() }
                            Button("Save Config") { vm.saveConfig() }
                            Button("Reset Defaults") { vm.resetDefaults() }
                        }
                        Text("Assembled Prompt:").font(.caption)
                        ScrollView {
                            Text(vm.assembledPrompt).frame(maxWidth:.infinity, alignment:.leading)
                                .padding(8).background(Color.black.opacity(0.03)).cornerRadius(6)
                        }.frame(height:120)
                    }.padding(8)
                }
                
                GroupBox("Weights (Intents/Tones/Domains)") {
                    VStack {
                        WeightGridView(weights: $vm.weights)
                    }.padding(6)
                }
                
                GroupBox("Fault Injection & Resilience") {
                    VStack(alignment: .leading) {
                        Toggle(isOn: $vm.faultEnabled) { Text("Enable fault injection simulation") }
                        HStack {
                            Slider(value: Binding(
                                get: { vm.faultProbability },
                                set: { new in vm.setFaultProbability(vm.faultEnabled ? new : 0.0) }
                            ), in: 0.0...0.9)
                            Text(String(format: "%.2f", vm.faultProbability)).frame(width:50)
                        }
                        HStack {
                            Button("Disintegrate Sky Plates") { vm.disintegrateSkyPlates() }
                            Text("(safe simulated corruption for resilience testing)").font(.caption).foregroundColor(.secondary)
                        }
                    }.padding(8)
                }
                
                Spacer()
                HStack {
                    Button("Recompute Regions") { vm.recomputeSimilarities() }
                    Spacer()
                    Text("Regions: \(vm.regions.count)")
                }.padding(.top, 6)
            }.frame(minWidth: 420)
            .padding()
            
            Divider()
            
            // Right: heatmap + region similarity
            VStack(spacing: 12) {
                Text("Regional Similarity Heatmap").font(.headline)
                HeatmapView(weights: $vm.weights, regions: $vm.regions, matrix: $vm.similarityMatrix)
                    .frame(minWidth: 420, minHeight: 420)
                    .background(Color(.windowBackgroundColor))
                    .cornerRadius(8)
                    .padding()
                
                GroupBox("Nearest Regions") {
                    VStack(alignment:.leading) {
                        ForEach(vm.regions, id:\.name) { r in
                            HStack {
                                Text(r.name).bold()
                                Spacer()
                                if let (n, s) = vm.nearestMap[r.name] {
                                    Text("\(n): \(String(format: ".3f", s))")
                                } else {
                                    Text("-")
                                }
                            }
                            Divider()
                        }
                    }.padding(8)
                }
                Spacer()
            }.padding()
        }
    }
}
