"""Tests for configuration."""

import pytest
from pathlib import Path

from anki_sync.config import Config
from anki_sync.exceptions import ConfigError


def test_config_load_defaults(tmp_path: Path):
    """Test loading config with defaults."""
    # Create minimal source file
    source_file = tmp_path / "vocabulary.yaml"
    source_file.write_text("[]")

    # Create config file
    config_file = tmp_path / "config.yaml"
    config_file.write_text(f"""
anki:
  deck_name: "Test::Deck"

sync:
  source_file: "{source_file}"
  state_file: "{tmp_path}/state.json"
  conflict_log: "{tmp_path}/conflicts.log"
""")

    config = Config.load(config_file)

    # Check defaults
    assert config.anki_host == "localhost"
    assert config.anki_port == 8765
    assert config.anki_timeout == 30
    assert config.deck_name == "Test::Deck"
    assert config.model_name == "SpanishVocab"  # Default
    assert config.auto_sync_ankiweb is False
    assert config.include_examples is True
    assert config.include_notes is True


def test_config_load_explicit_values(tmp_path: Path):
    """Test loading config with explicit values."""
    source_file = tmp_path / "vocabulary.yaml"
    source_file.write_text("[]")

    config_file = tmp_path / "config.yaml"
    config_file.write_text(f"""
anki:
  host: "192.168.1.100"
  port: 9999
  timeout: 60
  deck_name: "Custom::Deck"
  model_name: "CustomModel"

sync:
  source_file: "{source_file}"
  state_file: "{tmp_path}/state.json"
  conflict_log: "{tmp_path}/conflicts.log"
  auto_sync_ankiweb: true

cards:
  include_examples: false
  include_notes: false
  max_example_length: 100
  tag_prefix: "custom_tag"
""")

    config = Config.load(config_file)

    assert config.anki_host == "192.168.1.100"
    assert config.anki_port == 9999
    assert config.anki_timeout == 60
    assert config.deck_name == "Custom::Deck"
    assert config.model_name == "CustomModel"
    assert config.auto_sync_ankiweb is True
    assert config.include_examples is False
    assert config.include_notes is False
    assert config.max_example_length == 100
    assert config.tag_prefix == "custom_tag"


def test_config_validate_source_file_missing(tmp_path: Path):
    """Test validation fails if source file doesn't exist."""
    config = Config(
        anki_host="localhost",
        anki_port=8765,
        anki_timeout=30,
        deck_name="Test",
        model_name="Test",
        source_file=tmp_path / "nonexistent.yaml",
        state_file=tmp_path / "state.json",
        conflict_log=tmp_path / "conflicts.log",
        auto_sync_ankiweb=False,
        include_examples=True,
        include_notes=True,
        max_example_length=200,
        tag_prefix="test",
    )

    with pytest.raises(ConfigError, match="Source file does not exist"):
        config.validate()


def test_config_validate_invalid_port(tmp_path: Path):
    """Test validation fails for invalid port."""
    # Create a valid source file
    source_file = tmp_path / "test.yaml"
    source_file.write_text("[]")

    config = Config(
        anki_host="localhost",
        anki_port=99999,  # Invalid
        anki_timeout=30,
        deck_name="Test",
        model_name="Test",
        source_file=source_file,
        state_file=tmp_path / "state.json",
        conflict_log=tmp_path / "conflicts.log",
        auto_sync_ankiweb=False,
        include_examples=True,
        include_notes=True,
        max_example_length=200,
        tag_prefix="test",
    )

    with pytest.raises(ConfigError, match="Invalid port number"):
        config.validate()


def test_config_validate_invalid_timeout(tmp_path: Path):
    """Test validation fails for invalid timeout."""
    # Create a valid source file
    source_file = tmp_path / "test.yaml"
    source_file.write_text("[]")

    config = Config(
        anki_host="localhost",
        anki_port=8765,
        anki_timeout=0,  # Invalid
        deck_name="Test",
        model_name="Test",
        source_file=source_file,
        state_file=tmp_path / "state.json",
        conflict_log=tmp_path / "conflicts.log",
        auto_sync_ankiweb=False,
        include_examples=True,
        include_notes=True,
        max_example_length=200,
        tag_prefix="test",
    )

    with pytest.raises(ConfigError, match="Invalid timeout"):
        config.validate()


def test_config_load_nonexistent_file(tmp_path: Path):
    """Test loading non-existent config file."""
    with pytest.raises(ConfigError, match="Config file not found"):
        Config.load(tmp_path / "nonexistent.yaml")


def test_config_load_invalid_yaml(tmp_path: Path):
    """Test loading invalid YAML."""
    config_file = tmp_path / "config.yaml"
    config_file.write_text("invalid: yaml: content:")

    with pytest.raises(ConfigError, match="Invalid YAML"):
        Config.load(config_file)
