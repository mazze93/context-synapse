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
