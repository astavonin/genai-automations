"""Translation file I/O utilities."""

import logging
from pathlib import Path
from typing import List
import yaml

from ..models.translation import Translation
from ..exceptions import ValidationError

logger = logging.getLogger(__name__)


def load_translations(source_file: Path) -> List[Translation]:
    """Load translations from YAML file.

    Args:
        source_file: Path to vocabulary YAML file

    Returns:
        List of Translation objects

    Raises:
        ValidationError: If file format is invalid
    """
    if not source_file.exists():
        return []

    try:
        with open(source_file, "r", encoding="utf-8") as f:
            data = yaml.safe_load(f)

        # Empty file returns None from yaml.safe_load
        if data is None:
            return []

        if not isinstance(data, list):
            raise ValidationError(f"Source file must contain a YAML list: {source_file}")

        translations = [Translation.from_dict(item) for item in data]
        return translations

    except yaml.YAMLError as e:
        raise ValidationError(f"Invalid YAML in source file {source_file}: {e}") from e
    except (OSError, KeyError) as e:
        raise ValidationError(f"Cannot read source file {source_file}: {e}") from e


def save_translations(source_file: Path, translations: List[Translation]) -> None:
    """Save translations to YAML file atomically.

    Uses atomic write pattern (write to temp file, then rename) to prevent
    corruption on failure.

    Args:
        source_file: Path to vocabulary YAML file
        translations: List of translations to save

    Raises:
        ValidationError: If save fails
    """
    temp_file = source_file.with_suffix(".tmp")
    try:
        data = [t.to_dict() for t in translations]
        with open(temp_file, "w", encoding="utf-8") as f:
            yaml.safe_dump(data, f, allow_unicode=True, default_flow_style=False, sort_keys=False)
        # Atomic rename
        temp_file.replace(source_file)
        logger.debug(f"Saved {len(translations)} translations to {source_file}")

    except (OSError, yaml.YAMLError) as e:
        # Clean up temp file on failure
        if temp_file.exists():
            temp_file.unlink()
        raise ValidationError(f"Cannot save translations to {source_file}: {e}") from e
