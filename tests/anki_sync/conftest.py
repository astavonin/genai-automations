"""Pytest fixtures for anki_sync tests."""

import pytest
from pathlib import Path
from unittest.mock import Mock
from typing import List

from anki_sync.client import AnkiConnectClient
from anki_sync.models import Translation
from anki_sync.config import Config


@pytest.fixture
def mock_anki_client():
    """Mock AnkiConnectClient."""
    client = Mock(spec=AnkiConnectClient)
    client.api_version = 6
    client.version.return_value = 6
    client.deck_names.return_value = []
    client.model_names.return_value = []
    client.add_notes.return_value = [1, 2]
    client.find_notes.return_value = []
    client.notes_info.return_value = []
    return client


@pytest.fixture
def sample_translations() -> List[Translation]:
    """Sample translation data."""
    return [
        Translation(
            spanish="sí",
            english="yes",
            example="sí, funciona",
            notes="affirmative",
            tags=["common"],
        ),
        Translation(
            spanish="¿Qué tal?",
            english="How's it going?",
            example="",
            notes="",
            tags=["greeting"],
        ),
    ]


@pytest.fixture
def temp_config(tmp_path: Path) -> Config:
    """Temporary config for testing."""
    source_file = tmp_path / "vocabulary.yaml"
    state_file = tmp_path / "state.json"
    conflict_log = tmp_path / "conflicts.log"

    # Create empty source file
    source_file.write_text("[]")

    return Config(
        anki_host="localhost",
        anki_port=8765,
        anki_timeout=30,
        deck_name="Test::Deck",
        model_name="TestModel",
        source_file=source_file,
        state_file=state_file,
        conflict_log=conflict_log,
        auto_sync_ankiweb=False,
        include_examples=True,
        include_notes=True,
        max_example_length=200,
        tag_prefix="test_sync",
    )
