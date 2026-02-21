import Foundation
import SynapseCore

let args = CommandLine.arguments

// Global flag scan (needed before core initialization)
var selectedUser = "default"
var scanIndex = 1
while scanIndex < args.count {
    if args[scanIndex] == "--user", scanIndex + 1 < args.count {
        selectedUser = args[scanIndex + 1]
        break
    }
    scanIndex += 1
}

let core = SynapseCore(user: selectedUser)

// Check for special commands first (export/import), regardless of flag order.
let exportIndex = args.firstIndex(of: "--export")
let importIndex = args.firstIndex(of: "--import")
if exportIndex != nil && importIndex != nil {
    fputs("Error: --export and --import cannot be used together\n", stderr)
    exit(1)
}

if let exportIndex {
    guard exportIndex + 1 < args.count else {
        fputs("Usage: contextsynapse --export <output-file.json> [--metadata key=value ...] [--user <id>]\n", stderr)
        exit(1)
    }
    let outputFile = args[exportIndex + 1]
    var metadata: [String: String] = [:]

    var i = 1
    while i < args.count {
        if args[i] == "--metadata", i + 1 < args.count {
            let parts = args[i + 1].split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                metadata[String(parts[0])] = String(parts[1])
            }
            i += 2
        } else {
            i += 1
        }
    }

    let url = URL(fileURLWithPath: outputFile)
    if core.exportState(to: url, metadata: metadata) {
        print("Successfully exported state to: \(outputFile)")
        exit(0)
    }
    fputs("Error: Failed to export state\n", stderr)
    exit(1)
}

if let importIndex {
    guard importIndex + 1 < args.count else {
        fputs("Usage: contextsynapse --import <input-file.json> [--merge] [--user <id>]\n", stderr)
        exit(1)
    }
    let inputFile = args[importIndex + 1]
    let merge = args.contains("--merge")

    let url = URL(fileURLWithPath: inputFile)
    if core.importState(from: url, merge: merge) {
        print("Successfully imported state from: \(inputFile)")
        print(merge ? "Mode: Merged with existing data" : "Mode: Replaced existing data")
        exit(0)
    }
    fputs("Error: Failed to import state\n", stderr)
    exit(1)
}

// Regular query processing
var weights = core.loadOrCreateDefaultWeights()
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
        i += 1; if i < args.count { flagApp = args[i] }
    case "--focus":
        i += 1; if i < args.count { flagFocus = args[i] }
    case "--intent":
        i += 1; if i < args.count { flagIntent = args[i] }
    case "--tone":
        i += 1; if i < args.count { flagTone = args[i] }
    case "--domain":
        i += 1; if i < args.count { flagDomain = args[i] }
    case "--time":
        i += 1; if i < args.count { flagTime = args[i] }
    case "--feedback":
        i += 1; if i < args.count { feedbackFlag = args[i] }
    case "--fault-prob":
        i += 1; if i < args.count { faultProbFlag = args[i] }
    case "--user":
        i += 1 // already consumed for core init
    default:
        if providedQuery == nil {
            providedQuery = a
        } else {
            providedQuery = (providedQuery ?? "") + " " + a
        }
    }
    i += 1
}

if providedQuery == nil {
    let stdinData = FileHandle.standardInput.availableData
    if !stdinData.isEmpty,
       let s = String(data: stdinData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
       !s.isEmpty {
        providedQuery = s
    }
}

guard let userQuery = providedQuery?.trimmingCharacters(in: .whitespacesAndNewlines), !userQuery.isEmpty else {
    fputs("Usage: contextsynapse <your query> [--user <id>] [--app Mail] [--focus Home] [--intent Brainstorm] [--tone Casual] [--domain Work] [--time HH:MM] [--feedback good|bad] [--fault-prob 0.0-1.0]\n", stderr)
    fputs("       contextsynapse --export <output-file.json> [--metadata key=value ...] [--user <id>]\n", stderr)
    fputs("       contextsynapse --import <input-file.json> [--merge] [--user <id>]\n", stderr)
    exit(1)
}

if let fp = faultProbFlag, let v = Double(fp) {
    core.faultProbability = max(0.0, min(1.0, v))
}

var activeTriggers = [String]()
if let app = flagApp { activeTriggers.append("app.\(app)") }
if let focus = flagFocus { activeTriggers.append("focus.\(focus)") }
if let t = flagTime {
    let components = t.split(separator: ":")
    if let hhStr = components.first, let hh = Int(hhStr), hh >= 0, hh < 24 {
        if hh >= 5 && hh < 12 {
            activeTriggers.append("time.morning")
        } else if hh >= 12 && hh < 17 {
            activeTriggers.append("time.afternoon")
        } else {
            activeTriggers.append("time.evening")
        }
    } else {
        fputs("Warning: Invalid time format '\(t)', using current time instead\n", stderr)
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 5 && hour < 12 {
            activeTriggers.append("time.morning")
        } else if hour >= 12 && hour < 17 {
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

let finalPrompt = core.assemblePrompt(tone: chosenTone, intent: chosenIntent, domain: chosenDomain, query: userQuery)
print(finalPrompt)

let run = SynapseCore.RunLog(
    timestamp: ISO8601DateFormatter().string(from: Date()),
    input: userQuery,
    chosenIntent: chosenIntent,
    chosenTone: chosenTone,
    chosenDomain: chosenDomain,
    assembledPrompt: finalPrompt,
    context: [
        "user": selectedUser,
        "app": flagApp ?? "unknown",
        "focus": flagFocus ?? "unknown",
        "timeBucket": activeTriggers.joined(separator: ",")
    ]
)
core.logRun(run)

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
