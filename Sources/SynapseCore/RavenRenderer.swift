import Foundation

// MARK: - Edgar
// The raven. The Fool's dog. The maternal referee.
//
// Edgar doesn't cheer. Edgar doesn't lecture.
// Edgar watches, tracks drift, and bites at your heels
// when you're about to walk off the edge.
//
// His state IS the system's state.
// You read Edgar before you read any text.
//
// Named after Poe's raven — but Edgar isn't ominous.
// He's the one trying to tell you something.

// MARK: - ANSI color helpers

private enum ANSI {
    static let reset       = "\u{001B}[0m"
    static let bold        = "\u{001B}[1m"
    static let dim         = "\u{001B}[2m"

    // Edgar's palette — maps to rot score
    static let purple      = "\u{001B}[38;5;135m"   // dormant / export
    static let cyan        = "\u{001B}[38;5;51m"    // perched — healthy
    static let cyanDim     = "\u{001B}[38;5;45m"    // watching — slight drift
    static let yellow      = "\u{001B}[38;5;226m"   // stirring — notable drift
    static let orange      = "\u{001B}[38;5;208m"   // alarmed — heels-bite imminent
    static let red         = "\u{001B}[38;5;196m"   // cauterize — full interrupt
    static let white       = "\u{001B}[97m"         // flash frame in cauterize
    static let dimPurple   = "\u{001B}[38;5;93m"    // export fade

    // Accent for circuit traces in wings
    static let circuitBlue = "\u{001B}[38;5;39m"
    static let circuitPink = "\u{001B}[38;5;213m"
}

// MARK: - RavenState

public enum RavenState: Equatable {
    case dormant                    // pre-lighthouse, waiting
    case perched                    // lighthouse set, rot 0.0–0.25
    case watching                   // rot 0.25–0.50, subtle shift
    case stirring                   // rot 0.50–0.75, circuit flicker
    case alarmed                    // rot 0.75–0.82, heels-bite
    case cauterize                  // rot >= 0.82, hard interrupt
    case resync                     // returning to lighthouse
    case export                     // session end

    public static func from(rotScore: Double, lighthouseSet: Bool) -> RavenState {
        guard lighthouseSet else { return .dormant }
        switch rotScore {
        case ..<0.25:   return .perched
        case ..<0.50:   return .watching
        case ..<0.75:   return .stirring
        case ..<0.82:   return .alarmed
        default:        return .cauterize
        }
    }
}

// MARK: - RavenRenderer

public struct RavenRenderer {

    public static func frameCount(for state: RavenState) -> Int {
        switch state {
        case .dormant:    return 2
        case .perched:    return 3
        case .watching:   return 3
        case .stirring:   return 4
        case .alarmed:    return 3
        case .cauterize:  return 4
        case .resync:     return 3
        case .export:     return 2
        }
    }

    public static func render(state: RavenState, frameIndex: Int = 0, lighthouseLabel: String? = nil, rotScore: Double = 0.0) {
        let frame = buildFrame(state: state, frameIndex: frameIndex, lighthouseLabel: lighthouseLabel, rotScore: rotScore)
        print(frame)
    }

    public static func buildFrame(state: RavenState, frameIndex: Int = 0, lighthouseLabel: String? = nil, rotScore: Double = 0.0) -> String {
        let color = primaryColor(for: state, frameIndex: frameIndex)
        let accent = accentColor(for: state, frameIndex: frameIndex)
        let bird = birdFrame(state: state, frameIndex: frameIndex, color: color, accent: accent)
        let statusLine = buildStatusLine(state: state, lighthouseLabel: lighthouseLabel, rotScore: rotScore, color: color)
        return bird + "\n" + statusLine + ANSI.reset
    }

    // MARK: - Bird ASCII frames

