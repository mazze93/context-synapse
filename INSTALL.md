# Context Synapse Installation Guide

Complete installation and build instructions for the Context Synapse Swift project.

## Requirements

### System Requirements
- **macOS**: 12.0+ (Monterey or later)
- **Xcode**: 14.0+ (for development)
- **Swift**: 5.7+ toolchain
- **Disk Space**: ~50MB for source + build artifacts

### Optional
- Apple Developer account (for signing/notarizing the macOS app)
- Git (for cloning the repository)

## Installation Methods

### Method 1: Build from Source (Recommended)

#### 1. Clone the Repository

```bash
git clone https://github.com/mazze93/context-synapse.git
cd context-synapse
```

#### 2. Build the CLI Tool

**Debug Build** (for development):
```bash
swift build

# Run the CLI
.build/debug/contextsynapse --help
```

**Release Build** (optimized):
```bash
swift build -c release

# Install to system path (optional)
sudo cp .build/release/contextsynapse /usr/local/bin/
```

#### 3. Build the GUI Application

**Option A: Using Xcode**
```bash
# Open the project in Xcode
open Package.swift

# In Xcode:
# 1. Select "ContextSynapseApp" scheme
# 2. Product → Build (⌘B)
# 3. Product → Run (⌘R)
```

**Option B: Command Line**
```bash
swift build -c release --product ContextSynapseApp

# The app bundle will be in:
# .build/release/ContextSynapseApp.app
```

### Method 2: Quick Start with Swift PM

```bash
# Build and run CLI in one command
swift run contextsynapse --help

# Run with specific arguments
swift run contextsynapse --feedback positive --intent Technical --domain Work
```

## Usage

### CLI Usage Examples

```bash
# Apply positive feedback
contextsynapse --feedback positive --intent Technical --domain Work --tone Formal

# Apply negative feedback
contextsynapse --feedback negative --intent Casual --tone Friendly

# View current weights and state
contextsynapse --status

# Use custom config file
contextsynapse --config ~/my-config.json --feedback positive --intent Learning
```

### GUI Application

1. Launch the ContextSynapseApp
2. Use the interactive weight grid to visualize context weights
3. View real-time heatmap of intent probabilities
4. Use keyboard shortcuts:
   - `⌘+P`: Apply positive feedback
   - `⌘+N`: Apply negative feedback
   - `⌘+R`: Reload configuration

## Configuration

### Default Configuration Location

```
~/Library/Application Support/ContextSynapse/
├── config.json          # User configuration and weights
├── regions.json         # Context region vectors
└── logs/               # Application logs
```

### Configuration File Format

The `default_config.json` in the repository provides Bayesian priors:

```json
{
  "priors": {
    "intents": {
      "Technical": 0.5,
      "Casual": 0.3,
      "Creative": 0.2
    },
    "domains": {
      "Work": 0.6,
      "Personal": 0.3,
      "Learning": 0.1
    },
    "tones": {
      "Formal": 0.4,
      "Friendly": 0.4,
      "Analytical": 0.2
    }
  },
  "fault_probability": 0.6
}
```

### Customizing Configuration

1. Copy `default_config.json` to your config directory:
   ```bash
   mkdir -p "~/Library/Application Support/ContextSynapse"
   cp default_config.json "~/Library/Application Support/ContextSynapse/config.json"
   ```

2. Edit the file to adjust:
   - Prior probabilities for intents, domains, and tones
   - Fault probability (for testing resilience)
   - Add custom intents/domains/tones

## Testing

### Running Tests

```bash
# Run all tests
swift test

# Run specific test
swift test --filter BayesianConvergenceTests

# Run with verbose output
swift test --verbose
```

### Test Coverage

The test suite includes:
- Bayesian convergence validation
- Fault injection handling
- Cosine similarity computation
- Region similarity matrix generation
- Weight update correctness

## Troubleshooting

### Common Issues

**Build fails with "Cannot find module"**:
```bash
# Clean build artifacts
swift package clean
swift package resolve
swift build
```

**"Command not found: contextsynapse"**:
```bash
# Ensure the binary is in your PATH
echo $PATH

# Or use the full path
.build/release/contextsynapse --help
```

**GUI app won't launch**:
- Ensure macOS 12.0+ 
- Check Console.app for crash logs
- Try building in Xcode for better error messages

**Permission denied when installing to /usr/local/bin**:
```bash
# Use sudo
sudo cp .build/release/contextsynapse /usr/local/bin/

# Or install to user bin
mkdir -p ~/bin
cp .build/release/contextsynapse ~/bin/
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
```

### Getting Help

- **Documentation**: See [README.md](README.md) for project overview
- **Code Review**: See [REVIEW.md](REVIEW.md) for architecture details
- **Issues**: Report bugs on [GitHub Issues](https://github.com/mazze93/context-synapse/issues)

## Uninstallation

```bash
# Remove CLI tool
sudo rm /usr/local/bin/contextsynapse

# Remove configuration and data
rm -rf ~/Library/Application\ Support/ContextSynapse/

# Remove GUI app
rm -rf /Applications/ContextSynapseApp.app
```

## Development

### Project Structure

```
context-synapse/
├── Package.swift                   # Swift Package Manager manifest
├── Sources/
│   ├── SynapseCore/               # Core Bayesian engine
│   ├── contextsynapse/            # CLI executable
│   └── ContextSynapseApp/         # macOS GUI app
├── Tests/
│   └── BayesianConvergenceTests/  # Test suite
└── default_config.json            # Default configuration
```

### Building for Distribution

```bash
# Build release binary with optimizations
swift build -c release -Xswiftc -O

# Create distributable archive
tar -czf context-synapse-macos.tar.gz \
  -C .build/release \
  contextsynapse
```

## Next Steps

- Read [README.md](README.md) for usage examples and architecture
- See [REVIEW.md](REVIEW.md) for code review and troubleshooting
- Explore the source code in `Sources/`
- Run tests to understand the Bayesian feedback system
