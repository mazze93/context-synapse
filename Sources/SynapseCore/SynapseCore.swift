import Foundation

// MARK: - Prior (Bayesian Beta distribution)
public struct Prior: Codable, Equatable {
    public var alpha: Double
    public var beta: Double
    
    public init(alpha: Double = 1.0, beta: Double = 1.0) {
        self.alpha = alpha
        self.beta = beta
    }
    
    public func probability() -> Double {
        let s = alpha + beta
        return s > 0 ? alpha / s : 0.5
    }
}

// MARK: - Priors collection
public struct Priors: Codable, Equatable {
    public var intents: [String: Prior]
    public var tones: [String: Prior]
    public var domains: [String: Prior]
    
    public init(intents: [String:Prior] = [:], tones: [String:Prior] = [:], domains: [String:Prior] = [:]) {
        self.intents = intents
        self.tones = tones
        self.domains = domains
    }
}

// MARK: - Weights configuration
public struct Weights: Codable, Equatable {
    public var intents: [String: Double]
    public var tones: [String: Double]
    public var domains: [String: Double]
    public var triggers: [String: [String: Double]]
    public var priors: Priors
    
    public init(intents: [String:Double], tones: [String:Double], domains: [String:Double], triggers: [String:[String:Double]], priors: Priors = Priors()) {
        self.intents = intents
        self.tones = tones
        self.domains = domains
        self.triggers = triggers
        self.priors = priors
    }
}

// MARK: - Region
public struct Region: Codable, Equatable {
    public var name: String
    public var vector: [Double]
    
    public init(name: String, vector: [Double]) {
        self.name = name
        self.vector = vector
    }
}

// MARK: - SynapseCore class
public class SynapseCore {
    let fm = FileManager.default
    public let appSupport: URL
    public let configURL: URL
    public let regionsURL: URL
    public let logDir: URL
    
    /// Fault injection probability (0.0 by default). Can be set via env var CONTEXT_SYNAPSE_FAULT_PROB
    public var faultProbability: Double = 0.0
    
    public init(folderName: String = "ContextSynapse") {
        let home = fm.homeDirectoryForCurrentUser
        self.appSupport = home.appendingPathComponent("Library").appendingPathComponent("Application Support").appendingPathComponent(folderName)
        self.configURL = appSupport.appendingPathComponent("config.json")
        self.regionsURL = appSupport.appendingPathComponent("regions.json")
        self.logDir = appSupport.appendingPathComponent("logs")
        try? fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try? fm.createDirectory(at: logDir, withIntermediateDirectories: true)
        // init faultProbability from environment (useful for testing)
        if let env = ProcessInfo.processInfo.environment["CONTEXT_SYNAPSE_FAULT_PROB"], let v = Double(env) {
            self.faultProbability = max(0.0, min(1.0, v))
        }
        // seed defaults if missing
        _ = loadOrCreateDefaultWeights()
        _ = loadOrSeedRegions()
    }
    
    // MARK: - Config I/O
    public func loadOrCreateDefaultWeights() -> Weights {
        if let data = try? Data(contentsOf: configURL), let w = try? JSONDecoder().decode(Weights.self, from: data) {
            return w
        }
        let intents = ["Summarize":1.0,"Create":1.0,"Analyze":1.0,"Brainstorm":1.0,"ActionableSteps":1.0]
        let tones = ["Concise":1.0,"Technical":1.0,"Casual":1.0,"Persuasive":1.0,"Creative":1.0]
        let domains = ["Work":1.0,"Personal":1.0,"GameDesign":1.0,"Marketing":1.0,"Writing":1.0]
        let triggers: [String:[String:Double]] = [
            "app.Mail": ["Create":1.6, "ActionableSteps":1.2],
            "app.Notes": ["Create":1.7, "Creative":1.4],
            "time.morning": ["Analyze":1.25],
            "focus.DoNotDisturb": ["Concise":1.6]
        ]
        var priors = Priors()
        priors.intents = Dictionary(uniqueKeysWithValues: intents.keys.map { ($0, Prior()) })
        priors.tones = Dictionary(uniqueKeysWithValues: tones.keys.map { ($0, Prior()) })
        priors.domains = Dictionary(uniqueKeysWithValues: domains.keys.map { ($0, Prior()) })
        let defaults = Weights(intents: intents, tones: tones, domains: domains, triggers: triggers, priors: priors)
        saveWeights(defaults)
        return defaults
    }
    
