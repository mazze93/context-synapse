# Context Synapse

AI context management and synchronization tool for maintaining coherent conversation state across sessions.

## Overview

Context Synapse is a lightweight Python tool designed to help manage and synchronize contextual information across AI conversation sessions. It's particularly useful for individuals with ADHD or anyone who needs to maintain consistent context across multiple interrupted work sessions.

## Features

- **Context Persistence**: Save and restore conversation context between sessions
- **State Management**: Track project state, decisions, and progress
- **ADHD-Friendly**: Designed with neurodivergent users in mind
- **Privacy-Focused**: Local storage with optional encrypted backups
- **Lightweight**: Minimal dependencies and system overhead

## Installation

```bash
# Clone the repository
git clone https://github.com/mazze93/context-synapse.git
cd context-synapse

# Install dependencies
pip install -r requirements.txt
```

## Quick Start

```python
from context_synapse import ContextManager

# Initialize context manager
ctx = ContextManager()

# Save context
ctx.save({
    'project': 'my-project',
    'state': 'in-progress',
    'notes': 'Working on feature X'
})

# Load context later
context = ctx.load('my-project')
```

## Use Cases

- Maintaining project context across multiple coding sessions
- Tracking decisions and rationale in long-term projects
- Synchronizing context between different AI assistants
- Managing multiple concurrent projects without losing context

## Project Structure

```
context-synapse/
├── context_synapse/     # Main package
├── tests/               # Test suite
├── docs/                # Documentation
├── examples/            # Example usage
└── README.md            # This file
```

## Development

This project follows the "small, focused tools" philosophy. It aims to do one thing well: manage context.

```bash
# Run tests
python -m pytest

# Run linter
flake8 context_synapse
```

## Contributing

Contributions are welcome! This project is open source and built for the community.

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

MIT License - see LICENSE file for details

## Author

Created by mazze93 as part of a collection of tools designed to support neurodivergent developers and improve AI interaction workflows.

## Roadmap

- [ ] Basic context save/load functionality
- [ ] Encrypted storage support
- [ ] CLI interface
- [ ] Integration with popular AI platforms
- [ ] Context versioning and history
- [ ] Multi-project context management
- [ ] Export/import functionality
