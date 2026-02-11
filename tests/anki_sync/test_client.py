"""Tests for Anki-Connect client."""

import pytest
import responses
from requests.exceptions import Timeout

from anki_sync.client import AnkiConnectClient
from anki_sync.exceptions import AnkiConnectionError, AnkiAPIError


@responses.activate
def test_client_version():
    """Test version() method."""
    responses.add(
        responses.POST,
        "http://localhost:8765",
        json={"result": 6, "error": None},
        status=200,
    )

    client = AnkiConnectClient()
    version = client.version()

    assert version == 6
    assert len(responses.calls) == 1


@responses.activate
def test_client_deck_names():
    """Test deck_names() method."""
    responses.add(
        responses.POST,
        "http://localhost:8765",
        json={"result": ["Default", "Spanish::Vocabulary"], "error": None},
        status=200,
    )

    client = AnkiConnectClient()
    decks = client.deck_names()

    assert decks == ["Default", "Spanish::Vocabulary"]


@responses.activate
def test_client_api_error():
    """Test API error handling."""
    responses.add(
        responses.POST,
        "http://localhost:8765",
        json={"result": None, "error": "deck not found"},
        status=200,
    )

    client = AnkiConnectClient()

    with pytest.raises(AnkiAPIError) as exc_info:
        client.deck_names()

    assert "deck not found" in str(exc_info.value)
    assert exc_info.value.action == "deckNames"


@responses.activate
def test_client_connection_error():
    """Test connection error handling."""
    # Don't add any response - will cause ConnectionError
    client = AnkiConnectClient()

    with pytest.raises(AnkiConnectionError, match="Cannot connect"):
        client.version()


@responses.activate
def test_client_timeout():
    """Test timeout handling."""
    responses.add(responses.POST, "http://localhost:8765", body=Timeout("Connection timeout"))

    client = AnkiConnectClient(timeout=1)

    with pytest.raises(AnkiConnectionError, match="timed out"):
        client.version()


@responses.activate
def test_client_add_notes():
    """Test add_notes() method."""
    responses.add(
        responses.POST,
        "http://localhost:8765",
        json={"result": [123, 456], "error": None},
        status=200,
    )

    client = AnkiConnectClient()
    notes = [{"deckName": "Test", "modelName": "Basic", "fields": {"Front": "Q", "Back": "A"}}]
    note_ids = client.add_notes(notes)

    assert note_ids == [123, 456]


@responses.activate
def test_client_add_notes_partial_failure():
    """Test add_notes() with partial failures (null IDs)."""
    responses.add(
        responses.POST,
        "http://localhost:8765",
        json={"result": [123, None, 456], "error": None},
        status=200,
    )

    client = AnkiConnectClient()
    notes = [{"fields": {}}, {"fields": {}}, {"fields": {}}]
    note_ids = client.add_notes(notes)

    assert note_ids == [123, None, 456]


@responses.activate
def test_client_update_note_fields():
    """Test update_note_fields() method."""
    responses.add(
        responses.POST,
        "http://localhost:8765",
        json={"result": None, "error": None},
        status=200,
    )

    client = AnkiConnectClient()
    client.update_note_fields(123, {"Front": "Updated Q", "Back": "Updated A"})

    assert len(responses.calls) == 1
    request_body = responses.calls[0].request.body
    assert b"updateNoteFields" in request_body


@responses.activate
def test_client_delete_notes():
    """Test delete_notes() method."""
    responses.add(
        responses.POST,
        "http://localhost:8765",
        json={"result": None, "error": None},
        status=200,
    )

    client = AnkiConnectClient()
    client.delete_notes([123, 456])

    assert len(responses.calls) == 1


@responses.activate
def test_client_find_notes():
    """Test find_notes() method."""
    responses.add(
        responses.POST,
        "http://localhost:8765",
        json={"result": [123, 456, 789], "error": None},
        status=200,
    )

    client = AnkiConnectClient()
    note_ids = client.find_notes('deck:"Spanish::Vocabulary"')

    assert note_ids == [123, 456, 789]


@responses.activate
def test_client_notes_info():
    """Test notes_info() method."""
    responses.add(
        responses.POST,
        "http://localhost:8765",
        json={
            "result": [
                {
                    "noteId": 123,
                    "modelName": "Basic",
                    "fields": {"Front": {"value": "Q"}, "Back": {"value": "A"}},
                    "mod": 1234567890,
                }
            ],
            "error": None,
        },
        status=200,
    )

    client = AnkiConnectClient()
    notes = client.notes_info([123])

    assert len(notes) == 1
    assert notes[0]["noteId"] == 123


@responses.activate
def test_client_create_model():
    """Test create_model() method."""
    responses.add(
        responses.POST,
        "http://localhost:8765",
        json={"result": {"id": 1}, "error": None},
        status=200,
    )

    client = AnkiConnectClient()
    model_spec = {
        "modelName": "TestModel",
        "inOrderFields": ["Front", "Back"],
        "css": ".card {}",
        "cardTemplates": [],
    }
    result = client.create_model(model_spec)

    assert result == {"id": 1}


@responses.activate
def test_client_sync():
    """Test sync() method."""
    responses.add(
        responses.POST,
        "http://localhost:8765",
        json={"result": None, "error": None},
        status=200,
    )

    client = AnkiConnectClient()
    client.sync()  # Should not raise

    assert len(responses.calls) == 1
