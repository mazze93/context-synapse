import Foundation
import SynapseCore

// MARK: - Edgar
// The raven. The Fool's dog. The maternal referee.
// He renders on every query. His state IS the system's state.

let args = CommandLine.arguments

// MARK: - Global flag scan (pre-init)
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

// MARK: - --lighthouse and --resync
// Persistence lives in SynapseCore (LighthouseStore.swift) so the GUI and
// tests reach the same store. Legacy <user>/lighthouse.json files written by
// the pre-0.4 CLI are migrated transparently on load.

if let lighthouseIdx = args.firstIndex(of: "--lighthouse"), lighthouseIdx + 1 < args.count {
    let label = args[lighthouseIdx + 1]
    let content = SynapseContent(id: UUID().uuidString, text: label)
    core.saveLighthouse(content)

    RavenRenderer.render(state: .perched, frameIndex: 0, lighthouseLabel: label, rotScore: 0.0)
    print("")
    print("\u{001B}[38;5;51m\u{001B}[1m⚓ Lighthouse set: \"\(label)\"\u{001B}[0m")
    print("\u{001B}[2medgar is watching.\u{001B}[0m")
    exit(0)
}

if args.contains("--resync") {
    core.clearLighthouse()
    RavenRenderer.render(state: .resync, frameIndex: 0, lighthouseLabel: nil, rotScore: 0.0)
    print("")
    print("\u{001B}[38;5;51m⚓ Lighthouse cleared. Set a new one with --lighthouse \"description\"\u{001B}[0m")
    exit(0)
}

// MARK: - --referee
// Persist referee mode (referee.json). Abrasive mode is strictly opt-in
// (ADR-002) — this explicit flag is the only way to enable it.

if let refereeIdx = args.firstIndex(of: "--referee"), refereeIdx + 1 < args.count {
    let rawMode = args[refereeIdx + 1].lowercased()
    guard let mode = RefereeMode(rawValue: rawMode) else {
        let valid = RefereeMode.allCases.map(\.rawValue).joined(separator: " | ")
        fputs("Unknown referee mode '\(rawMode)'. Use: \(valid)\n", stderr)
        exit(1)
    }
    var refereeConfig = core.loadRefereeConfig()
    refereeConfig.mode = mode
    guard core.saveRefereeConfig(refereeConfig) else {
        fputs("Failed to persist referee config\n", stderr)
        exit(1)
    }
    print("referee mode set: \(mode.rawValue)")
    exit(0)
}

// MARK: - --rsa
// Render the session's RSA state: latest similarity heatmap over
// [lighthouse + tracked synapses] and the anchor-saliency sparkline across
// epochs. This is the evidence layer — drift claims point here.

if args.contains("--rsa") {
    let manager = core.makeSynapseManager()
    let epochs = await manager.epochs
    if let latest = epochs.last {
        print(RSARenderer.heatmap(latest))
        print(RSARenderer.saliencyStrip(epochs))
    } else if core.loadLighthouseRecord() == nil {
        print("No lighthouse set — RSA epochs are only meaningful relative to an anchor.")
        print("Set one: contextsynapse --lighthouse \"<your primary goal>\"")
    } else {
        print(RSARenderer.saliencyStrip(epochs))
    }
    exit(0)
}

