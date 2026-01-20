# ContextSynapse Extended Features Roadmap

This document details the implementation status and architecture for ContextSynapse's extended features.

## ✅ Implemented Features (v1.1)

### Export/Import Functionality

**Status:** Fully implemented

**Features:**
- Complete state export including weights, priors, regions, and metadata
- Import with two modes: replace (overwrite) or merge (average priors)
- JSON-based format with versioning
- CLI commands: `--export` and `--import`

**API:**
```swift
// Export
core.exportState(to: fileURL, metadata: ["user": "johndoe"])

// Import (replace mode)
core.importState(from: fileURL, merge: false)

// Import (merge mode - averages priors)
core.importState(from: fileURL, merge: true)
```

**CLI:**
```bash
# Export
contextsynapse --export backup.json --metadata user=johndoe

# Import
contextsynapse --import backup.json [--merge]
```

**Use Cases:**
- Backup and restore context state
- Share configurations between machines
- Migrate contexts between users
- Version control for context configurations

---

### Multi-User Support

**Status:** Fully implemented

**Features:**
- User-namespaced directories for config, regions, and logs
- User profiles with creation and last-used timestamps
- Profile management API
- Automatic profile creation on first use

**Architecture:**
```
~/Library/Application Support/ContextSynapse/
  └── users/
      ├── default/
      │   ├── profile.json
      │   ├── config.json
      │   ├── regions.json
      │   └── logs/
      ├── johndoe/
      │   ├── profile.json
      │   ├── config.json
      │   ├── regions.json
      │   └── logs/
      └── ...
```

**API:**
```swift
// Initialize with specific user
let core = SynapseCore(user: "johndoe")

// List all users
let users = core.listUsers()

// Switch users (creates new instance)
let newCore = SynapseCore.switchUser(to: "janedoe")
```

**CLI:**
```bash
# Use specific user
contextsynapse --user johndoe "Summarize this"
```

**Use Cases:**
- Multiple team members on same machine
- Different personas or contexts (work, personal, creative)
- Testing and development isolation
- Collaborative workflows without conflicts

---

### AI Platform Integration

**Status:** Fully implemented (OpenAI + Anthropic)

**Features:**
- Protocol-based design for extensibility
- OpenAI client with GPT models support
- Anthropic client with Claude models support
- Async completion handlers
- Configurable models and token limits

**API:**
```swift
// OpenAI
let openai = OpenAIClient(
    apiKey: "sk-...",
    model: "gpt-4",
    maxTokens: 1000
)

// Anthropic
let anthropic = AnthropicClient(
    apiKey: "sk-ant-...",
    model: "claude-3-sonnet-20240229",
    maxTokens: 1000
)

// Send prompt
openai.sendPrompt(assembledPrompt) { result in
    switch result {
    case .success(let response):
        print(response)
    case .failure(let error):
        print("Error: \(error)")
    }
}
```

**Integration Pattern:**
```swift
// Assemble context-aware prompt
let weights = core.loadOrCreateDefaultWeights()
let intent = core.weightedPick(weights.intents) ?? "Create"
let tone = core.weightedPick(weights.tones) ?? "Concise"
let domain = core.weightedPick(weights.domains) ?? "Work"
let prompt = "[\(tone)] [\(intent)] [\(domain)]: \(userQuery)"

// Send to AI
aiClient.sendPrompt(prompt) { result in
    // Handle response and apply feedback
}
```

**Use Cases:**
- Direct AI integration without manual copy-paste
- Context-aware prompt assembly
- Feedback loop integration (rate AI responses)
- Multi-platform AI orchestration

---

## 🚧 Partially Implemented / Foundations Laid

### Advanced Visualization Dashboards

**Current Status:**
- ✅ Basic heatmap visualization (SwiftUI)
- ✅ Weight grid display
- ✅ Real-time similarity matrix
- ❌ Prior evolution tracking over time
- ❌ Feedback success rate metrics
- ❌ Historical trend analysis

**Next Steps:**
1. Add timestamped snapshots of priors to logs
2. Create analytics structures for tracking changes
3. Add SwiftUI Charts views for:
   - Prior probability trends
   - Weight evolution over time
   - Feedback success rates
   - Usage patterns (most-used intents/tones/domains)

**Proposed API:**
```swift
// Track prior evolution
struct PriorSnapshot: Codable {
    let timestamp: String
    let priors: Priors
}

// Get evolution data
func getPriorEvolution(days: Int) -> [PriorSnapshot]

// Get feedback metrics
struct FeedbackMetrics {
    let totalFeedback: Int
    let positiveCount: Int
    let negativeCount: Int
    let topIntents: [(String, Int)]
}

func getFeedbackMetrics(since: Date) -> FeedbackMetrics
```

---

## 📋 Planned Features

### Cloud Sync (Encrypted)

**Status:** Architecture documented, needs implementation

**Requirements:**
- End-to-end encryption (AES-256)
- Conflict resolution strategy
- Sync protocol (REST or WebSocket)
- Backend storage (CloudKit, Firebase, or custom)

