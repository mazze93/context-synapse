# Context Synapse
![Swift](https://img.shields.io/badge/Swift-5.8-orange)
![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![Local--First](https://img.shields.io/badge/Architecture-Local--First-success)
![Bayesian](https://img.shields.io/badge/Learning-Bayesian-purple)
![Status](https://img.shields.io/badge/Status-Experimental-critical)
ContextSynapse

ContextSynapse is a local-first, adaptive prompt orchestration engine that treats context like a living system—not a static prefix.

It combines Bayesian learning, contextual matrices, and intentional fault injection to dynamically assemble prompts based on intent, tone, domain, region, and environment. Instead of brittle rules, ContextSynapse evolves through feedback, gracefully degrades under partial failure, and exposes its internal state through an interactive heatmap interface.

Built in Swift as a CLI + macOS app + App-Intent-ready core, ContextSynapse is designed for people exploring how human intention, machine response, and uncertainty can coexist inside resilient systems.

⸻

Why this exists

Most prompt systems assume:
	•	perfect inputs
	•	stable context
	•	static rules

ContextSynapse assumes the opposite.

It is designed to:
	•	learn from use (Bayesian priors update with feedback)
	•	survive damage (controlled fault injection simulates partial data loss)
	•	remain interpretable (weights, priors, and similarities are visible and adjustable)
	•	operate locally (no required network or cloud dependency)

This makes it suitable for research, creative tooling, and anyone exploring post-deterministic human–machine interaction models.

⸻

Key Features
	•	🧠 Bayesian Weighting
Uses Beta priors to adapt intent, tone, and domain selection over time.
	•	🧩 Contextual Matrix Engine
Blends triggers, priors, and live signals into weighted prompt assembly.
	•	🌍 Regional Similarity Analysis
Cosine similarity across region vectors with interactive heatmap visualization.
	•	⚡ Intentional Fragility
Built-in fault injection (“disintegrating sky plates”) to test resilience under partial failure.
	•	🧪 Deterministic & Testable
Unit tests validate convergence, degradation tolerance, and numerical stability.
	•	🛠 Local-First Architecture
Swift Package core, CLI, macOS UI, App-Intent ready—no vendor lock-in.

⸻

Philosophy

ContextSynapse treats prompting as a dynamic cognitive process, not a string operation.

Context is not something you prepend.
It’s something you negotiate, reinforce, and occasionally let fracture.

⸻

Status

Actively evolving.
Designed as a research-grade scaffold, not a polished consumer product.

## Architecture

### Core Components

**SynapseCore**: Main framework implementing:
- `ContextRegion`: Weighted regions with intent, domain, and tone tracking
- `SynapseCore`: Bayesian feedback engine with prior/posterior management
- `applyFeedbackUpdate()`: Update weights based on user feedback
- `computeRegionSimilarities()`: Cosine similarity for context matching
- `loadOrCreateDefaultWeights()`: Initialize or restore weight state

**CLI Tool** (`contextsynapse`):
- Argument parsing for feedback operations
- Bayesian weight updates via command-line
- JSON state persistence

**GUI Application** (`ContextSynapseApp`):
- Interactive weight grid visualization
- Real-time heatmap display
- Keyboard shortcuts for rapid feedback
- macOS-native SwiftUI interface

## Installation

### Prerequisites

- macOS 12.0+
- Xcode 14.0+ (for building)
- Swift 5.7+

### Building from Source

```bash
# Clone the repository
git clone https://github.com/mazze93/context-synapse.git
cd context-synapse

# Build the project
swift build -c release

# Run the CLI
.build/release/contextsynapse --help

# Or build and run the GUI app in Xcode
open Package.swift
```

See [INSTALL.md](INSTALL.md) for detailed build instructions.

## Quick Start

### CLI Usage

```bash
# Apply positive feedback to "Technical" intent in "Work" domain
contextsynapse --feedback positive --intent Technical --domain Work

# Apply negative feedback to "Casual" tone
contextsynapse --feedback negative --tone Casual

# View current weights (loads from default_config.json)
contextsynapse --status
```

### Programmatic Usage

```swift
import SynapseCore

// Initialize core with default priors
let core = SynapseCore()

// Apply feedback update
core.applyFeedbackUpdate(
    chosenIntent: "Technical",
    chosenTone: "Formal",
    chosenDomain: "Work",
    positive: true
)

// Compute region similarities
let regions = core.loadOrCreateRegions()
let (matrix, nearest) = core.computeRegionSimilarities(regionsIn: regions)

// Save state
core.saveWeights("~/.context-synapse/weights.json")
```

## Use Cases

- Maintaining project context across multiple coding sessions
- Tracking decisions and rationale in long-term projects
- Synchronizing context between different AI assistants
- Managing multiple concurrent projects without losing context
- Adaptive learning of user preferences over time
- ADHD-friendly context recovery after interruptions

## Project Structure

```
context-synapse/
├── Sources/
│   ├── SynapseCore/
│   │   └── SynapseCore.swift      # Core Bayesian engine
│   ├── contextsynapse/
│   │   └── main.swift              # CLI tool
│   └── ContextSynapseApp/          # macOS GUI
│       ├── AppMain.swift
│       ├── ContentView.swift
│       ├── WeightGridView.swift
│       ├── HeatmapView.swift
│       └── AppShortcutsBridge.swift
├── Tests/
│   └── BayesianConvergenceTests.swift
├── Package.swift
├── default_config.json
├── INSTALL.md
├── REVIEW.md
└── README.md
```

## Configuration

Default Bayesian priors are stored in `default_config.json`:

```json
{
  "priors": {
    "intents": {"Technical": 0.5, "Casual": 0.3, "Creative": 0.2},
    "domains": {"Work": 0.6, "Personal": 0.3, "Learning": 0.1},
    "tones": {"Formal": 0.4, "Friendly": 0.4, "Analytical": 0.2}
  },
  "fault_probability": 0.6
}
```

## Development

This project follows the "small, focused tools" philosophy. It aims to do one thing well: manage context with Bayesian learning.

### Running Tests

```bash
swift test
```

### Code Review

See [REVIEW.md](REVIEW.md) for the two-pass code review process.

## Contributing

Contributions are welcome! This project is open source and built for the community.

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) file for details

## Author

Created by mazze93 as part of a collection of tools designed to support neurodivergent developers and improve AI interaction workflows.

## Roadmap

- [x] Core Bayesian feedback engine
- [x] CLI interface with argument parsing
- [x] macOS GUI with SwiftUI
- [x] JSON-based state persistence
- [x] Cosine similarity for region matching
- [x] Comprehensive test suite
- [ ] Multi-user support
- [ ] Cloud sync (encrypted)
- [ ] Browser extension integration
- [ ] Export/import functionality
- [ ] Advanced visualization dashboards
- [ ] Integration with popular AI platforms (OpenAI, Anthropic)
- [ ] Context versioning and history
- [ ] Collaborative context sharing
