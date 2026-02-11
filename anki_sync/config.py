"""Configuration management for anki_sync."""

from dataclasses import dataclass
from pathlib import Path
from typing import Optional
import yaml

from .exceptions import ConfigError


@dataclass
class Config:
    """Configuration for anki_sync."""

    # Anki connection
    anki_host: str
    anki_port: int
    anki_timeout: int
    deck_name: str
    model_name: str

    # File paths
    source_file: Path
    state_file: Path
    conflict_log: Path

    # Sync options
    auto_sync_ankiweb: bool

    # Card formatting
    include_examples: bool
    include_notes: bool
    max_example_length: int
    tag_prefix: str

    @classmethod
    def load(cls, config_path: Optional[Path] = None) -> "Config":
        """Load configuration from YAML file.

        Search order:
        1. Explicit path (--config)
        2. ~/.config/anki_sync/config.yaml
        3. ./anki_sync_config.yaml
        4. Built-in defaults

        Args:
            config_path: Optional explicit config file path

        Returns:
            Config instance

        Raises:
            ConfigError: If config file is invalid
        """
        config_data: dict = {}

        if config_path:
            # Explicit path provided
            if not config_path.exists():
                raise ConfigError(f"Config file not found: {config_path}")
            config_data = cls._load_yaml(config_path)
        else:
            # Search for config file
            search_paths = [
                Path.home() / ".config" / "anki_sync" / "config.yaml",
                Path.cwd() / "anki_sync_config.yaml",
            ]

            for path in search_paths:
                if path.exists():
                    config_data = cls._load_yaml(path)
                    break

        # Load with defaults
        config = cls._from_dict(config_data)
        config.validate()
        return config

    @staticmethod
    def _load_yaml(path: Path) -> dict:
        """Load YAML file.

        Args:
            path: Path to YAML file

        Returns:
            Parsed YAML data

        Raises:
            ConfigError: If YAML is invalid
        """
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = yaml.safe_load(f)
                if data is None:
                    return {}
                if not isinstance(data, dict):
                    raise ConfigError(f"Config file must contain a YAML dictionary: {path}")
                return data
        except yaml.YAMLError as e:
            raise ConfigError(f"Invalid YAML in config file {path}: {e}") from e
        except OSError as e:
            raise ConfigError(f"Cannot read config file {path}: {e}") from e

    @classmethod
    def _from_dict(cls, data: dict) -> "Config":
        """Create Config from dictionary with defaults.

        Args:
            data: Config data dictionary

        Returns:
            Config instance
        """
        anki_config = data.get("anki", {})
        sync_config = data.get("sync", {})
        cards_config = data.get("cards", {})

        # Parse paths with expansion
        source_file = sync_config.get(
            "source_file", str(Path.home() / ".claude" / "memory" / "spanish-vocabulary.yaml")
        )
        state_file = sync_config.get(
            "state_file", str(Path.home() / ".config" / "anki_sync" / "sync_state.json")
        )
        conflict_log = sync_config.get(
            "conflict_log", str(Path.home() / ".config" / "anki_sync" / "conflicts.log")
        )

        return cls(
            # Anki connection
            anki_host=anki_config.get("host", "localhost"),
            anki_port=anki_config.get("port", 8765),
            anki_timeout=anki_config.get("timeout", 30),
            deck_name=anki_config.get("deck_name", "Spanish::Vocabulary"),
            model_name=anki_config.get("model_name", "SpanishVocab"),
            # File paths
            source_file=Path(source_file).expanduser(),
            state_file=Path(state_file).expanduser(),
            conflict_log=Path(conflict_log).expanduser(),
            # Sync options
            auto_sync_ankiweb=sync_config.get("auto_sync_ankiweb", False),
            # Card formatting
            include_examples=cards_config.get("include_examples", True),
            include_notes=cards_config.get("include_notes", True),
            max_example_length=cards_config.get("max_example_length", 200),
            tag_prefix=cards_config.get("tag_prefix", "anki_sync"),
        )

    def validate(self) -> None:
        """Validate configuration values.

        Raises:
            ConfigError: If validation fails
        """
        # Validate source file exists
        if not self.source_file.exists():
            raise ConfigError(
                f"Source file does not exist: {self.source_file}\n"
                f"Create the file or adjust 'sync.source_file' in config."
            )

        # Validate source file is readable
        if not self.source_file.is_file():
            raise ConfigError(f"Source file is not a file: {self.source_file}")

        # Validate state file directory is writable
        state_dir = self.state_file.parent
        if not state_dir.exists():
            try:
                state_dir.mkdir(parents=True, exist_ok=True)
            except OSError as e:
                raise ConfigError(f"Cannot create state directory {state_dir}: {e}") from e

        # Validate conflict log directory
        conflict_dir = self.conflict_log.parent
        if not conflict_dir.exists():
            try:
                conflict_dir.mkdir(parents=True, exist_ok=True)
            except OSError as e:
                raise ConfigError(
                    f"Cannot create conflict log directory {conflict_dir}: {e}"
                ) from e

        # Validate port range
        if not (1 <= self.anki_port <= 65535):
            raise ConfigError(f"Invalid port number: {self.anki_port} (must be 1-65535)")

        # Validate timeout
        if self.anki_timeout <= 0:
            raise ConfigError(f"Invalid timeout: {self.anki_timeout} (must be > 0)")

        # Validate max_example_length
        if self.max_example_length <= 0:
            raise ConfigError(
                f"Invalid max_example_length: {self.max_example_length} (must be > 0)"
            )
