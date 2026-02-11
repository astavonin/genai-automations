# Anki Sync

Bidirectional vocabulary synchronization between local YAML files and Anki Desktop via Anki-Connect.

## Features

- **Bidirectional sync**: Push translations to Anki and pull edits back
- **Dual-direction cards**: Creates both Spanish→English and English→Spanish cards
- **Incremental sync**: Only syncs changes (new/updated/deleted entries)
- **Change detection**: Content-based hashing detects modifications
- **Atomic operations**: Safe state persistence with crash recovery
- **Dry-run mode**: Preview changes before applying
- **Conflict logging**: Track sync conflicts and resolution

## Prerequisites

1. **Anki Desktop** installed and running
2. **Anki-Connect add-on** installed (code: 2055492159)
   - Install from Anki: Tools → Add-ons → Get Add-ons → Enter code
   - Restart Anki after installation

## Installation

```bash
# Install with anki dependencies
pip install -e ".[anki]"

# For development (includes test dependencies)
pip install -e ".[anki,dev]"
```

## Quick Start

### 1. Create vocabulary file

Create a YAML file with your translations (e.g., `~/.claude/memory/spanish-vocabulary.yaml`):

```yaml
- spanish: "sí"
  english: "yes"
  example: "Sí, funciona bien"
  notes: "Affirmative response"
  tags: ["common", "basic"]

- spanish: "¿Qué tal?"
  english: "How's it going?"
  example: "¿Qué tal tu día?"
  notes: "Informal greeting"
  tags: ["greeting", "informal"]
```

### 2. Create configuration file

Create `~/.config/anki_sync/config.yaml`:

```yaml
anki:
  host: "localhost"
  port: 8765
  deck_name: "Spanish::Vocabulary"
  model_name: "SpanishVocab"

sync:
  source_file: "~/.claude/memory/spanish-vocabulary.yaml"
  state_file: "~/.config/anki_sync/sync_state.json"
```

See `anki_sync/examples/config.yaml` for full configuration options.

### 3. Initialize Anki deck

```bash
anki-sync setup
```

