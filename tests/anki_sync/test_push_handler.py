"""Tests for push handler."""

import pytest
import yaml

from anki_sync.handlers import PushHandler
from anki_sync.models import CardMapping, SyncState
from anki_sync.exceptions import ValidationError


def test_push_handler_new_entries(temp_config, mock_anki_client, sample_translations):
    """Test pushing new entries."""
    handler = PushHandler(temp_config)
    handler.client = mock_anki_client

    # Write translations to source file
    with open(temp_config.source_file, "w", encoding="utf-8") as f:
        yaml.safe_dump([t.to_dict() for t in sample_translations], f)

    # Mock add_notes to return note IDs
    mock_anki_client.add_notes.return_value = [1, 2, 3, 4]  # 2 notes per entry

    handler.execute()

    # Verify notes were added
    mock_anki_client.add_notes.assert_called_once()
    call_args = mock_anki_client.add_notes.call_args[0][0]
    assert len(call_args) == 4  # 2 entries × 2 directions

    # Verify state was saved
    state = SyncState.load(temp_config.state_file)
    assert len(state.mappings) == 2


def test_push_handler_updated_entries(temp_config, mock_anki_client, sample_translations):
    """Test pushing updated entries."""
    handler = PushHandler(temp_config)
    handler.client = mock_anki_client

    # Create initial state with existing mappings
    state = SyncState()
    trans = sample_translations[0]
    state.mappings[trans.source_id] = CardMapping(
        source_id=trans.source_id,
        es_en_note_id=1,
        en_es_note_id=2,
        last_push_hash="old_hash",  # Different hash
        last_pull_mod=0,
    )
    state.save(temp_config.state_file)

    # Write translations (with updated content)
    with open(temp_config.source_file, "w", encoding="utf-8") as f:
        yaml.safe_dump([trans.to_dict()], f)

    handler.execute()

    # Verify notes were updated
    assert mock_anki_client.update_note_fields.call_count == 2  # Both directions


def test_push_handler_deleted_entries(temp_config, mock_anki_client):
    """Test deleting entries."""
    handler = PushHandler(temp_config)
    handler.client = mock_anki_client

    # Create state with mapping for entry that's not in source
    state = SyncState()
    state.mappings["deleted"] = CardMapping(
        source_id="deleted",
        es_en_note_id=1,
        en_es_note_id=2,
        last_push_hash="hash",
        last_pull_mod=0,
    )
    state.save(temp_config.state_file)

    # Write empty translations
    with open(temp_config.source_file, "w", encoding="utf-8") as f:
        yaml.safe_dump([], f)

    handler.execute()

    # Verify notes were deleted
    mock_anki_client.delete_notes.assert_called_once_with([1, 2])

    # Verify mapping was removed
    state = SyncState.load(temp_config.state_file)
    assert "deleted" not in state.mappings


def test_push_handler_collision_detection(temp_config, mock_anki_client):
    """Test source_id collision detection."""
    handler = PushHandler(temp_config)
    handler.client = mock_anki_client

    # Create translations with same normalized source_id
    translations = [
        {"spanish": "Hola", "english": "Hello"},
        {"spanish": "hola", "english": "Hi"},  # Same after normalization
    ]

    with open(temp_config.source_file, "w", encoding="utf-8") as f:
        yaml.safe_dump(translations, f)

    with pytest.raises(ValidationError, match="Duplicate source_id"):
        handler.execute()


def test_push_handler_partial_failure(temp_config, mock_anki_client, sample_translations):
    """Test handling partial failures in add_notes."""
    handler = PushHandler(temp_config)
    handler.client = mock_anki_client

    with open(temp_config.source_file, "w", encoding="utf-8") as f:
        yaml.safe_dump([sample_translations[0].to_dict()], f)

    # Return [success, None] - one card created, one failed
    mock_anki_client.add_notes.return_value = [1, None]

    handler.execute()

    # State should only have the successful note ID
    state = SyncState.load(temp_config.state_file)
    mapping = state.get_mapping(sample_translations[0].source_id)
    assert mapping is not None
    assert mapping.es_en_note_id == 1
    assert mapping.en_es_note_id is None


def test_push_handler_dry_run(temp_config, mock_anki_client, sample_translations):
    """Test push in dry-run mode."""
    handler = PushHandler(temp_config, dry_run=True)
    handler.client = mock_anki_client

    with open(temp_config.source_file, "w", encoding="utf-8") as f:
        yaml.safe_dump([t.to_dict() for t in sample_translations], f)

    handler.execute()

    # Should not call any write operations
    mock_anki_client.add_notes.assert_not_called()
    mock_anki_client.update_note_fields.assert_not_called()
    mock_anki_client.delete_notes.assert_not_called()
