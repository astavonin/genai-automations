"""Setup handler for initializing Anki deck and note model."""

import logging

from ..config import Config
from ..client import AnkiConnectClient
from ..exceptions import AnkiConnectionError, ConfigError
from ..models import MODEL_FIELDS

logger = logging.getLogger(__name__)


class SetupHandler:
    """Initialize Anki deck and note model."""

    def __init__(self, config: Config, dry_run: bool = False):
        """Initialize setup handler.

        Args:
            config: Configuration instance
            dry_run: If True, preview changes without applying
        """
        self.config = config
        self.dry_run = dry_run
        self.client = AnkiConnectClient(config.anki_host, config.anki_port, config.anki_timeout)

    def execute(self) -> None:
        """Run setup.

        Raises:
            AnkiConnectionError: If cannot connect to Anki
            ConfigError: If configuration is invalid
        """
        logger.info("Setting up Anki sync...")

        # 1. Check Anki-Connect connection
        self._verify_connection()

        # 2. Ensure deck exists
        self._ensure_deck()

        # 3. Ensure note model exists
        self._ensure_model()

        logger.info("✓ Setup complete")

    def _verify_connection(self) -> None:
        """Verify Anki-Connect is accessible.

        Raises:
            AnkiConnectionError: If connection fails
        """
        logger.info("Checking Anki-Connect connection...")

        try:
            version = self.client.version()
            logger.info(f"✓ Connected to Anki-Connect (version {version})")
        except AnkiConnectionError as e:
            logger.error(f"✗ {e}")
            raise

    def _ensure_deck(self) -> None:
        """Create deck if not exists."""
        logger.info(f"Checking deck '{self.config.deck_name}'...")

        if self.dry_run:
            logger.info(f"[DRY RUN] Would create deck '{self.config.deck_name}'")
            return

        decks = self.client.deck_names()
        if self.config.deck_name not in decks:
            logger.info(f"Creating deck '{self.config.deck_name}'...")
            self.client.create_deck(self.config.deck_name)
            logger.info("✓ Deck created")
        else:
            logger.info("✓ Deck exists")

    def _ensure_model(self) -> None:
        """Create note model if not exists.

        Raises:
            ConfigError: If existing model has wrong fields
        """
        logger.info(f"Checking model '{self.config.model_name}'...")

        if self.dry_run:
            logger.info(f"[DRY RUN] Would create model '{self.config.model_name}'")
            return

        models = self.client.model_names()
        if self.config.model_name in models:
            # Validate existing model has correct fields
            fields = self.client.model_field_names(self.config.model_name)
            expected_fields = MODEL_FIELDS
            if set(fields) == set(expected_fields):
                logger.info("✓ Model exists with correct fields")
                return

            raise ConfigError(
                f"Model '{self.config.model_name}' exists but has wrong fields. "
                f"Expected {expected_fields}, got {fields}"
            )

        # Create model
        logger.info(f"Creating model '{self.config.model_name}'...")
        model_spec = {
            "modelName": self.config.model_name,
            "inOrderFields": MODEL_FIELDS,
            "css": self._get_model_css(),
            "cardTemplates": [
                {
                    "Name": "Card 1",
                    "Front": self._get_card_front_template(),
                    "Back": self._get_card_back_template(),
                }
            ],
        }
        self.client.create_model(model_spec)
        logger.info("✓ Model created")

    @staticmethod
    def _get_model_css() -> str:
        """Get CSS for card styling.

        Returns:
            CSS string
        """
        return """
.card {
 font-family: arial;
 font-size: 20px;
 text-align: center;
 color: black;
 background-color: white;
}

.front { font-size: 24px; font-weight: bold; }
.example { font-size: 16px; color: #666; margin-top: 20px; }
.notes { font-size: 14px; color: #999; margin-top: 10px; font-style: italic; }
"""

    @staticmethod
    def _get_card_front_template() -> str:
        """Get HTML template for card front.

        Returns:
            HTML template string
        """
        return """
<div class="front">{{Front}}</div>
"""

    @staticmethod
    def _get_card_back_template() -> str:
        """Get HTML template for card back.

        Returns:
            HTML template string
        """
        return """
<div class="front">{{Front}}</div>
<hr id=answer>
<div class="back">{{Back}}</div>
{{#Example}}
<div class="example">Example: {{Example}}</div>
{{/Example}}
{{#Notes}}
<div class="notes">{{Notes}}</div>
{{/Notes}}
"""
