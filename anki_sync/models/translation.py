"""Translation entry model."""

from dataclasses import dataclass, field
from typing import List
import hashlib
import json


@dataclass
class Translation:
    """A single vocabulary entry."""

    spanish: str
    english: str
    example: str = ""
    notes: str = ""
    tags: List[str] = field(default_factory=list)

    @property
    def source_id(self) -> str:
        """Compute source_id from Spanish term.

        Uses normalized Spanish term as unique identifier.
        Collision detection is handled by translation loading.

        Returns:
            Normalized spanish term (lowercase, stripped)
        """
        return self.spanish.lower().strip()

    def content_hash(self) -> str:
        """Compute hash of content for change detection.

        Uses 12 hex characters (48 bits) for good collision resistance
        while remaining human-readable in logs.

        Returns:
            12-character hex hash string
        """
        content = {
            "spanish": self.spanish,
            "english": self.english,
            "example": self.example,
            "notes": self.notes,
            "tags": sorted(self.tags),
        }
        content_str = json.dumps(content, sort_keys=True)
        return hashlib.sha256(content_str.encode()).hexdigest()[:12]

    def to_dict(self) -> dict:
        """Convert to dictionary for YAML serialization.

        Returns:
            Dictionary representation
        """
        return {
            "spanish": self.spanish,
            "english": self.english,
            "example": self.example,
            "notes": self.notes,
            "tags": self.tags,
        }

    @classmethod
    def from_dict(cls, data: dict) -> "Translation":
        """Create from dictionary.

        Args:
            data: Dictionary with translation data

        Returns:
            Translation instance
        """
        return cls(
            spanish=data["spanish"],
            english=data["english"],
            example=data.get("example", ""),
            notes=data.get("notes", ""),
            tags=data.get("tags", []),
        )
