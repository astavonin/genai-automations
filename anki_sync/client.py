"""Client for Anki-Connect HTTP API."""

from typing import Any, List, Dict, Optional
import logging

import requests

from .exceptions import AnkiConnectionError, AnkiAPIError

logger = logging.getLogger(__name__)


class AnkiConnectClient:
    """Client for Anki-Connect HTTP API."""

    def __init__(self, host: str = "localhost", port: int = 8765, timeout: int = 30):
        """Initialize Anki-Connect client.

        Args:
            host: Anki-Connect host
            port: Anki-Connect port
            timeout: Request timeout in seconds
        """
        self.base_url = f"http://{host}:{port}"
        self.timeout = timeout
        self.api_version = 6  # Anki-Connect API version we target

    def _request(self, action: str, params: Optional[Dict] = None) -> Any:
        """Make HTTP request to Anki-Connect.

        Args:
            action: API action name
            params: Optional parameters dictionary

        Returns:
            Response data from Anki-Connect

        Raises:
            AnkiConnectionError: If connection fails
            AnkiAPIError: If API returns an error
        """
        payload = {"action": action, "version": self.api_version, "params": params or {}}

        try:
            response = requests.post(self.base_url, json=payload, timeout=self.timeout)
            response.raise_for_status()
            data = response.json()

            if data.get("error"):
                raise AnkiAPIError(action, data["error"])

            return data.get("result")

        except requests.exceptions.ConnectionError as e:
            raise AnkiConnectionError(
                f"Cannot connect to Anki-Connect at {self.base_url}. "
                "Is Anki running with Anki-Connect installed?"
            ) from e
        except requests.exceptions.Timeout as e:
            raise AnkiConnectionError(
                f"Request to Anki-Connect timed out after {self.timeout}s"
            ) from e

    # Deck operations

    def deck_names(self) -> List[str]:
        """Get all deck names.

        Returns:
            List of deck names
        """
        return self._request("deckNames")

    def create_deck(self, deck_name: str) -> int:
        """Create deck if not exists.

        Args:
            deck_name: Name of deck to create

        Returns:
            Deck ID
        """
        return self._request("createDeck", {"deck": deck_name})

    # Model operations

    def model_names(self) -> List[str]:
        """Get all model (note type) names.

        Returns:
            List of model names
        """
        return self._request("modelNames")

    def create_model(self, model: Dict) -> Dict:
        """Create custom note model.

        Args:
            model: Model specification dictionary

        Returns:
            Model creation result
        """
        return self._request("createModel", model)

    def model_field_names(self, model_name: str) -> List[str]:
        """Get field names for a model.

        Args:
            model_name: Name of the model

        Returns:
            List of field names
        """
        return self._request("modelFieldNames", {"modelName": model_name})

    # Note operations

    def add_notes(self, notes: List[Dict]) -> List[Optional[int]]:
        """Add multiple notes.

        Args:
            notes: List of note dictionaries

        Returns:
            List of note IDs (None for failed notes)
        """
        return self._request("addNotes", {"notes": notes})

    def can_add_notes(self, notes: List[Dict]) -> List[bool]:
        """Check if notes can be added (duplicate detection).

        Args:
            notes: List of note dictionaries

        Returns:
            List of booleans indicating if each note can be added
        """
        return self._request("canAddNotes", {"notes": notes})

    def update_note_fields(self, note_id: int, fields: Dict[str, str]) -> None:
        """Update fields of an existing note.

        Args:
            note_id: Note ID to update
            fields: Dictionary of field names to values
        """
        self._request("updateNoteFields", {"note": {"id": note_id, "fields": fields}})

    def delete_notes(self, note_ids: List[int]) -> None:
        """Delete multiple notes.

        Args:
            note_ids: List of note IDs to delete
        """
        self._request("deleteNotes", {"notes": note_ids})

    def notes_info(self, note_ids: List[int]) -> List[Dict]:
        """Get detailed info for multiple notes.

        Args:
            note_ids: List of note IDs

        Returns:
            List of note info dictionaries
        """
        return self._request("notesInfo", {"notes": note_ids})

    def find_notes(self, query: str) -> List[int]:
        """Find notes matching query.

        Args:
            query: Anki search query

        Returns:
            List of note IDs
        """
        return self._request("findNotes", {"query": query})

    # Sync operations

    def sync(self) -> None:
        """Trigger AnkiWeb sync."""
        self._request("sync")

    # Utility

    def version(self) -> int:
        """Get Anki-Connect version.

        Returns:
            Anki-Connect version number
        """
        return self._request("version")