    public func saveWeights(_ w: Weights) {
        if let data = try? JSONEncoder().encode(w) {
            try? data.write(to: configURL, options: .atomic)
        }
    }
    
    // MARK: - Regions
    public func loadOrSeedRegions() -> [Region] {
        if let d = try? Data(contentsOf: regionsURL), let arr = try? JSONDecoder().decode([Region].self, from: d) {
            return arr
        }
        let defaults = loadOrCreateDefaultWeights()
        let intentKeys = defaults.intents.keys.sorted()
        let toneKeys = defaults.tones.keys.sorted()
        let domainKeys = defaults.domains.keys.sorted()
        func vectorFor(baseScale: Double) -> [Double] {
            var v = [Double]()
            v += intentKeys.map { _ in baseScale }
            v += toneKeys.map { _ in baseScale * 0.9 }
            v += domainKeys.map { _ in baseScale * 1.1 }
            return v
        }
        let regions = [
            Region(name: "NorthAmerica", vector: vectorFor(baseScale: 1.0)),
            Region(name: "EMEA", vector: vectorFor(baseScale: 0.9)),
            Region(name: "APAC", vector: vectorFor(baseScale: 1.05))
        ]
        if let data = try? JSONEncoder().encode(regions) {
            try? data.write(to: regionsURL, options: .atomic)
        }
        return regions
    }
    
    public func saveRegions(_ regions: [Region]) {
        if let d = try? JSONEncoder().encode(regions) {
            try? d.write(to: regionsURL, options: .atomic)
        }
    }
    
    // MARK: - Trigger application and picking
    public func applyTriggers(base: [String:Double], triggers: [String:[String:Double]], activeKeys: [String]) -> [String:Double] {
        var result = base
        for key in activeKeys {
            if let tmap = triggers[key] {
                for (k, boost) in tmap {
                    result[k] = (result[k] ?? 0.0) * boost
                }
            }
        }
        return result
    }
    
    public func weightedPick(_ map: [String:Double]) -> String? {
        let entries = Array(map)
        let total = entries.map { max(0.0,$0.value) }.reduce(0, +)
        if total <= 0 { return entries.first?.key }
        let r = Double.random(in: 0..<total)
        var cumulative = 0.0
        for (k, v) in entries {
            cumulative += max(0.0, v)
            if r < cumulative { return k }
        }
        return entries.first?.key
    }
    
    /// map a Beta prior to a weight range
    public func mapPriorToWeight(_ prior: Prior, minW: Double = 0.1, maxW: Double = 3.0) -> Double {
        let p = prior.probability()
        return minW + p * (maxW - minW)
    }
    
    /// call this to apply feedback and update priors/weights (Bayesian updates via Beta)
    public func applyFeedbackUpdate(chosenIntent: String, chosenTone: String, chosenDomain: String, positive: Bool) {
        var w = loadOrCreateDefaultWeights()
        func bump(dictKey: String, in map: inout [String:Prior]) {
            if map[dictKey] == nil { map[dictKey] = Prior() }
            if positive {
                map[dictKey]!.alpha += 1.0
            } else {
                map[dictKey]!.beta += 1.0
            }
        }
        bump(dictKey: chosenIntent, in: &w.priors.intents)
        bump(dictKey: chosenTone, in: &w.priors.tones)
        bump(dictKey: chosenDomain, in: &w.priors.domains)
        // recompute numeric weights from priors (keeps alignement)
        for (k, prior) in w.priors.intents { w.intents[k] = mapPriorToWeight(prior) }
        for (k, prior) in w.priors.tones { w.tones[k] = mapPriorToWeight(prior) }
        for (k, prior) in w.priors.domains { w.domains[k] = mapPriorToWeight(prior) }
        saveWeights(w)
    }
    
