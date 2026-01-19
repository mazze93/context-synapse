import SwiftUI
import SynapseCore

@main
struct ContextSynapseAppMain: App {
    @StateObject private var vm = AppViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vm)
                .frame(minWidth: 900, minHeight: 640)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

// Simple app view model bridging core to UI
final class AppViewModel: ObservableObject {
    private let core = SynapseCore()
    
    @Published var weights: Weights
    @Published var regions: [Region]
    @Published var similarityMatrix: [[Double]] = []
    @Published var nearestMap: [String: (String, Double)] = [:]
    @Published var assembledPrompt: String = ""
    @Published var queryText: String = ""
    @Published var faultEnabled: Bool = false
    @Published var faultProbability: Double = 0.0
    
    init() {
        self.weights = core.loadOrCreateDefaultWeights()
        self.regions = core.loadOrSeedRegions()
        self.faultProbability = core.faultProbability
        recomputeSimilarities()
    }
    
    func recomputeSimilarities() {
        let (matrix, nearest) = core.computeRegionSimilarities(regions)
        DispatchQueue.main.async {
            self.similarityMatrix = matrix
            self.nearestMap = nearest
        }
    }
    
    func assemblePrompt() {
        // pick currently highest scoring keys for display
        let intent = core.weightedPick(weights.intents) ?? weights.intents.keys.sorted().first ?? "Create"
        let tone = core.weightedPick(weights.tones) ?? weights.tones.keys.sorted().first ?? "Concise"
        let domain = core.weightedPick(weights.domains) ?? weights.domains.keys.sorted().first ?? "Work"
        let p = "[\(tone)] [\(intent)] [\(domain)]: \(queryText)"
        assembledPrompt = p
        
        // log a run
        let run = SynapseCore.RunLog(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            input: queryText,
            chosenIntent: intent,
            chosenTone: tone,
            chosenDomain: domain,
            assembledPrompt: p,
            context: ["ui":"macapp"]
        )
        core.logRun(run)
    }
    
    func saveConfig() {
        core.saveWeights(weights)
        core.saveRegions(regions)
    }
    
    func resetDefaults() {
        self.weights = core.loadOrCreateDefaultWeights()
        self.regions = core.loadOrSeedRegions()
        recomputeSimilarities()
    }
    
    // toggle fault injection and set core probability
    func setFaultProbability(_ p: Double) {
        self.faultProbability = max(0.0, min(1.0, p))
        core.faultProbability = self.faultProbability
    }
    
    // intentionally disintegrate regions for resilience testing
    func disintegrateSkyPlates() {
        var regs = regions
        core.maybeInjectFaults(into: &regs)
        self.regions = regs
        recomputeSimilarities()
    }
    
    // apply manual feedback (UI)
    func applyFeedback(chosenIntent: String, chosenTone: String, chosenDomain: String, positive: Bool) {
        core.applyFeedbackUpdate(chosenIntent: chosenIntent, chosenTone: chosenTone, chosenDomain: chosenDomain, positive: positive)
        self.weights = core.loadOrCreateDefaultWeights()
    }
}
