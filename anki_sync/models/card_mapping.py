"""Card mapping model."""

from dataclasses import dataclass
from typing import Optional


@dataclass
class CardMapping:
    """Mapping between source entry and Anki notes."""

    source_id: str
    es_en_note_id: Optional[int]  # Spanish -> English card
    en_es_note_id: Optional[int]  # English -> Spanish card
    last_push_hash: str
    last_pull_mod: int  # Anki modification timestamp

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization.

        Returns:
            Dictionary representation
        """
        return {
            "source_id": self.source_id,
            "es_en_note_id": self.es_en_note_id,
            "en_es_note_id": self.en_es_note_id,
            "last_push_hash": self.last_push_hash,
            "last_pull_mod": self.last_pull_mod,
        }

    @classmethod
    def from_dict(cls, data: dict) -> "CardMapping":
        """Create from dictionary.

        Args:
            data: Dictionary with mapping data

        Returns:
            CardMapping instance
        """
        return cls(
            source_id=data["source_id"],
            es_en_note_id=data.get("es_en_note_id"),
            en_es_note_id=data.get("en_es_note_id"),
            last_push_hash=data["last_push_hash"],
            last_pull_mod=data["last_pull_mod"],
        )
