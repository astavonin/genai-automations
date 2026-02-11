# Anki Sync - Claude Code Integration

## Overview

`anki_sync` is a Python application for bidirectional vocabulary synchronization between local YAML files and Anki Desktop via the Anki-Connect API.

**Location:** `/home/astavonin/projects/genai-automations/anki_sync/`

**Status:** ✅ Implementation complete, ready for code review

---

## Quick Reference

### Installation

```bash
# Install with anki dependencies
pip install -e ".[anki]"

# For development (includes test dependencies)
pip install -e ".[dev,anki]"
```

### Basic Usage

```bash
# Initialize Anki deck and model
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

### Global Options

```bash
--config PATH     # Use custom config file
--dry-run         # Preview without applying changes
--verbose         # Enable DEBUG logging
```

---

## Architecture

### Module Structure

```
anki_sync/
├── __init__.py              # Package info (version 0.1.0)
├── __main__.py              # Entry point for python -m anki_sync
├── cli.py                   # CLI with command dispatch
├── config.py                # Config dataclass with validation
├── exceptions.py            # Exception hierarchy
├── client.py                # AnkiConnectClient (HTTP wrapper)
├── models/                  # Data models
│   ├── translation.py       # Translation dataclass
│   ├── card_mapping.py      # CardMapping dataclass
│   └── sync_state.py        # SyncState with atomic saves
├── handlers/                # Command handlers
│   ├── setup_handler.py     # Setup command
│   ├── push_handler.py      # Push sync logic
│   └── pull_handler.py      # Pull sync logic
├── utils/                   # Utilities
│   └── logging_config.py    # Logging setup
└── formatters/              # Placeholder for future formatters
```

### Design Principles

1. **Atomic operations** - State saves use write-to-temp-then-rename
2. **Incremental saves** - Save state after each batch operation
3. **Collision detection** - Validate source_id uniqueness before sync
4. **Partial failure handling** - Handle individual note failures gracefully
5. **Error ordering** - Save translations before state to prevent divergence

---

## Configuration

### Config File Locations (search order)

1. Explicit path: `--config /path/to/config.yaml`
2. User config: `~/.config/anki_sync/config.yaml`
3. Current directory: `./anki_sync_config.yaml`
4. Built-in defaults

### Example Configuration

See `anki_sync/examples/config.yaml` for full configuration.

### Required Files

- **Source file**: YAML file with translations (default: `~/.claude/memory/spanish-vocabulary.yaml`)
- **State file**: JSON file with sync state (default: `~/.config/anki_sync/sync_state.json`)
- **Conflict log**: Log file for conflicts (default: `~/.config/anki_sync/conflicts.log`)

---

## Prerequisites

### Anki-Connect Setup

1. Install Anki Desktop
2. Install Anki-Connect add-on (code: 2055492159)
   - Anki → Tools → Add-ons → Get Add-ons → Enter code
3. Restart Anki
4. Verify: `anki-sync verify`

### Translation File Format

YAML list of entries:

```yaml
- spanish: "sí"
  english: "yes"
  example: "Sí, funciona bien"  # optional
  notes: "Affirmative response"  # optional
  tags: ["common", "basic"]      # optional
```

**Required fields:** `spanish`, `english`

---

## Key Features

### Bidirectional Sync

- **Push** (`anki-sync push`): Sync translations → Anki
  - Creates 2 cards per entry (ES→EN, EN→ES)
  - Detects new/updated/deleted entries
  - Updates existing cards
  - Saves state incrementally

- **Pull** (`anki-sync pull`): Sync Anki → translations
  - Detects modified notes via timestamps
  - Updates source YAML file
  - Last-writer-wins conflict resolution

### Change Detection

- **Content hash**: 12-character SHA256 hash
- **Modification timestamp**: Anki's `mod` field
- **Source ID**: Normalized Spanish term (lowercase, stripped)

### Safety Features

- **Dry-run mode**: Preview changes with `--dry-run`
- **Atomic writes**: State file corruption protection
- **Incremental saves**: Minimize data loss on crash
- **Collision detection**: Prevent duplicate source_ids
- **Partial failure handling**: Continue on individual errors

---

## Development

### Running Tests

```bash
# All tests
pytest tests/anki_sync/ -v

# Specific test file
pytest tests/anki_sync/test_models.py -v

# With coverage
pytest tests/anki_sync/ --cov=anki_sync --cov-report=html
```

### Code Quality

```bash
# Format
black anki_sync/

# Lint
pylint anki_sync/
flake8 anki_sync/

# Type check
mypy anki_sync/
```

### Test Coverage

- **54 tests** covering:
  - Models (Translation, CardMapping, SyncState)
  - Config (loading, validation, search order)
  - Client (all API methods, error handling)
  - Handlers (setup, push, pull)
  - Edge cases (collisions, partial failures)

---

## Error Handling

### Common Errors

**Cannot connect to Anki-Connect:**
```
ERROR: Cannot connect to Anki-Connect at http://localhost:8765
```
**Fix:** Ensure Anki is running with Anki-Connect installed.

**Duplicate source_id:**
```
ERROR: Duplicate source_id 'hola' detected:
  Entry 1: spanish='Hola'
  Entry 2: spanish='hola'
