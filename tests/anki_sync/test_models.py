"""Tests for data models."""

from pathlib import Path

from anki_sync.models import Translation, CardMapping, SyncState


def test_translation_source_id():
    """Test source_id computation."""
    trans = Translation(spanish="¿Hola?", english="Hello")
    assert trans.source_id == "¿hola?"  # Lowercase, stripped


def test_translation_content_hash():
    """Test content hash computation."""
    trans1 = Translation(spanish="sí", english="yes", example="sí funciona")
    trans2 = Translation(spanish="sí", english="yes", example="sí funciona")
    trans3 = Translation(spanish="sí", english="yes", example="different")

    # Same content = same hash
    assert trans1.content_hash() == trans2.content_hash()

    # Different content = different hash
    assert trans1.content_hash() != trans3.content_hash()

    # Hash length is 12 characters
    assert len(trans1.content_hash()) == 12


def test_translation_to_dict():
    """Test translation serialization."""
    trans = Translation(
        spanish="sí", english="yes", example="ejemplo", notes="nota", tags=["common"]
    )
    data = trans.to_dict()

    assert data == {
        "spanish": "sí",
        "english": "yes",
        "example": "ejemplo",
        "notes": "nota",
        "tags": ["common"],
    }


def test_translation_from_dict():
    """Test translation deserialization."""
    data = {
        "spanish": "sí",
        "english": "yes",
        "example": "ejemplo",
        "notes": "nota",
        "tags": ["common"],
    }
    trans = Translation.from_dict(data)

    assert trans.spanish == "sí"
    assert trans.english == "yes"
    assert trans.example == "ejemplo"
    assert trans.notes == "nota"
    assert trans.tags == ["common"]


def test_card_mapping_serialization():
    """Test CardMapping serialization/deserialization."""
    mapping = CardMapping(
        source_id="hola",
        es_en_note_id=123,
        en_es_note_id=456,
        last_push_hash="abc123def456",
        last_pull_mod=1234567890,
    )

    data = mapping.to_dict()
    restored = CardMapping.from_dict(data)

    assert restored.source_id == mapping.source_id
    assert restored.es_en_note_id == mapping.es_en_note_id
    assert restored.en_es_note_id == mapping.en_es_note_id
    assert restored.last_push_hash == mapping.last_push_hash
    assert restored.last_pull_mod == mapping.last_pull_mod


def test_sync_state_load_nonexistent(tmp_path: Path):
    """Test loading state from non-existent file."""
    state_file = tmp_path / "state.json"
    state = SyncState.load(state_file)

    assert state.version == 1
    assert state.last_push is None
    assert state.last_pull is None
    assert len(state.mappings) == 0


def test_sync_state_save_load(tmp_path: Path):
    """Test state persistence."""
    state_file = tmp_path / "state.json"

    # Create state
    state = SyncState(
        version=1,
        last_push="2026-01-01T00:00:00",
        last_pull="2026-01-02T00:00:00",
        deck_name="Test::Deck",
        model_name="TestModel",
    )
    state.mappings["hola"] = CardMapping(
        source_id="hola",
        es_en_note_id=123,
        en_es_note_id=456,
        last_push_hash="abc123",
        last_pull_mod=1000,
    )

    # Save and reload
    state.save(state_file)
    loaded = SyncState.load(state_file)

    assert loaded.version == state.version
    assert loaded.last_push == state.last_push
    assert loaded.last_pull == state.last_pull
    assert loaded.deck_name == state.deck_name
    assert loaded.model_name == state.model_name
    assert len(loaded.mappings) == 1
    assert "hola" in loaded.mappings


def test_sync_state_get_mapping():
    """Test get_mapping method."""
    state = SyncState()
    state.mappings["hola"] = CardMapping(
        source_id="hola",
        es_en_note_id=123,
        en_es_note_id=456,
        last_push_hash="abc123",
        last_pull_mod=1000,
    )

    mapping = state.get_mapping("hola")
    assert mapping is not None
    assert mapping.source_id == "hola"

    mapping = state.get_mapping("nonexistent")
    assert mapping is None


def test_sync_state_find_by_note_id():
    """Test find_by_note_id method."""
    state = SyncState()
    state.mappings["hola"] = CardMapping(
        source_id="hola",
        es_en_note_id=123,
        en_es_note_id=456,
        last_push_hash="abc123",
        last_pull_mod=1000,
    )

    mapping = state.find_by_note_id(123)
    assert mapping is not None
    assert mapping.source_id == "hola"

    mapping = state.find_by_note_id(456)
    assert mapping is not None
    assert mapping.source_id == "hola"

    mapping = state.find_by_note_id(999)
    assert mapping is None


def test_sync_state_update_timestamps():
    """Test timestamp update methods."""
    state = SyncState()

    assert state.last_push is None
    state.update_push_timestamp()
    assert state.last_push is not None
    assert "T" in state.last_push  # ISO format

    assert state.last_pull is None
    state.update_pull_timestamp()
    assert state.last_pull is not None
    assert "T" in state.last_pull  # ISO format


def test_sync_state_atomic_save(tmp_path: Path):
    """Test atomic save (temp file pattern)."""
    state_file = tmp_path / "state.json"

    state = SyncState()
    state.mappings["test"] = CardMapping(
        source_id="test",
        es_en_note_id=1,
        en_es_note_id=2,
        last_push_hash="hash",
        last_pull_mod=0,
    )

    state.save(state_file)

    # Temp file should be cleaned up
    temp_file = state_file.with_suffix(".tmp")
    assert not temp_file.exists()

    # State file should exist
    assert state_file.exists()
