import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Utility: stderr helper
private var standardError = FileHandle.standardError

extension FileHandle: TextOutputStream {
    public func write(_ string: String) {
        if let data = string.data(using: .utf8) {
            try? write(contentsOf: data)
        }
    }
}

// MARK: - AI Platform Integration

/// Protocol for AI platform clients
public protocol AIClient {
    func sendPrompt(_ prompt: String, completion: @escaping (Result<String, Error>) -> Void)
}

/// Configuration for AI platforms
public struct AIConfig: Codable {
    public let provider: String  // "openai" or "anthropic"
    public let apiKey: String
    public let model: String
    public let maxTokens: Int
    
    public init(provider: String, apiKey: String, model: String, maxTokens: Int = 1000) {
        self.provider = provider
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
    }
}

/// Base implementation for HTTP-based AI clients with security and error handling
class BaseHTTPAIClient {
    private let session: URLSession
    
    init(timeoutInterval: TimeInterval = 30.0) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeoutInterval
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = URLSession(configuration: config)
    }
    
    func sendRequest(
        url: URL,
        headers: [String: String],
        body: [String: Any],
        responseParser: @escaping ([String: Any]) -> String?,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to serialize request"])))
            return
        }
        request.httpBody = httpBody
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            // Validate HTTP status code
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                let message = "HTTP error: \(httpResponse.statusCode)"
                completion(.failure(NSError(domain: "AIClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: message])))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = responseParser(json) else {
                completion(.failure(NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response"])))
                return
            }
            
            completion(.success(content))
        }.resume()
    }
}

/// OpenAI API client implementation
public class OpenAIClient: AIClient {
    private let apiKey: String
    private let model: String
    private let maxTokens: Int
    private let baseClient: BaseHTTPAIClient
    
    public init(apiKey: String, model: String = "gpt-4", maxTokens: Int = 1000) {
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
        self.baseClient = BaseHTTPAIClient()
    }
    
    public func sendPrompt(_ prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            completion(.failure(NSError(domain: "OpenAI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        let headers = [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json"
        ]
        
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": maxTokens
        ]
        
        baseClient.sendRequest(url: url, headers: headers, body: body, responseParser: { json in
            guard let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                return nil
            }
            return content
        }, completion: completion)
    }
}

/// Anthropic API client implementation
public class AnthropicClient: AIClient {
    private let apiKey: String
    private let model: String
    private let maxTokens: Int
    private let baseClient: BaseHTTPAIClient
    
    public init(apiKey: String, model: String = "claude-3-sonnet-20240229", maxTokens: Int = 1000) {
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
        self.baseClient = BaseHTTPAIClient()
    }
    
    public func sendPrompt(_ prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            completion(.failure(NSError(domain: "Anthropic", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        let headers = [
            "x-api-key": apiKey,
            "Content-Type": "application/json",
            "anthropic-version": "2023-06-01"
        ]
        
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": maxTokens
        ]
        
        baseClient.sendRequest(url: url, headers: headers, body: body, responseParser: { json in
            guard let content = json["content"] as? [[String: Any]],
                  let text = content.first?["text"] as? String else {
                return nil
            }
            return text
        }, completion: completion)
    }
}

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

// MARK: - Export/Import Bundle
/// Complete export bundle containing all ContextSynapse state
public struct ExportBundle: Codable {
    public let version: String
    public let exportDate: String
    public let weights: Weights
    public let regions: [Region]
    public let metadata: [String: String]
    
    public init(version: String = "1.0", exportDate: String, weights: Weights, regions: [Region], metadata: [String: String] = [:]) {
        self.version = version
        self.exportDate = exportDate
        self.weights = weights
        self.regions = regions
        self.metadata = metadata
    }
}

// MARK: - User Profile
/// User profile for multi-user support
public struct UserProfile: Codable, Equatable {
    public let id: String
    public var displayName: String
    public let createdAt: String
    public var lastUsedAt: String
    
    public init(id: String, displayName: String, createdAt: String, lastUsedAt: String) {
        self.id = id
        self.displayName = displayName
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

// MARK: - SynapseCore class
public class SynapseCore {
    let fm = FileManager.default
    public let appSupport: URL
    public let configURL: URL
    public let regionsURL: URL
    public let logDir: URL
    public let usersDir: URL
    public var currentUser: String
    
    /// Fault injection probability (0.0 by default). Can be set via env var CONTEXT_SYNAPSE_FAULT_PROB
    public var faultProbability: Double = 0.0
    
    /// Simple logging helper for debugging and error tracking
    private func logError(_ message: String, error: Error? = nil) {
        let errorMsg = error.map { " - \($0.localizedDescription)" } ?? ""
        print("ContextSynapse Error: \(message)\(errorMsg)", to: &standardError)
    }
    
    public init(folderName: String = "ContextSynapse", user: String = "default") {
        // Validate and sanitize user input to prevent directory traversal
        // Remove path separators and dots to prevent traversal attacks
        let sanitizedUser = user
            .components(separatedBy: CharacterSet(charactersIn: "/\\:."))
            .joined()
        
        // Ensure the sanitized user is not empty and is alphanumeric with limited special chars
        guard !sanitizedUser.isEmpty,
              sanitizedUser.rangeOfCharacter(from: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))) != nil else {
            fatalError("Invalid user identifier: must contain alphanumeric characters")
        }
        
        let home = fm.homeDirectoryForCurrentUser
        let baseDir = home.appendingPathComponent("Library").appendingPathComponent("Application Support").appendingPathComponent(folderName)
        self.appSupport = baseDir
        self.usersDir = baseDir.appendingPathComponent("users")
        self.currentUser = sanitizedUser
        
        // Create user-specific directories
        let userDir = usersDir.appendingPathComponent(sanitizedUser)
        self.configURL = userDir.appendingPathComponent("config.json")
        self.regionsURL = userDir.appendingPathComponent("regions.json")
        self.logDir = userDir.appendingPathComponent("logs")
        
        // Create directories with better error handling
        do {
            try fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
            try fm.createDirectory(at: usersDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: userDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: logDir, withIntermediateDirectories: true)
        } catch {
            logError("Failed to create directories", error: error)
        }
        
        // Create or update user profile
        updateUserProfile()
        
        // init faultProbability from environment (useful for testing)
        if let env = ProcessInfo.processInfo.environment["CONTEXT_SYNAPSE_FAULT_PROB"], 
           let v = Double(env), v >= 0.0, v <= 1.0 {
            self.faultProbability = v
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
        do {
            let data = try JSONEncoder().encode(w)
            try data.write(to: configURL, options: .atomic)
        } catch {
            logError("Failed to save weights", error: error)
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
        saveRegions(regions)
        return regions
    }
    
    public func saveRegions(_ regions: [Region]) {
        do {
            let data = try JSONEncoder().encode(regions)
            try data.write(to: regionsURL, options: .atomic)
        } catch {
            logError("Failed to save regions", error: error)
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
    
    /// Helper function to recompute numeric weights from priors
    private func updateWeightsFromPriors(_ weights: inout Weights) {
        for (k, prior) in weights.priors.intents {
            weights.intents[k] = mapPriorToWeight(prior)
        }
        for (k, prior) in weights.priors.tones {
            weights.tones[k] = mapPriorToWeight(prior)
        }
        for (k, prior) in weights.priors.domains {
            weights.domains[k] = mapPriorToWeight(prior)
        }
    }
    
    /// call this to apply feedback and update priors/weights (Bayesian updates via Beta)
    public func applyFeedbackUpdate(chosenIntent: String, chosenTone: String, chosenDomain: String, positive: Bool) {
        // Input validation
        guard !chosenIntent.isEmpty, !chosenTone.isEmpty, !chosenDomain.isEmpty else {
            return
        }
        
        var w = loadOrCreateDefaultWeights()
        func bump(dictKey: String, in map: inout [String:Prior]) {
            var prior = map[dictKey] ?? Prior()
            if positive {
                prior.alpha += 1.0
            } else {
                prior.beta += 1.0
            }
            map[dictKey] = prior
        }
        bump(dictKey: chosenIntent, in: &w.priors.intents)
        bump(dictKey: chosenTone, in: &w.priors.tones)
        bump(dictKey: chosenDomain, in: &w.priors.domains)
        // recompute numeric weights from priors (keeps alignment)
        updateWeightsFromPriors(&w)
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
        do {
            let data = try JSONEncoder().encode(run)
            try data.write(to: file, options: .atomic)
        } catch {
            logError("Failed to write run log", error: error)
        }
    }
    
    // MARK: - Export/Import
    
    /// Export complete state (weights + regions + metadata) to a file
    /// - Parameters:
    ///   - url: Destination file URL
    ///   - metadata: Optional metadata dictionary (e.g., user, description)
    /// - Returns: true if export succeeded
    @discardableResult
    public func exportState(to url: URL, metadata: [String: String] = [:]) -> Bool {
        let weights = loadOrCreateDefaultWeights()
        let regions = loadOrSeedRegions()
        let exportDate = ISO8601DateFormatter().string(from: Date())
        
        let bundle = ExportBundle(
            version: "1.0",
            exportDate: exportDate,
            weights: weights,
            regions: regions,
            metadata: metadata
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        guard let data = try? encoder.encode(bundle) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
    
    /// Import state from an export bundle file
    /// - Parameters:
    ///   - url: Source file URL
    ///   - merge: If true, merge with existing data; if false, replace completely
    /// - Returns: true if import succeeded
    @discardableResult
    public func importState(from url: URL, merge: Bool = false) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        guard let bundle = try? JSONDecoder().decode(ExportBundle.self, from: data) else { return false }
        
        if merge {
            // Merge mode: combine priors and weights intelligently
            var currentWeights = loadOrCreateDefaultWeights()
            
            // Helper function to merge prior dictionaries
            func mergePriors(_ current: inout [String: Prior], with new: [String: Prior]) {
                for (key, prior) in new {
                    if let existing = current[key] {
                        current[key] = Prior(
                            alpha: (existing.alpha + prior.alpha) / 2.0,
                            beta: (existing.beta + prior.beta) / 2.0
                        )
                    } else {
                        current[key] = prior
                    }
                }
            }
            
            // Merge priors (average alpha/beta values)
            mergePriors(&currentWeights.priors.intents, with: bundle.weights.priors.intents)
            mergePriors(&currentWeights.priors.tones, with: bundle.weights.priors.tones)
            mergePriors(&currentWeights.priors.domains, with: bundle.weights.priors.domains)
            
            // Recompute weights from merged priors
            updateWeightsFromPriors(&currentWeights)
            
            saveWeights(currentWeights)
            
            // Merge regions (add new ones, keep existing)
            var currentRegions = loadOrSeedRegions()
            let existingNames = Set(currentRegions.map { $0.name })
            for region in bundle.regions where !existingNames.contains(region.name) {
                currentRegions.append(region)
            }
            saveRegions(currentRegions)
        } else {
            // Replace mode: overwrite with imported data
            saveWeights(bundle.weights)
            saveRegions(bundle.regions)
        }
        
        return true
    }
    
    // MARK: - Multi-user Management
    
    /// Get or create user profile
    private func updateUserProfile() {
        let profileURL = usersDir.appendingPathComponent(currentUser).appendingPathComponent("profile.json")
        let now = ISO8601DateFormatter().string(from: Date())
        
        if let data = try? Data(contentsOf: profileURL),
           var profile = try? JSONDecoder().decode(UserProfile.self, from: data) {
            // Update last used timestamp
            profile.lastUsedAt = now
            if let d = try? JSONEncoder().encode(profile) {
                try? d.write(to: profileURL, options: .atomic)
            }
        } else {
            // Create new profile
            let profile = UserProfile(
                id: currentUser,
                displayName: currentUser.capitalized,
                createdAt: now,
                lastUsedAt: now
            )
            if let d = try? JSONEncoder().encode(profile) {
                try? d.write(to: profileURL, options: .atomic)
            }
        }
    }
    
    /// List all user profiles
    public func listUsers() -> [UserProfile] {
        guard let userDirs = try? fm.contentsOfDirectory(at: usersDir, includingPropertiesForKeys: nil) else {
            return []
        }
        
        var profiles: [UserProfile] = []
        for userDir in userDirs where userDir.hasDirectoryPath {
            let profileURL = userDir.appendingPathComponent("profile.json")
            if let data = try? Data(contentsOf: profileURL),
               let profile = try? JSONDecoder().decode(UserProfile.self, from: data) {
                profiles.append(profile)
            }
        }
        
        return profiles.sorted { $0.lastUsedAt > $1.lastUsedAt }
    }
    
    /// Switch to a different user (requires reinitializing SynapseCore)
    public static func switchUser(to user: String, folderName: String = "ContextSynapse") -> SynapseCore {
        return SynapseCore(folderName: folderName, user: user)
    }
}