```
**Fix:** Use distinct Spanish terms.

**Source file not found:**
```
ERROR: Source file does not exist: /path/to/file.yaml
```
**Fix:** Create the file or adjust `sync.source_file` in config.

### Error Recovery

**State file corrupted:**
```bash
# Backup state
cp ~/.config/anki_sync/sync_state.json{,.backup}

# Delete state (will re-sync from scratch)
rm ~/.config/anki_sync/sync_state.json

# Re-initialize
anki-sync setup
anki-sync push
```

---

## Integration with Claude Code Workflow

### Phase 4: Implementation ✅ COMPLETE

The anki_sync application has been fully implemented following the approved design document.

### Phase 5: Code Review (NEXT)

Ready for code review using the reviewer agent:

```bash
# Use reviewer agent with review checklist
~/.claude/agents/reviewer.md
~/.claude/skills/domains/quality-attributes/references/review-checklist.md
```

### Phase 6: Verification (PENDING)

After code review approval:

1. **Run tests**: `pytest tests/anki_sync/ -v`
2. **Run linters**: `pylint anki_sync/`, `flake8 anki_sync/`
3. **Run type checker**: `mypy anki_sync/`
4. **Format code**: `black anki_sync/`
5. **Integration test**: Test with real Anki instance

### Phase 7: Commit (PENDING USER)

User handles git commits after verification.

---

## Design Review Fixes Applied

All fixes from design review have been implemented:

### Critical ✅
1. `api_version` attribute instead of `version` method
2. Atomic state file writes (temp + rename)
3. Incremental state saves in push handler

### Major ✅
4. Partial failure handling (null ID detection)
5. Save translations before state in pull handler
6. Logging configuration module
7. Source ID collision detection
8. `responses` library in dev dependencies

### Minor ✅
9. `datetime.now(timezone.utc)` instead of `utcnow()`
10. 12-character content hash

---

## Dependencies

### Runtime (anki group)
- `requests>=2.31.0` - HTTP client for Anki-Connect

### Development (dev group)
- `pytest>=7.0` - Testing framework
- `pytest-cov>=4.0` - Coverage reporting
- `black>=23.0` - Code formatter
- `flake8>=6.0` - Linter
- `mypy>=1.0` - Type checker
- `pylint>=3.0` - Linter
- `types-PyYAML>=6.0` - Type stubs
- `responses>=0.25.0` - HTTP mocking for tests

### Built-in (no install required)
- `PyYAML>=5.4` - YAML parsing (from ci_platform_manager)

---

## File Manifest

### Package (17 files)
- Core: `__init__.py`, `__main__.py`, `cli.py`, `config.py`, `exceptions.py`, `client.py`
- Models: `translation.py`, `card_mapping.py`, `sync_state.py`
- Handlers: `setup_handler.py`, `push_handler.py`, `pull_handler.py`
- Utils: `logging_config.py`
- Placeholders: `formatters/__init__.py`

### Tests (8 files)
- `conftest.py` (fixtures)
- `test_models.py`, `test_config.py`, `test_client.py`
- `test_setup_handler.py`, `test_push_handler.py`, `test_pull_handler.py`

### Documentation (5 files)
- `README.md` - User documentation
- `IMPLEMENTATION_SUMMARY.md` - Implementation details
- `CLAUDE.md` - This file (Claude Code integration)
- `anki_sync/examples/config.yaml` - Example config
- `anki_sync/examples/vocabulary.yaml` - Example translations

### Modified (1 file)
- `pyproject.toml` - Added anki_sync script and dependencies

---

## Troubleshooting

### Import Errors

```bash
# Verify package imports
python3 -c "import anki_sync; print(anki_sync.__version__)"

# Verify models import
python3 -c "from anki_sync.models import Translation"

# Verify CLI works
python3 -m anki_sync --help
```

### Missing Dependencies

```bash
# Install package with dependencies
pip install -e ".[anki,dev]"
```

### Test Failures

```bash
# Run tests with verbose output
pytest tests/anki_sync/ -v -s

# Run specific test
pytest tests/anki_sync/test_models.py::test_translation_content_hash -v
```

---

## Related Documentation

- **User Guide**: `anki_sync/README.md`
- **Implementation Details**: `anki_sync/IMPLEMENTATION_SUMMARY.md`
- **Design Document**: `planning/genai-automations/anki-sync/design/implementation-design.md`
- **Examples**: `anki_sync/examples/`

---

## Contact

For issues, questions, or contributions related to this module:

1. Check documentation: `anki_sync/README.md`
2. Review design: `planning/genai-automations/anki-sync/design/implementation-design.md`
3. Consult implementation summary: `anki_sync/IMPLEMENTATION_SUMMARY.md`

---

**Status:** ✅ Implementation complete, ready for code review

**Next Step:** Phase 5 - Code Review (use reviewer agent)