    private static func birdFrame(state: RavenState, frameIndex: Int, color: String, accent: String) -> String {
        switch state {

        case .dormant:
            let frames = [
             """
             \(color)      .
                  \(accent)◦\(color)▓▓◦
                   ███
                   ▓█▓
                    ▓\(ANSI.reset)
             """,
             """
             \(color)
                  \(accent)◦\(color)▓▓◦
                   ███
                   ▓█▓   .
                    ▓\(ANSI.reset)
             """]
            return frames[frameIndex % frames.count]

        case .perched:
            let frames = [
             """
             \(color)    \(accent)◈\(color)
                 ╔▓██▓╗
                 ║█\(accent)◉\(color)█║
                ╱▓███▓╲
               ╱▓▓\(accent)·:·\(color)▓▓╲
                   ▓▓\(ANSI.reset)
             """,
             """
             \(color)
                 ╔▓██▓╗
                 ║█\(accent)◉\(color)█║  \(accent)·\(color)
                ╱▓███▓╲
               ╱▓▓\(accent)·:·\(color)▓▓╲
                   ▓▓\(ANSI.reset)
             """,
             """
             \(color)
                 ╔▓██▓╗
                 ║█\(accent)◉\(color)█║
                ╱▓███▓╲  \(accent)◦\(color)
               ╱▓▓\(accent)·:·\(color)▓▓╲
                   ▓▓\(ANSI.reset)
             """]
            return frames[frameIndex % frames.count]

        case .watching:
            let frames = [
             """
             \(color)    \(accent)◈\(color)
                 ╔▓██▓╗
                 ║█\(accent)◉\(color)█║
                ╱▓███▓╲\(accent)~\(color)
               ╱▓▓\(accent)·:·\(color)▓▓╲
                   ▓▓\(ANSI.reset)
             """,
             """
             \(color)   \(accent)◈\(color)
                 ╔▓██▓╗
                /█\(accent)◉\(color)█╗
               ╱▓████▓╲
              ╱▓▓\(accent)~·:·~\(color)▓▓╲
                   ▓▓\(ANSI.reset)
             """,
             """
             \(color)    \(accent)◈\(color)
                 ╔▓██▓╗
                 ║█\(accent)◉\(color)█║
                ╱▓███▓╲
               ╱▓▓\(accent)~·:·~\(color)▓▓╲\(accent)~\(color)
                   ▓▓\(ANSI.reset)
             """]
            return frames[frameIndex % frames.count]

        case .stirring:
            let frames = [
             """
             \(color)  \(accent)◈ ◦\(color)
                ╔▓███▓╗
               /█\(accent)◉\(color)██╗\(accent)≋\(color)
              ╱▓█████▓╲
             ╱▓▓\(accent){·:·}\(color)▓▓▓╲
                  ▓▓▓\(ANSI.reset)
             """,
             """
             \(color)  \(accent)◦ ◈\(color)
                ╔▓███▓╗
               /█\(accent)◉\(color)██╗
              ╱▓█████▓╲\(accent)≋\(color)
             ╱▓▓\(accent)[·:·]\(color)▓▓▓╲
                  ▓▓▓\(ANSI.reset)
             """,
             """
             \(color)  \(accent)◈\(color)
                ╔▓███▓╗\(accent)≋\(color)
               /█\(accent)◉\(color)██╗
              ╱▓█████▓╲
             ╱▓▓\(accent){·:·}\(color)▓▓▓╲
                  ▓▓▓\(ANSI.reset)
             """,
             """
             \(color)  \(accent)◦ ◦\(color)
                ╔▓███▓╗
              \(accent)≋\(color)/█\(accent)◉\(color)██╗
              ╱▓█████▓╲
             ╱▓▓\(accent)[·:·]\(color)▓▓▓╲\(accent)≋\(color)
                  ▓▓▓\(ANSI.reset)
             """]
            return frames[frameIndex % frames.count]

        case .alarmed:
            let frames = [
             """
             \(color)\(ANSI.bold)    \(accent)◈◈\(color)
               ╔══▓███▓══╗
              /██\(accent)◉\(color)███╗\(accent)!\(color)
             ╱████████████╲
             ╱▓▓\(accent)!·:·!\(color)▓▓▓▓▓╲
                   ▓▓▓\(ANSI.reset)
             """,
             """
             \(color)\(ANSI.bold)   \(accent)◈ ◈\(color)
               ╔══▓███▓══╗\(accent)!\(color)
              /██\(accent)◉\(color)███╗
             ╱████████████╲
             ╱▓▓\(accent)!·:·!\(color)▓▓▓▓▓╲
                   ▓▓▓\(ANSI.reset)
             """,
             """
             \(color)\(ANSI.bold)    \(accent)◈◈\(color)\(ANSI.bold)
               ╔══▓███▓══╗
             \(accent)!\(color)/██\(accent)◉\(color)███╗
             ╱████████████╲\(accent)!\(color)
             ╱▓▓\(accent)!·:·!\(color)▓▓▓▓▓╲
                   ▓▓▓\(ANSI.reset)
             """]
            return frames[frameIndex % frames.count]

        case .cauterize:
            let flash = frameIndex % 2 == 0 ? ANSI.red : ANSI.white
            let frames = [
             """
             \(flash)\(ANSI.bold)  ◈ CAW ◈
             ╔═══▓████▓═══╗
             ║███\(accent)◉\(flash)████║ !!!
             ╠═══════════╣
             ╱▓▓▓!·:·!▓▓▓▓╲
                   ▓▓▓\(ANSI.reset)
             """,
             """
             \(flash)\(ANSI.bold)◈◈ CAW CAW ◈◈
             ╔═══▓████▓═══╗
             ╠███\(accent)◉\(flash)████╣
             ╠═══════════╣ !!!
             ╱▓▓▓!·:·!▓▓▓▓╲
                   ▓▓▓\(ANSI.reset)
             """,
             """
             \(flash)\(ANSI.bold)  ◈ CAW ◈
             ╔═══▓████▓═══╗ !!!
             ╠███\(accent)◉\(flash)████╣
             ╠═══════════╣
             ╱▓▓▓!·:·!▓▓▓▓╲
                   ▓▓▓\(ANSI.reset)
             """,
             """
             \(flash)\(ANSI.bold)◈◈◈ CAW ◈◈◈
             ╔═══▓████▓═══╗
             ║███\(accent)◉\(flash)████║
             ╠═══════════╣ !!!
             ╱▓▓▓!·:·!▓▓▓▓╲
                   ▓▓▓\(ANSI.reset)
             """]
            return frames[frameIndex % frames.count]

        case .resync:
            let frames = [
             """
             \(color)\(ANSI.bold)    \(accent)◈\(color)
                 ╔▓██▓╗  \(accent)↩\(color)
                 ║█\(accent)◉\(color)█║
                ╱▓███▓╲
               ╱▓▓\(accent)·:·\(color)▓▓╲
                   ▓▓\(ANSI.reset)
             """,
             """
             \(color)
                 ╔▓██▓╗
                 ║█\(accent)◉\(color)█║  \(accent)◦\(color)
                ╱▓███▓╲
               ╱▓▓\(accent)·:·\(color)▓▓╲
                   ▓▓\(ANSI.reset)
             """,
             """
             \(color)    \(accent)◈\(color)
                 ╔▓██▓╗
                 ║█\(accent)◉\(color)█║
                ╱▓███▓╲
               ╱▓▓\(accent)·:·\(color)▓▓╲
                   ▓▓\(ANSI.reset)
             """]
            return frames[frameIndex % frames.count]

        case .export:
            let frames = [
             """
             \(ANSI.dimPurple)\(ANSI.dim)
                  ▓▓▓
                 ▓███▓
                 ▓███▓
                  ▓▓▓
                   ▓\(ANSI.reset)
             """,
             """
             \(ANSI.dimPurple)\(ANSI.dim)
                   ▓▓
                  ████
                  ████
                   ▓▓
                   ▓\(ANSI.reset)
             """]
            return frames[frameIndex % frames.count]
        }
    }