**Proposed Architecture:**
```swift
protocol CloudSyncProvider {
    func upload(bundle: ExportBundle, encrypted: Bool) async throws
    func download() async throws -> ExportBundle
    func listVersions() async throws -> [String]
}

class CloudKitSyncProvider: CloudSyncProvider { ... }
class FirebaseSyncProvider: CloudSyncProvider { ... }

// Encryption
class EncryptionManager {
    func encrypt(data: Data, key: String) throws -> Data
    func decrypt(data: Data, key: String) throws -> Data
}
```

**Implementation Steps:**
1. Add encryption utilities (CryptoKit)
2. Implement sync protocol
3. Add conflict resolution (last-write-wins or merge strategies)
4. Create CloudKit/Firebase providers
5. Add sync settings to config
6. Implement background sync

**Security Considerations:**
- Never sync unencrypted data
- Key derivation from user password
- Optional local key storage in Keychain
- Sync only on explicit user action (no auto-sync without consent)

---

### Browser Extension Integration

**Status:** Architecture documented, needs implementation

**Proposed Architecture:**

**Communication Protocol:**
- Local WebSocket server in ContextSynapse
- Browser extension connects via localhost:PORT
- Message-based JSON protocol

**Message Types:**
```json
// Request: Get context for current page
{
  "type": "getContext",
  "url": "https://github.com/...",
  "title": "Repository Page"
}

// Response: Context recommendation
{
  "type": "contextRecommendation",
  "intent": "Analyze",
  "tone": "Technical",
  "domain": "Work",
  "prompt": "[Technical] [Analyze] [Work]: ..."
}

// Request: Apply feedback
{
  "type": "feedback",
  "intent": "Analyze",
  "tone": "Technical",
  "domain": "Work",
  "positive": true
}
```

**Browser Extension Components:**
1. **Background Script:** Maintains WebSocket connection
2. **Content Script:** Extracts page context
3. **Popup UI:** Shows recommendations, allows feedback
4. **Options Page:** Configure connection settings

**Implementation Steps:**
1. Add WebSocket server to SynapseCore
2. Define message protocol
3. Create browser extension (manifest v3)
4. Implement bidirectional communication
5. Add page context extraction
6. Create popup UI for recommendations

**Use Cases:**
- ChatGPT/Claude integration (auto-populate prompts)
- GitHub code review context
- Documentation writing assistance
- Research note-taking with context

---

## 🎯 Future Considerations

### Context Versioning and History

**Concept:** Track changes to weights and priors over time, allow rollback

**Features:**
- Automatic snapshots on significant changes
- Manual checkpoint creation
- Rollback to previous state
- Diff visualization between versions

**API:**
```swift
// Create checkpoint
core.createCheckpoint(name: "Before major refactor")

// List checkpoints
let checkpoints = core.listCheckpoints()

// Restore checkpoint
core.restoreCheckpoint(id: "checkpoint-id")

// Compare versions
let diff = core.compareVersions(from: "v1", to: "v2")
```

---

### Collaborative Context Sharing

**Concept:** Share context configurations with team members

**Features:**
- Export bundles with sharing permissions
- Import with attribution
- Merge multiple team members' contexts
- Collaborative priors (weighted by team consensus)

**Use Cases:**
- Team onboarding (share expert's context)
- Project handoffs
- Distributed teams sharing best practices
- Community-curated contexts for specific domains

---

## Testing Strategy

All implemented features have comprehensive test coverage:

### Export/Import Tests
- `testExportStateCreatesValidFile` - Validates export format
- `testImportStateRestoresData` - Verifies import accuracy
- `testImportStateMergesDataCorrectly` - Tests merge logic

### Multi-User Tests
- Tests covered in existing test suite with unique folder names
- User profile creation and updates tested implicitly
- Future: Add explicit multi-user scenario tests

### AI Integration Tests
- Mock-based testing (avoid real API calls in tests)
- Future: Add integration tests with test API keys

---

## Migration Guide

### Upgrading from v1.0 to v1.1

**Breaking Changes:**
- `SynapseCore()` now defaults to user="default" instead of shared directory
- Existing data will be in root directory, not under users/default/

**Migration Steps:**

Option 1: Manual migration
```bash
# Backup existing data
contextsynapse --export backup-v1.0.json

# Initialize new user
contextsynapse --user default "test"

# Import data
contextsynapse --user default --import backup-v1.0.json
```

Option 2: Automatic migration (recommended)
```swift
// Run once to migrate existing data
let core = SynapseCore(user: "default")
// Existing data will be accessible as before
```

---

## Performance Considerations

### Export/Import
- Large export files (>1MB) may take several seconds
- Consider streaming for very large datasets
- Compression could reduce file sizes by 60-70%

### Multi-User
- Each user's data is isolated (no cross-contamination)
- Disk space scales linearly with users
- Profile listing scans directory (cache if >100 users)

### AI Integration
- Network latency depends on provider
- Implement timeouts (30s recommended)
- Consider request queuing for high volume
- Rate limiting per provider's requirements

---

## Contributing

To add new features:

1. Follow the existing pattern (see Export/Import as reference)
2. Add protocol/struct definitions first
3. Implement core functionality
4. Add comprehensive tests
5. Update CLI if applicable
6. Document in README and ROADMAP
7. Add example usage

For questions or suggestions, open an issue on GitHub.
