# Context Synapse — Installation Guide

## Requirements

- **macOS**: 13 (Ventura) or later
- **Swift**: 5.8+ toolchain — ships with Xcode 15+, or install the [standalone Swift toolchain](https://swift.org/download/)
- **Xcode**: 15+ (required only for the GUI app or for Xcode-based development)
- **Disk space**: ~50 MB for source + build artifacts

No external package dependencies. `swift package resolve` is a no-op beyond the standard library.

---

## CLI — build from source

### 1. Clone

```bash
git clone https://github.com/mazze93/context-synapse.git
cd context-synapse
```

### 2. Build

```bash
# Release build (optimized — recommended)
swift build -c release --product contextsynapse

# Debug build (for development)
swift build --product contextsynapse
```

### 3. Run

```bash
.build/release/contextsynapse "Draft a reply to this email"
# → [Concise] [Create] [Work]: Draft a reply to this email
```

### 4. Install system-wide (optional)

```bash
sudo cp .build/release/contextsynapse /usr/local/bin/

# Or install to ~/bin without sudo
mkdir -p ~/bin
cp .build/release/contextsynapse ~/bin/
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

---

## GUI app — build from source

The GUI (`ContextSynapseApp`) is a SwiftUI executable. Use Xcode to build a proper `.app` bundle with code signing; SPM produces an unsigned command-line executable.

**Option A — Xcode (recommended for running the app)**

```bash
open Package.swift       # opens the package in Xcode
```

In Xcode:
1. Select the `ContextSynapseApp` scheme.
2. **Product → Build** (⌘B) or **Product → Run** (⌘R).

**Option B — SPM command line** (produces an unsigned executable, not an `.app` bundle)

```bash
swift build -c release --product ContextSynapseApp
.build/release/ContextSynapseApp
```

---

## Build all targets

```bash
swift build -c release    # builds SynapseCore, contextsynapse, and ContextSynapseApp
```

---

## Run the test suite

```bash
swift build               # required — some tests invoke the CLI binary directly
swift test --parallel
swift test --filter BayesianConvergenceTests   # run a specific suite
```

---

## CLI reference (quick)

```bash
# Assemble a prompt (stochastic picks from current weights)
contextsynapse "your query"

# Force specific dimensions
contextsynapse "your query" --intent Create --tone Technical --domain Work

# Apply positive / negative feedback
contextsynapse "your query" --feedback good
contextsynapse "your query" --feedback bad

# Contextual triggers
contextsynapse "your query" --app Notes --focus DoNotDisturb --time 14:30

# Multi-user namespaces
contextsynapse "your query" --user alice

# Export state
contextsynapse --export snapshot.json --metadata project=myapp

# Import state (replace or merge)
contextsynapse --import snapshot.json
contextsynapse --import snapshot.json --merge

# Fault injection (resilience research)
CONTEXT_SYNAPSE_FAULT_PROB=0.4 contextsynapse "test query"
```

Full flag reference is in [README.md](README.md).

---

## State location

```
~/Library/Application Support/ContextSynapse/
└── users/
    └── default/
        ├── config.json     # weights + Bayesian priors (plain JSON)
        ├── regions.json    # named embedding vectors
        └── logs/           # per-run JSON logs
```

On first run, defaults are seeded automatically from the built-in `defaultWeights()`. You can also copy `default_config.json` from the repository to pre-populate the config:

```bash
mkdir -p ~/Library/Application\ Support/ContextSynapse/users/default
cp default_config.json ~/Library/Application\ Support/ContextSynapse/users/default/config.json
```

The `config.json` format (all values start at `1.0` — uniform priors):

```json
{
  "intents": { "Summarize": 1.0, "Create": 1.0, "Analyze": 1.0, "Brainstorm": 1.0, "ActionableSteps": 1.0 },
  "tones":   { "Concise": 1.0, "Technical": 1.0, "Casual": 1.0, "Persuasive": 1.0, "Creative": 1.0 },
  "domains": { "Work": 1.0, "Personal": 1.0, "GameDesign": 1.0, "Marketing": 1.0, "Writing": 1.0 },
  "triggers": {
    "app.Mail": { "Create": 1.6, "ActionableSteps": 1.2 },
    "app.Notes": { "Create": 1.7, "Creative": 1.4 },
    "time.morning": { "Analyze": 1.25 },
    "focus.DoNotDisturb": { "Concise": 1.6 }
  },
  "priors": {
    "intents":  { "Summarize": {"alpha": 1, "beta": 1}, "Create": {"alpha": 1, "beta": 1}, "Analyze": {"alpha": 1, "beta": 1}, "Brainstorm": {"alpha": 1, "beta": 1}, "ActionableSteps": {"alpha": 1, "beta": 1} },
    "tones":    { "Concise": {"alpha": 1, "beta": 1}, "Technical": {"alpha": 1, "beta": 1}, "Casual": {"alpha": 1, "beta": 1}, "Persuasive": {"alpha": 1, "beta": 1}, "Creative": {"alpha": 1, "beta": 1} },
    "domains":  { "Work": {"alpha": 1, "beta": 1}, "Personal": {"alpha": 1, "beta": 1}, "GameDesign": {"alpha": 1, "beta": 1}, "Marketing": {"alpha": 1, "beta": 1}, "Writing": {"alpha": 1, "beta": 1} }
  }
}
```

---

## Troubleshooting

**Build fails with "Cannot find module"**

```bash
swift package clean
swift package resolve
swift build -c release
```

**"command not found: contextsynapse"**

```bash
# Confirm binary exists
ls .build/release/contextsynapse

# Use absolute path, or install to PATH (see step 4 above)
```

**GUI app crashes on launch**

- Confirm macOS 13+
- Check Console.app for crash reports
- Build in Xcode for richer diagnostics (Xcode scheme → Product → Run)

**Permission denied installing to /usr/local/bin**

Use `sudo`, or install to `~/bin` (no sudo required — see step 4 above).

---

## Uninstall

```bash
# Remove CLI
sudo rm /usr/local/bin/contextsynapse

# Remove all state and logs
rm -rf ~/Library/Application\ Support/ContextSynapse/
```

---

## Security

See [SECURITY.md](SECURITY.md) for the vulnerability disclosure policy, release artifact verification steps (SHA-256, SBOM, notarization), and supported versions.
