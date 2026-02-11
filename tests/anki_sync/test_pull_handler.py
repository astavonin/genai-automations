"""Tests for pull handler."""

import yaml

from anki_sync.handlers import PullHandler
from anki_sync.models import CardMapping, SyncState


def test_pull_handler_no_changes(temp_config, mock_anki_client):
    """Test pull when no changes in Anki."""
    handler = PullHandler(temp_config)
    handler.client = mock_anki_client

    # Setup state with mapping
    state = SyncState()
    state.mappings["hola"] = CardMapping(
        source_id="hola",
        es_en_note_id=1,
        en_es_note_id=2,
        last_push_hash="hash",
        last_pull_mod=1000,
    )
    state.save(temp_config.state_file)

    # Setup translations
    trans = [{"spanish": "Hola", "english": "Hello"}]
    with open(temp_config.source_file, "w", encoding="utf-8") as f:
        yaml.safe_dump(trans, f)

    # Mock Anki responses - same mod time
    mock_anki_client.find_notes.return_value = [1, 2]
    mock_anki_client.notes_info.return_value = [
        {"noteId": 1, "mod": 1000, "fields": {}},  # Same mod time
        {"noteId": 2, "mod": 1000, "fields": {}},
    ]

    handler.execute()

    # Source file should not change
    with open(temp_config.source_file, "r", encoding="utf-8") as f:
        result = yaml.safe_load(f)
    assert result == trans


def test_pull_handler_modified_notes(temp_config, mock_anki_client):
    """Test pull when notes are modified in Anki."""
    handler = PullHandler(temp_config)
    handler.client = mock_anki_client

    # Setup state
    state = SyncState()
    state.mappings["hola"] = CardMapping(
        source_id="hola",
        es_en_note_id=1,
        en_es_note_id=2,
        last_push_hash="hash",
        last_pull_mod=1000,
    )
    state.save(temp_config.state_file)

    # Setup translations
    trans = [{"spanish": "Hola", "english": "Hello", "example": "", "notes": "", "tags": []}]
    with open(temp_config.source_file, "w", encoding="utf-8") as f:
        yaml.safe_dump(trans, f)

    # Mock Anki responses - modified note
    mock_anki_client.find_notes.return_value = [1]
    mock_anki_client.notes_info.return_value = [
        {
            "noteId": 1,
            "mod": 2000,  # Higher mod time
            "fields": {
                "Front": {"value": "Hola"},
                "Back": {"value": "Hi"},  # Changed
                "Example": {"value": ""},
                "Notes": {"value": ""},
            },
        }
    ]

    handler.execute()

    # Check translation was updated
    with open(temp_config.source_file, "r", encoding="utf-8") as f:
        result = yaml.safe_load(f)
    assert result[0]["english"] == "Hi"

    # Check state was updated
    state = SyncState.load(temp_config.state_file)
    mapping = state.get_mapping("hola")
    assert mapping.last_pull_mod == 2000


def test_pull_handler_updates_both_directions(temp_config, mock_anki_client):
    """Test pull correctly handles updates to both card directions."""
    handler = PullHandler(temp_config)
    handler.client = mock_anki_client

    state = SyncState()
    state.mappings["hola"] = CardMapping(
        source_id="hola",
        es_en_note_id=1,
        en_es_note_id=2,
        last_push_hash="hash",
        last_pull_mod=1000,
    )
    state.save(temp_config.state_file)

    trans = [{"spanish": "Hola", "english": "Hello", "example": "", "notes": "", "tags": []}]
    with open(temp_config.source_file, "w", encoding="utf-8") as f:
        yaml.safe_dump(trans, f)

    # Spanish->English card modified
    mock_anki_client.find_notes.return_value = [1]
    mock_anki_client.notes_info.return_value = [
        {
            "noteId": 1,  # ES->EN
            "mod": 2000,
            "fields": {
                "Front": {"value": "Hola"},
                "Back": {"value": "Hi"},
                "Example": {"value": "¡Hola!"},
                "Notes": {"value": "common"},
            },
        }
    ]

    handler.execute()

    with open(temp_config.source_file, "r", encoding="utf-8") as f:
        result = yaml.safe_load(f)
    assert result[0]["english"] == "Hi"
    assert result[0]["example"] == "¡Hola!"
    assert result[0]["notes"] == "common"


