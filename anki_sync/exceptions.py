"""Exception hierarchy for anki_sync."""


class AnkiSyncError(Exception):
    """Base exception for all anki_sync errors."""


class ConfigError(AnkiSyncError):
    """Configuration error."""


class AnkiConnectionError(AnkiSyncError):
    """Cannot connect to Anki-Connect."""


class AnkiAPIError(AnkiSyncError):
    """Anki-Connect API returned an error."""

    def __init__(self, action: str, error_message: str):
        """Initialize API error with action and message.

        Args:
            action: The API action that failed
            error_message: Error message from Anki-Connect
        """
        self.action = action
        self.error_message = error_message
        super().__init__(f"Anki API error in '{action}': {error_message}")


class SyncConflictError(AnkiSyncError):
    """Sync conflict detected (both sides modified)."""


class ValidationError(AnkiSyncError):
    """Data validation failed."""
