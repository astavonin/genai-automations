"""Sync state persistence."""

from dataclasses import dataclass, field
from typing import Dict, Optional
from pathlib import Path
from datetime import datetime, timezone
import json

from .card_mapping import CardMapping


@dataclass
class SyncState:
    """Persistent sync state."""

    version: int = 1
    last_push: Optional[str] = None  # ISO 8601 timestamp
    last_pull: Optional[str] = None
    deck_name: str = ""
    model_name: str = ""
    mappings: Dict[str, CardMapping] = field(default_factory=dict)

    @classmethod
    def load(cls, state_file: Path) -> "SyncState":
        """Load state from JSON file.

        Args:
            state_file: Path to state file

        Returns:
            SyncState instance (empty if file doesn't exist)
        """
        if not state_file.exists():
            return cls()

        with open(state_file, "r", encoding="utf-8") as f:
            data = json.load(f)

        mappings = {
            source_id: CardMapping.from_dict(mapping_data)
            for source_id, mapping_data in data.get("mappings", {}).items()
        }

        return cls(
            version=data.get("version", 1),
            last_push=data.get("last_push"),
            last_pull=data.get("last_pull"),
            deck_name=data.get("deck_name", ""),
            model_name=data.get("model_name", ""),
            mappings=mappings,
        )

    def save(self, state_file: Path) -> None:
        """Save state to JSON file atomically.

        Uses write-to-temp-then-rename for atomic operation to prevent
        corruption if process crashes during write.

        Args:
            state_file: Path to state file
        """
        state_file.parent.mkdir(parents=True, exist_ok=True)

        data = {
            "version": self.version,
            "last_push": self.last_push,
            "last_pull": self.last_pull,
            "deck_name": self.deck_name,
            "model_name": self.model_name,
            "mappings": {
                source_id: mapping.to_dict() for source_id, mapping in self.mappings.items()
            },
        }

        # Atomic write via temp file
        temp_file = state_file.with_suffix(".tmp")
        try:
            with open(temp_file, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)
            # Atomic rename on POSIX systems
            temp_file.replace(state_file)
        except Exception:
            # Clean up temp file on failure
            if temp_file.exists():
                temp_file.unlink()
            raise

    def get_mapping(self, source_id: str) -> Optional[CardMapping]:
        """Get mapping for source entry.

        Args:
            source_id: Source entry ID

        Returns:
            CardMapping if found, None otherwise
        """
        return self.mappings.get(source_id)

    def find_by_note_id(self, note_id: int) -> Optional[CardMapping]:
        """Find mapping containing this note ID.

        Args:
            note_id: Anki note ID

        Returns:
            CardMapping if found, None otherwise
        """
        for mapping in self.mappings.values():
            if mapping.es_en_note_id == note_id or mapping.en_es_note_id == note_id:
                return mapping
        return None

    def update_push_timestamp(self) -> None:
        """Update last push timestamp to now."""
        self.last_push = datetime.now(timezone.utc).isoformat()

    def update_pull_timestamp(self) -> None:
        """Update last pull timestamp to now."""
        self.last_pull = datetime.now(timezone.utc).isoformat()