    // MARK: - Status line

    private static func buildStatusLine(state: RavenState, lighthouseLabel: String?, rotScore: Double, color: String) -> String {
        let rotBar = buildRotBar(rotScore: rotScore, color: color)
        if let label = lighthouseLabel {
            let truncated = label.count > 32 ? String(label.prefix(29)) + "..." : label
            return "\(color)⚓ \(truncated)  \(rotBar)\(ANSI.reset)"
        } else {
            switch state {
            case .dormant:
                return "\(ANSI.purple)\(ANSI.dim)edgar · set a lighthouse to begin  ──────────────\(ANSI.reset)"
            case .export:
                return "\(ANSI.dimPurple)\(ANSI.dim)edgar · session folded. until next time.\(ANSI.reset)"
            default:
                return "\(color)edgar · \(rotBar)\(ANSI.reset)"
            }
        }
    }

    private static func buildRotBar(rotScore: Double, color: String) -> String {
        let pct = Int(rotScore * 100)
        let barWidth = 20
        let filled = Int(Double(barWidth) * rotScore)
        let empty = barWidth - filled
        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
        let label: String
        switch rotScore {
        case ..<0.25:  label = "clean"
        case ..<0.50:  label = "drifting"
        case ..<0.75:  label = "rotting"
        case ..<0.82:  label = "heels-bite incoming"
        default:       label = "CAW"
        }
        return "rot [\(bar)] \(pct)%  \(label)"
    }

