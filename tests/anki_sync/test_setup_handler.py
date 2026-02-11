"""Tests for setup handler."""

import pytest

from anki_sync.handlers import SetupHandler
from anki_sync.exceptions import ConfigError


def test_setup_handler_success(temp_config, mock_anki_client):
    """Test successful setup."""
    handler = SetupHandler(temp_config)
    handler.client = mock_anki_client

    # Configure mocks
    mock_anki_client.version.return_value = 6
    mock_anki_client.deck_names.return_value = []
    mock_anki_client.model_names.return_value = []

    # Execute
    handler.execute()

    # Verify calls
    mock_anki_client.version.assert_called_once()
    mock_anki_client.deck_names.assert_called_once()
    mock_anki_client.create_deck.assert_called_once()
    mock_anki_client.model_names.assert_called_once()
    mock_anki_client.create_model.assert_called_once()


def test_setup_handler_deck_exists(temp_config, mock_anki_client):
    """Test setup when deck already exists."""
    handler = SetupHandler(temp_config)
    handler.client = mock_anki_client

    # Deck already exists
    mock_anki_client.deck_names.return_value = [temp_config.deck_name]
    mock_anki_client.model_names.return_value = []

    handler.execute()

    # Should not create deck
    mock_anki_client.create_deck.assert_not_called()


def test_setup_handler_model_exists(temp_config, mock_anki_client):
    """Test setup when model already exists."""
    handler = SetupHandler(temp_config)
    handler.client = mock_anki_client

    mock_anki_client.deck_names.return_value = []
    mock_anki_client.model_names.return_value = [temp_config.model_name]
    mock_anki_client.model_field_names.return_value = ["Front", "Back", "Example", "Notes"]

    handler.execute()

    # Should not create model
    mock_anki_client.create_model.assert_not_called()


def test_setup_handler_model_wrong_fields(temp_config, mock_anki_client):
    """Test setup fails when existing model has wrong fields."""
    handler = SetupHandler(temp_config)
    handler.client = mock_anki_client

    mock_anki_client.deck_names.return_value = []
    mock_anki_client.model_names.return_value = [temp_config.model_name]
    mock_anki_client.model_field_names.return_value = ["Front", "Back"]  # Wrong fields

    with pytest.raises(ConfigError, match="wrong fields"):
        handler.execute()


def test_setup_handler_dry_run(temp_config, mock_anki_client):
    """Test setup in dry-run mode."""
    handler = SetupHandler(temp_config, dry_run=True)
    handler.client = mock_anki_client

    mock_anki_client.version.return_value = 6
    mock_anki_client.deck_names.return_value = []
    mock_anki_client.model_names.return_value = []

    handler.execute()

    # Should only check version, not create anything
    mock_anki_client.version.assert_called_once()
    mock_anki_client.create_deck.assert_not_called()
    mock_anki_client.create_model.assert_not_called()