def test_pull_handler_dry_run(temp_config, mock_anki_client):
    """Test pull in dry-run mode."""
    handler = PullHandler(temp_config, dry_run=True)
    handler.client = mock_anki_client

    state = SyncState()
    state.mappings["hola"] = CardMapping(
        source_id="hola",
        es_en_note_id=1,
        en_es_note_id=2,
        last_push_hash="hash",
        last_pull_mod=1000,
    )
    state.save(temp_config.state_file)

    trans = [{"spanish": "Hola", "english": "Hello"}]
    with open(temp_config.source_file, "w", encoding="utf-8") as f:
        yaml.safe_dump(trans, f)

    mock_anki_client.find_notes.return_value = [1]
    mock_anki_client.notes_info.return_value = [
        {
            "noteId": 1,
            "mod": 2000,
            "fields": {"Front": {"value": "Hola"}, "Back": {"value": "Hi"}},
        }
    ]

    handler.execute()

    # Source should not change
    with open(temp_config.source_file, "r", encoding="utf-8") as f:
        result = yaml.safe_load(f)
    assert result[0]["english"] == "Hello"  # Unchanged


def test_pull_handler_no_synced_notes(temp_config, mock_anki_client):
    """Test pull when no synced notes found."""
    handler = PullHandler(temp_config)
    handler.client = mock_anki_client

    mock_anki_client.find_notes.return_value = []

    handler.execute()  # Should not raise

    mock_anki_client.notes_info.assert_not_called()


def test_pull_handler_source_id_remapping(temp_config, mock_anki_client):
    """Test pull when Spanish term changes in Anki (source_id remapping)."""
    handler = PullHandler(temp_config)
    handler.client = mock_anki_client

    # Setup state with mapping for "hola"
    state = SyncState()
    state.mappings["hola"] = CardMapping(
        source_id="hola",
        es_en_note_id=1,
        en_es_note_id=2,
        last_push_hash="hash",
        last_pull_mod=1000,
    )
    state.save(temp_config.state_file)

    # Setup translations
    trans = [{"spanish": "Hola", "english": "Hello", "example": "", "notes": "", "tags": []}]
    with open(temp_config.source_file, "w", encoding="utf-8") as f:
        yaml.safe_dump(trans, f)

    # Mock Anki responses - Front field changed to "Buenos días"
    mock_anki_client.find_notes.return_value = [1, 2]
    mock_anki_client.notes_info.return_value = [
        {
            "noteId": 1,  # ES->EN card with changed Front field
            "mod": 2000,
            "fields": {
                "Front": {"value": "Buenos días"},  # Changed Spanish term
                "Back": {"value": "Hello"},
                "Example": {"value": ""},
                "Notes": {"value": ""},
            },
        },
        {
            "noteId": 2,  # EN->ES card (unchanged, same mod to include it)
            "mod": 2000,
            "fields": {
                "Front": {"value": "Hello"},
                "Back": {"value": "Buenos días"},  # Changed Spanish term here too
                "Example": {"value": ""},
                "Notes": {"value": ""},
            },
        },
    ]

    handler.execute()

    # Check translation was updated
    with open(temp_config.source_file, "r", encoding="utf-8") as f:
        result = yaml.safe_load(f)
    assert result[0]["spanish"] == "Buenos días"

    # Check state was remapped correctly
    state = SyncState.load(temp_config.state_file)
    # Old mapping should be gone
    assert "hola" not in state.mappings
    # New mapping should exist with new source_id
    assert "buenos días" in state.mappings
    new_mapping = state.get_mapping("buenos días")
    assert new_mapping.es_en_note_id == 1
    assert new_mapping.en_es_note_id == 2
    assert new_mapping.last_pull_mod == 2000
