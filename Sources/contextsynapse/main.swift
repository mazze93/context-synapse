import Foundation
import SynapseCore

let core = SynapseCore()
var weights = core.loadOrCreateDefaultWeights()

let args = CommandLine.arguments
var providedQuery: String? = nil
var flagApp: String? = nil
var flagFocus: String? = nil
var flagIntent: String? = nil
var flagTone: String? = nil
var flagDomain: String? = nil
var flagTime: String? = nil
var feedbackFlag: String? = nil
var faultProbFlag: String? = nil

var i = 1
while i < args.count {
    let a = args[i]
    switch a {
    case "--app":
        i += 1
        if i < args.count { flagApp = args[i] }
    case "--focus":
        i += 1
        if i < args.count { flagFocus = args[i] }
    case "--intent":
        i += 1
        if i < args.count { flagIntent = args[i] }
    case "--tone":
        i += 1
        if i < args.count { flagTone = args[i] }
    case "--domain":
        i += 1
        if i < args.count { flagDomain = args[i] }
    case "--time":
        i += 1
        if i < args.count { flagTime = args[i] }
    case "--feedback":
        i += 1
        if i < args.count { feedbackFlag = args[i] }
    case "--fault-prob":
        i += 1
        if i < args.count { faultProbFlag = args[i] }
    default:
        if providedQuery == nil {
            providedQuery = a
        } else {
            providedQuery = (providedQuery ?? "") + " " + a
        }
    }
    i += 1
}

// stdin fallback
if providedQuery == nil {
    let stdinData = FileHandle.standardInput.availableData
    if !stdinData.isEmpty, let s = String(data: stdinData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
        providedQuery = s
    }
}


guard let userQuery = providedQuery?.trimmingCharacters(in: .whitespacesAndNewlines), !userQuery.isEmpty else {
    fputs("Usage: contextsynapse <your query> [--app Mail] [--focus Home] [--intent Brainstorm] [--tone Casual] [--domain Work] [--time HH:MM] [--feedback good|bad] [--fault-prob 0.0-1.0]\n", stderr)
    exit(1)
}

// set fault probability for this run if requested
if let fp = faultProbFlag, let v = Double(fp) {
    core.faultProbability = max(0.0, min(1.0, v))
}

// triggers
var activeTriggers = [String]()
if let app = flagApp { activeTriggers.append("app.\(app)") }
if let focus = flagFocus { activeTriggers.append("focus.\(focus)") }
if let t = flagTime {
    if let hh = Int(t.split(separator: ":").first ?? "") {
        if hh >= 5 && hh < 12 {
            activeTriggers.append("time.morning")
        } else if hh >= 12 && hh < 17 {
            activeTriggers.append("time.afternoon")
        } else {
            activeTriggers.append("time.evening")
        }
    }
} else {
    let hour = Calendar.current.component(.hour, from: Date())
    if hour >= 5 && hour < 12 {
        activeTriggers.append("time.morning")
    } else if hour >= 12 && hour < 17 {
        activeTriggers.append("time.afternoon")
    } else {
        activeTriggers.append("time.evening")
    }
}

let intentScores = core.applyTriggers(base: weights.intents, triggers: weights.triggers, activeKeys: activeTriggers)
let toneScores = core.applyTriggers(base: weights.tones, triggers: weights.triggers, activeKeys: activeTriggers)
let domainScores = core.applyTriggers(base: weights.domains, triggers: weights.triggers, activeKeys: activeTriggers)

let chosenIntent = flagIntent ?? core.weightedPick(intentScores) ?? "Create"
let chosenTone = flagTone ?? core.weightedPick(toneScores) ?? "Concise"
let chosenDomain = flagDomain ?? core.weightedPick(domainScores) ?? "Work"

let finalPrompt = "[\(chosenTone)] [\(chosenIntent)] [\(chosenDomain)]: \(userQuery)"
print(finalPrompt)

// log
let run = SynapseCore.RunLog(
    timestamp: ISO8601DateFormatter().string(from: Date()),
    input: userQuery,
    chosenIntent: chosenIntent,
    chosenTone: chosenTone,
    chosenDomain: chosenDomain,
    assembledPrompt: finalPrompt,
    context: ["app": flagApp ?? "unknown", "focus": flagFocus ?? "unknown", "timeBucket": activeTriggers.joined(separator: ",")]
)
core.logRun(run)

// feedback - apply Bayesian update and persist weights
if let fb = feedbackFlag?.lowercased() {
    if fb == "good" || fb == "yes" {
        core.applyFeedbackUpdate(chosenIntent: chosenIntent, chosenTone: chosenTone, chosenDomain: chosenDomain, positive: true)
        print("Feedback applied: positive priors updated.")
    } else if fb == "bad" || fb == "no" {
        core.applyFeedbackUpdate(chosenIntent: chosenIntent, chosenTone: chosenTone, chosenDomain: chosenDomain, positive: false)
        print("Feedback applied: negative priors updated.")
    } else {
        print("Unknown feedback token '\(fb)'. Use 'good' or 'bad'.")
    }
}