    // MARK: - Color mapping

    private static func primaryColor(for state: RavenState, frameIndex: Int) -> String {
        switch state {
        case .dormant:   return ANSI.purple
        case .perched:   return ANSI.cyan
        case .watching:  return ANSI.cyanDim
        case .stirring:  return ANSI.yellow
        case .alarmed:   return ANSI.orange
        case .cauterize: return frameIndex % 2 == 0 ? ANSI.red : ANSI.white
        case .resync:    return ANSI.cyan
        case .export:    return ANSI.dimPurple
        }
    }

    private static func accentColor(for state: RavenState, frameIndex: Int) -> String {
        switch state {
        case .dormant:   return ANSI.circuitPink
        case .perched:   return ANSI.circuitBlue
        case .watching:  return ANSI.circuitBlue
        case .stirring:  return ANSI.circuitPink
        case .alarmed:   return ANSI.orange
        case .cauterize: return ANSI.white
        case .resync:    return ANSI.circuitBlue
        case .export:    return ANSI.purple
        }
    }
}

// MARK: - EdgarIntervention
// The Fool's dog moment. Edgar caws. Four choices.
// No lecture. Just data and agency.
// "edgar doesn't judge. edgar just notices."

public struct EdgarIntervention {
    public static func render(intervention: ContextIntervention) {
        let r    = "\u{001B}[38;5;196m"
        let c    = "\u{001B}[38;5;51m"
        let w    = "\u{001B}[97m"
        let dim  = "\u{001B}[2m"
        let bold = "\u{001B}[1m"
        let rst  = "\u{001B}[0m"

        print("""
        \(r)\(bold)
        ┌─────────────────────────────────────────────────┐
        │  ◈ EDGAR  ·  CONTEXT ROT DETECTED               │
        └─────────────────────────────────────────────────┘\(rst)

        \(w)Lighthouse:\(rst)  \(c)\(intervention.lighthouseDescription)\(rst)
        \(w)Drift:\(rst)       \(intervention.currentSynapseDescription)
        \(w)Time lost:\(rst)   \(intervention.minutesInDrift) minutes
        \(w)Saliency:\(rst)    \(Int(intervention.lighthouseSaliencyNow * 100))%  \(buildMiniBar(intervention.lighthouseSaliencyNow))

        \(w)What do you want to do?\(rst)

          \(c)[1]\(rst) Return to lighthouse
          \(c)[2]\(rst) Promote current task to lighthouse
          \(c)[3]\(rst) Continue  (edgar will check in again in 15min)
          \(c)[4]\(rst) I know, I know. Dismiss.

        \(dim)edgar doesn't judge. edgar just notices.\(rst)
        """)
    }

    private static func buildMiniBar(_ value: Double) -> String {
        let w = 10
        let f = Int(Double(w) * value)
        return "[" + String(repeating: "█", count: f) + String(repeating: "░", count: w - f) + "]"
    }
}