    // MARK: - Robust cosine similarity
    public func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        // tolerate mismatched lengths by computing over the shared prefix
        let n = min(a.count, b.count)
        if n == 0 { return 0.0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<n {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        if na <= 0 || nb <= 0 { return 0.0 }
        return dot / (sqrt(na) * sqrt(nb))
    }
    
    /// Return a similarity matrix and nearest neighbor map
    public func computeRegionSimilarities(regionsIn: [Region]) -> (matrix: [[Double]], nearest: [String:(name:String, score:Double)]) {
        var regions = regionsIn
        // allow fault injection to slightly corrupt region vectors (simulates disintegration)
        maybeInjectFaults(into: &regions)
        let n = regions.count
        var matrix = Array(repeating: Array(repeating: 0.0, count: n), count: n)
        var nearest = [String:(String, Double)]()
        for i in 0..<n {
            var bestScore = -1.0
            var bestName = ""
            for j in 0..<n {
                let s = cosineSimilarity(regions[i].vector, regions[j].vector)
                matrix[i][j] = s
                if i != j && s > bestScore {
                    bestScore = s
                    bestName = regions[j].name
                }
            }
            nearest[regions[i].name] = (bestName, max(0, bestScore))
        }
        // small, deterministic degradation if faultProbability is configured moderately (helps testing resilience)
        if self.faultProbability > 0.0 && self.faultProbability <= 0.5 {
            for i in 0..<n {
                for j in 0..<n {
                    matrix[i][j] = matrix[i][j] * (1.0 - self.faultProbability * 0.25)
                }
            }
        }
        return (matrix, nearest)
    }
    
    /// Fault injection: randomly corrupt up to a small fraction of elements in region vectors.
    /// Controlled by self.faultProbability. Default is 0.0 (no faults).
    public func maybeInjectFaults(into regions: inout [Region]) {
        guard self.faultProbability > 0.0 else { return }
        for idx in regions.indices {
            if Double.random(in: 0...1) < self.faultProbability {
                // corrupt this region: either add noise, truncate, or zero a slice
                var v = regions[idx].vector
                let choice = Int.random(in: 0...2)
                if choice == 0 && !v.isEmpty {
                    // add small gaussian noise
                    for i in 0..<v.count {
                        let noise = Double.random(in: -0.02...0.02) * self.faultProbability
                        v[i] = v[i] + noise
                    }
                } else if choice == 1 && v.count > 2 {
                    // truncate a random slice
                    let cutFrom = Int.random(in: 0..<v.count-1)
                    let cutLen = Int.random(in: 1...max(1, v.count-cutFrom))
                    for i in cutFrom..<cutFrom+cutLen {
                        v[i] = 0.0
                    }
                } else if choice == 2 && !v.isEmpty {
                    // scale down a random subset
                    let cnt = max(1, Int(Double(v.count) * 0.08))
                    for _ in 0..<cnt {
                        let i = Int.random(in: 0..<v.count)
                        v[i] *= Double.random(in: 0.0...0.6)
                    }
                }
                regions[idx].vector = v
            }
        }
    }
    
    /// canonical vector builder for UI/regeneration
    public func canonicalVector(for weights: Weights, scale: Double = 1.0) -> [Double] {
        let intents = weights.intents.keys.sorted().map { weights.intents[$0] ?? 0.0 }
        let tones = weights.tones.keys.sorted().map { weights.tones[$0] ?? 0.0 }
        let domains = weights.domains.keys.sorted().map { weights.domains[$0] ?? 0.0 }
        return (intents + tones + domains).map { $0 * scale }
    }
    
    // MARK: - Logging
    public struct RunLog: Codable {
        public let timestamp: String
        public let input: String
        public let chosenIntent: String
        public let chosenTone: String
        public let chosenDomain: String
        public let assembledPrompt: String
        public let context: [String:String]
        
        public init(timestamp: String, input: String, chosenIntent: String, chosenTone: String, chosenDomain: String, assembledPrompt: String, context: [String:String]) {
            self.timestamp = timestamp
            self.input = input
            self.chosenIntent = chosenIntent
            self.chosenTone = chosenTone
            self.chosenDomain = chosenDomain
            self.assembledPrompt = assembledPrompt
            self.context = context
        }
    }
    
    public func logRun(_ run: RunLog) {
        let iso = ISO8601DateFormatter().string(from: Date())
        let file = logDir.appendingPathComponent("run-\(iso).json")
        if let d = try? JSONEncoder().encode(run) {
            try? d.write(to: file, options: .atomic)
        }
    }
}