// MARK: - Export/Import

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

    RavenRenderer.render(state: .export, frameIndex: 0, lighthouseLabel: nil, rotScore: 0.0)

    let url = URL(fileURLWithPath: outputFile)
    if core.exportState(to: url, metadata: metadata) {
        print("Successfully exported state to: \(outputFile)")
        print("\u{001B}[2medgar · session folded → \(outputFile)\u{001B}[0m")
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

// MARK: - Regular query processing

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
    case "--user", "--lighthouse", "--resync", "--referee":
        i += 1
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
    fputs("       contextsynapse --lighthouse \"<your primary goal>\"\n", stderr)
    fputs("       contextsynapse --resync\n", stderr)
    fputs("       contextsynapse --referee functional|abrasive\n", stderr)
    fputs("       contextsynapse --rsa   (render session RSA heatmap + anchor saliency strip)\n", stderr)
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
let toneScores   = core.applyTriggers(base: weights.tones,   triggers: weights.triggers, activeKeys: activeTriggers)
let domainScores = core.applyTriggers(base: weights.domains, triggers: weights.triggers, activeKeys: activeTriggers)

let chosenIntent = flagIntent ?? core.weightedPick(intentScores) ?? "Create"
let chosenTone   = flagTone   ?? core.weightedPick(toneScores)   ?? "Concise"
let chosenDomain = flagDomain ?? core.weightedPick(domainScores) ?? "Work"

// MARK: - Rot computation (v0.4: SynapseManager owns session state)
// The manager persists per-synapse clocks and interaction history across
// invocations, wires the SynapticCircuit backward pass, and snapshots an
// RSA epoch on every observation (view with --rsa). Drift clocks: a new
// thread of attention measures from the lighthouse's setAt; a revisited
// one from its own last interaction. Never from a just-born synapse —
// tanh(0) = 0 and Edgar would stay perched forever.

let currentContent = SynapseContent(
    id: UUID().uuidString,
    text: userQuery,
    fileReferences: flagApp.map { [$0] } ?? [],
    functionNames: []
)

let activeLighthouseRecord = core.loadLighthouseRecord()
let activeLighthouse = activeLighthouseRecord?.content
let refereeMode = core.loadRefereeConfig().mode
var rotScore: Double = 0.0
var decayWeightNow: Double = 1.0
var edgarState: RavenState = .dormant

let manager = core.makeSynapseManager()
if let epoch = await manager.observe(currentContent, event: .fileSave) {
    rotScore = max(0.0, min(1.0, 1.0 - epoch.lighthouseSaliency))
    decayWeightNow = epoch.observedDecayWeight
    edgarState = RavenState.from(rotScore: rotScore, lighthouseSet: true)
}

// MARK: - Breadcrumb
// Re-sync line before the prompt, also appended to logs/breadcrumb-<iso>.txt.
if let record = activeLighthouseRecord {
    BreadcrumbWriter.emit(for: record, rotScore: rotScore, core: core)
}

// MARK: - Assemble and print

let finalPrompt = core.assemblePrompt(tone: chosenTone, intent: chosenIntent, domain: chosenDomain, query: userQuery)
print(finalPrompt)
print("")

// MARK: - Edgar renders after every query
RavenRenderer.render(
    state: edgarState,
    frameIndex: Int.random(in: 0..<RavenRenderer.frameCount(for: edgarState)),
    lighthouseLabel: activeLighthouse?.text,
    rotScore: rotScore
)

// MARK: - Cauterize intervention
if edgarState == .cauterize, let lighthouse = activeLighthouse {
    print("")
    let intervention = ContextIntervention(
        lighthouseDescription: lighthouse.text,
        currentSynapseDescription: userQuery,
        minutesInDrift: activeLighthouseRecord?.setAtDate
            .map { Int(Date().timeIntervalSince($0) / 60) } ?? 0,
        lighthouseSaliencyNow: max(0.0, 1.0 - rotScore),
        lighthouseSaliencyAtSessionStart: 1.0
    )
    EdgarIntervention.render(intervention: intervention)
}

// MARK: - Run log (Edgar state + typed decay snapshot)
let decaySnapshot = SynapseCore.RunLog.DecaySnapshot(
    decayWeight: decayWeightNow,
    rotScore: rotScore,
    lighthouseSaliency: max(0.0, min(1.0, 1.0 - rotScore)),
    refereeMode: refereeMode.rawValue,
    interventionFired: edgarState == .cauterize
)
var runContext: [String: String] = [
    "user":       selectedUser,
    "app":        flagApp ?? "unknown",
    "focus":      flagFocus ?? "unknown",
    "timeBucket": activeTriggers.joined(separator: ","),
    "edgarState": "\(edgarState)",
    "lighthouse": activeLighthouse?.text ?? "none"
]
runContext.merge(decaySnapshot.contextFields) { _, new in new }
let run = SynapseCore.RunLog(
    timestamp: ISO8601DateFormatter().string(from: Date()),
    input: userQuery,
    chosenIntent: chosenIntent,
    chosenTone: chosenTone,
    chosenDomain: chosenDomain,
    assembledPrompt: finalPrompt,
    context: runContext
)
core.logRun(run)

// MARK: - Feedback
if let fb = feedbackFlag?.lowercased() {
    if fb == "good" || fb == "yes" {
        core.applyFeedbackUpdate(chosenIntent: chosenIntent, chosenTone: chosenTone, chosenDomain: chosenDomain, positive: true)
        print("\u{001B}[2medgar · feedback noted. priors updated.\u{001B}[0m")
    } else if fb == "bad" || fb == "no" {
        core.applyFeedbackUpdate(chosenIntent: chosenIntent, chosenTone: chosenTone, chosenDomain: chosenDomain, positive: false)
        print("\u{001B}[2medgar · feedback noted. priors adjusted.\u{001B}[0m")
    } else {
        print("Unknown feedback token '\(fb)'. Use 'good' or 'bad'.")
    }
}