This creates:
- The deck specified in config (if it doesn't exist)
- A custom note model with Front/Back/Example/Notes fields

### 4. Push translations to Anki

```bash
# Preview changes
anki-sync diff

# Apply changes
anki-sync push
```

### 5. Pull Anki edits back

After editing cards in Anki:

```bash
anki-sync pull
```

## Usage

### Commands

```bash
# Initialize deck and model
anki-sync setup

# Push translations to Anki
anki-sync push

# Pull Anki changes back
anki-sync pull

# Show sync status
anki-sync status

# Preview pending changes
anki-sync diff

# Verify sync integrity
anki-sync verify
```

### Options

```bash
# Use custom config file
anki-sync --config /path/to/config.yaml push

# Dry-run mode (preview without applying)
anki-sync --dry-run push

# Verbose output (DEBUG level)
anki-sync --verbose push
```

## Configuration

### Full Configuration Example

```yaml
anki:
  # Anki-Connect connection
  host: "localhost"
  port: 8765
  timeout: 30

  # Deck and model names
  deck_name: "Spanish::Vocabulary"
  model_name: "SpanishVocab"

sync:
  # Source file (translations)
  source_file: "~/.claude/memory/spanish-vocabulary.yaml"

  # State file (mappings)
  state_file: "~/.config/anki_sync/sync_state.json"

  # Conflict log
  conflict_log: "~/.config/anki_sync/conflicts.log"

  # Auto-sync to AnkiWeb after push
  auto_sync_ankiweb: false

cards:
  # Include example field
  include_examples: true

  # Include notes field
  include_notes: true

  # Truncate long examples
  max_example_length: 200

  # Tag prefix for synced cards
  tag_prefix: "anki_sync"
```

### Config File Search Order

1. Explicit path via `--config`
2. `~/.config/anki_sync/config.yaml`
3. `./anki_sync_config.yaml`
4. Built-in defaults

## Translation File Format

YAML file with list of entries:

```yaml
- spanish: "Spanish term"
  english: "English translation"
  example: "Example sentence (optional)"
  notes: "Additional notes (optional)"
  tags: ["tag1", "tag2"]  # optional
```

**Required fields:**
- `spanish`: Spanish term (used as unique identifier after normalization)
- `english`: English translation

**Optional fields:**
- `example`: Example sentence showing usage
- `notes`: Additional notes or context
- `tags`: List of tags for categorization

## How It Works

### Push Workflow

1. Load translations from source file
2. Load sync state from state file
3. Compute diff:
   - **New entries**: In source but not in state
   - **Updated entries**: Content hash changed
   - **Deleted entries**: In state but not in source
4. Apply changes to Anki:
   - Create 2 cards per new entry (ES→EN, EN→ES)
   - Update existing cards
   - Delete removed cards
5. Update sync state incrementally (save after each batch)

### Pull Workflow

1. Query Anki for all synced notes
2. Detect changes via modification timestamps
3. Update source file with Anki changes
4. Update sync state

### Change Detection

- **Content hash**: 12-character SHA256 hash of translation content
- **Modification timestamp**: Anki's internal `mod` field
- **Source ID**: Normalized Spanish term (lowercase, stripped)

### Conflict Resolution

- **Last-writer-wins**: Pull overwrites local changes
- **Logged**: Conflicts are logged to `conflict_log` file

## State Management

### Sync State File

`~/.config/anki_sync/sync_state.json`:

```json
{
  "version": 1,
  "last_push": "2026-02-10T10:00:00+00:00",
  "last_pull": "2026-02-10T09:00:00+00:00",
  "deck_name": "Spanish::Vocabulary",
  "model_name": "SpanishVocab",
  "mappings": {
    "sí": {
      "source_id": "sí",
      "es_en_note_id": 123,
      "en_es_note_id": 456,
      "last_push_hash": "abc123def456",
      "last_pull_mod": 1234567890
    }
  }
}
```

### Atomic State Saves

- Uses write-to-temp-then-rename pattern
- Prevents corruption on crash
- Incremental saves after each batch operation

## Error Handling

### Connection Errors

If Anki-Connect is not accessible:

```
ERROR: Cannot connect to Anki-Connect at http://localhost:8765
Make sure:
  1. Anki is running
  2. Anki-Connect add-on is installed (code: 2055492159)
  3. Anki-Connect is enabled in Anki > Tools > Add-ons
```

### Validation Errors

#### Duplicate Source IDs

If multiple entries normalize to the same `source_id`:

```
ERROR: Duplicate source_id 'hola' detected:
  Entry 1: spanish='Hola'
  Entry 2: spanish='hola'
These entries would collide after normalization.
```

**Fix**: Use distinct Spanish terms or add distinguishing context.

### Partial Failures

If some notes fail to create (e.g., duplicates):

```
WARNING: Failed to create es_en card for 'hola'. Possible duplicate or validation error.
✓ Created 3 cards
✗ Failed to create 1 cards (see warnings above)
```

State is saved for successful notes only.

## Examples

See `anki_sync/examples/` for:
- `config.yaml`: Example configuration
- `vocabulary.yaml`: Example translations

## Architecture

### Module Structure

```
anki_sync/
├── __init__.py           # Package info
├── __main__.py           # Entry point
├── cli.py                # Command-line interface
├── config.py             # Configuration management
├── exceptions.py         # Exception hierarchy
├── client.py             # Anki-Connect HTTP client
├── models/               # Data models
│   ├── translation.py    # Translation dataclass
│   ├── card_mapping.py   # Mapping dataclass
│   └── sync_state.py     # State persistence
├── handlers/             # Command handlers
│   ├── setup_handler.py  # Setup command
│   ├── push_handler.py   # Push command
│   └── pull_handler.py   # Pull command
└── utils/                # Utilities
    └── logging_config.py # Logging setup
```

### Design Principles

1. **Atomic operations**: State saves are atomic to prevent corruption
2. **Incremental saves**: Save state after each batch to minimize data loss
3. **Collision detection**: Validate source_id uniqueness before sync
4. **Partial failure handling**: Handle individual note failures gracefully
5. **Error ordering**: Save translations before state to prevent divergence

## Development

### Running Tests

```bash
pytest tests/anki_sync/ -v
```

### Code Quality

```bash
# Format code
black anki_sync/

# Lint
pylint anki_sync/
flake8 anki_sync/

# Type check
mypy anki_sync/
```

### Test Coverage

```bash
pytest tests/anki_sync/ --cov=anki_sync --cov-report=html
```

## Troubleshooting

### Anki-Connect Not Responding

1. Verify Anki is running
2. Check Anki-Connect add-on is installed: Tools → Add-ons
3. Restart Anki
4. Test connection: `anki-sync verify`

### State File Corruption

If state file is corrupted:

```bash
# Backup state
cp ~/.config/anki_sync/sync_state.json{,.backup}

# Delete state (will re-sync from scratch)
rm ~/.config/anki_sync/sync_state.json

# Re-initialize
anki-sync setup
anki-sync push
```

### Notes Missing from Anki

Run verification to check consistency:

```bash
anki-sync verify
```

## License

MIT License

## Credits

Built following ci_platform_manager patterns and quality standards.

Generated via Claude Code.
