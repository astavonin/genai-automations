"""Push handler for syncing translations to Anki."""

import logging
from typing import List, Tuple, Dict

from ..config import Config
from ..client import AnkiConnectClient
from ..models import (
    Translation,
    CardMapping,
    SyncState,
    FIELD_FRONT,
    FIELD_BACK,
    FIELD_EXAMPLE,
    FIELD_NOTES,
)
from ..exceptions import ValidationError, AnkiAPIError
from ..utils.translation_io import load_translations

logger = logging.getLogger(__name__)


class PushHandler:
    """Push translations to Anki."""

    def __init__(self, config: Config, dry_run: bool = False):
        """Initialize push handler.

        Args:
            config: Configuration instance
            dry_run: If True, preview changes without applying
        """
        self.config = config
        self.dry_run = dry_run
        self.client = AnkiConnectClient(config.anki_host, config.anki_port, config.anki_timeout)

    def execute(self) -> None:
        """Push translations to Anki."""
        logger.info("Pushing translations to Anki...")

        # 1. Load data
        translations = self._load_translations()
        self._validate_no_collisions(translations)
        state = SyncState.load(self.config.state_file)

        # 2. Compute diff
        new_entries, updated_entries, deleted_source_ids = self._compute_diff(translations, state)

        # 3. Show diff summary
        self._show_diff_summary(new_entries, updated_entries, deleted_source_ids)

        if self.dry_run:
            logger.info("[DRY RUN] No changes applied")
            return

        if not new_entries and not updated_entries and not deleted_source_ids:
            logger.info("✓ No changes to push")
            return

        # 4. Apply changes with incremental state saves
        if new_entries:
            self._create_new_cards(new_entries, state)
            state.save(self.config.state_file)  # Save after creation

        if updated_entries:
            self._update_cards(updated_entries, state)
            state.save(self.config.state_file)  # Save after updates

        if deleted_source_ids:
            self._delete_cards(deleted_source_ids, state)
            state.save(self.config.state_file)  # Save after deletions

        # 5. Update timestamp
        state.update_push_timestamp()
        state.save(self.config.state_file)

        # 6. Optional AnkiWeb sync
        if self.config.auto_sync_ankiweb:
            logger.info("Syncing to AnkiWeb...")
            self.client.sync()
            logger.info("✓ AnkiWeb sync complete")

        logger.info("✓ Push complete")

    def _load_translations(self) -> List[Translation]:
        """Load translations from source file.

        Returns:
            List of Translation objects

        Raises:
            ValidationError: If file format is invalid
        """
        translations = load_translations(self.config.source_file)
        logger.debug(f"Loaded {len(translations)} translations from source file")
        return translations

    def _validate_no_collisions(self, translations: List[Translation]) -> None:
        """Validate no source_id collisions.

        Args:
            translations: List of translations to validate

        Raises:
            ValidationError: If duplicate source_ids found
        """
        seen: Dict[str, str] = {}
        for trans in translations:
            if trans.source_id in seen:
                raise ValidationError(
                    f"Duplicate source_id '{trans.source_id}' detected:\n"
                    f"  Entry 1: spanish='{seen[trans.source_id]}'\n"
                    f"  Entry 2: spanish='{trans.spanish}'\n"
                    f"These entries would collide after normalization."
                )
            seen[trans.source_id] = trans.spanish

    def _compute_diff(
        self, translations: List[Translation], state: SyncState
    ) -> Tuple[List[Translation], List[Tuple[Translation, CardMapping]], List[str]]:
        """Compute diff between translations and state.

        Args:
            translations: Current translations
            state: Current sync state

        Returns:
            Tuple of (new_entries, updated_entries, deleted_source_ids)
        """
        new_entries: List[Translation] = []
        updated_entries: List[Tuple[Translation, CardMapping]] = []

        for trans in translations:
            mapping = state.get_mapping(trans.source_id)
            if mapping is None:
                # New entry
                new_entries.append(trans)
            elif trans.content_hash() != mapping.last_push_hash:
                # Updated entry
                updated_entries.append((trans, mapping))
            # else: unchanged

        # Find deleted (in state but not in source)
        source_ids = {t.source_id for t in translations}
        deleted_source_ids = [
            source_id for source_id in state.mappings if source_id not in source_ids
        ]

        return new_entries, updated_entries, deleted_source_ids

    def _show_diff_summary(
        self,
        new_entries: List[Translation],
        updated_entries: List[Tuple[Translation, CardMapping]],
        deleted_source_ids: List[str],
    ) -> None:
        """Show diff summary.

        Args:
            new_entries: New translations
            updated_entries: Updated translations with mappings
            deleted_source_ids: Deleted source IDs
        """
        logger.info("=== Push Summary ===")
        logger.info(f"New entries: {len(new_entries)} ({len(new_entries) * 2} cards)")
        logger.info(f"Updated entries: {len(updated_entries)} ({len(updated_entries) * 2} cards)")
        logger.info(
            f"Deleted entries: {len(deleted_source_ids)} ({len(deleted_source_ids) * 2} cards)"
        )

        if logger.isEnabledFor(logging.DEBUG):
            if new_entries:
                logger.debug("New: %s", [t.spanish for t in new_entries])
            if updated_entries:
                logger.debug("Updated: %s", [t.spanish for t, _ in updated_entries])
            if deleted_source_ids:
                logger.debug("Deleted: %s", deleted_source_ids)

    def _create_new_cards(self, new_entries: List[Translation], state: SyncState) -> None:
        """Create cards for new entries with partial failure handling.

        Args:
            new_entries: List of new translations
            state: Sync state to update
        """
        if not new_entries:
            return

        logger.info(f"Creating {len(new_entries)} new entries ({len(new_entries)*2} cards)...")

        # Build notes (2 per entry)
        notes_to_add = []
        entry_indices = []  # Track which entry each pair of notes belongs to

        for idx, trans in enumerate(new_entries):
            # Spanish -> English card
            notes_to_add.append(self._build_note(trans, direction="es_en"))
            entry_indices.append((idx, "es_en"))

            # English -> Spanish card
            notes_to_add.append(self._build_note(trans, direction="en_es"))
            entry_indices.append((idx, "en_es"))

        # Call Anki-Connect
        try:
            note_ids = self.client.add_notes(notes_to_add)
        except AnkiAPIError as e:
            logger.error(f"Failed to add notes: {e}")
            return

        # Handle partial failures (null IDs)
        success_count = 0
        fail_count = 0

        for i, note_id in enumerate(note_ids):
            entry_idx, direction = entry_indices[i]
            trans = new_entries[entry_idx]

            if note_id is None:
                # Failed to create this card
                fail_count += 1
                logger.warning(
                    f"Failed to create {direction} card for '{trans.spanish}'. "
                    f"Possible duplicate or validation error."
                )
                continue

            # Success - store mapping
            success_count += 1
            mapping = state.get_mapping(trans.source_id)
            if mapping is None:
                mapping = CardMapping(
                    source_id=trans.source_id,
                    es_en_note_id=None,
                    en_es_note_id=None,
                    last_push_hash=trans.content_hash(),
                    last_pull_mod=0,
                )
                state.mappings[trans.source_id] = mapping

            # Store the note ID
            if direction == "es_en":
                mapping.es_en_note_id = note_id
            else:
                mapping.en_es_note_id = note_id

        logger.info(f"✓ Created {success_count} cards")
        if fail_count > 0:
            logger.warning(f"✗ Failed to create {fail_count} cards (see warnings above)")

    def _update_cards(
        self, updated_entries: List[Tuple[Translation, CardMapping]], state: SyncState
    ) -> None:
        """Update existing cards.

        Args:
            updated_entries: List of (translation, mapping) tuples
            state: Sync state to update
        """
        if not updated_entries:
            return

        logger.info(f"Updating {len(updated_entries)} entries ({len(updated_entries)*2} cards)...")

        success_count = 0
        fail_count = 0

        for trans, mapping in updated_entries:
            # MAJOR FIX: Handle each update independently
            card_success_count = 0

            # Update Spanish -> English card
            if mapping.es_en_note_id:
                try:
                    fields = self._build_fields(trans, direction="es_en")
                    self.client.update_note_fields(mapping.es_en_note_id, fields)
                    logger.info(f"Updated ES→EN card for '{trans.spanish}'")
                    success_count += 1
                    card_success_count += 1
                except AnkiAPIError as e:
                    logger.warning(f"Failed to update ES→EN card for '{trans.spanish}': {e}")
                    fail_count += 1

            # Update English -> Spanish card (independent)
            if mapping.en_es_note_id:
                try:
                    fields = self._build_fields(trans, direction="en_es")
                    self.client.update_note_fields(mapping.en_es_note_id, fields)
                    logger.info(f"Updated EN→ES card for '{trans.spanish}'")
                    success_count += 1
                    card_success_count += 1
                except AnkiAPIError as e:
                    logger.warning(f"Failed to update EN→ES card for '{trans.spanish}': {e}")
                    fail_count += 1

            # Update hash only if at least one card updated successfully
            if card_success_count > 0:
                mapping.last_push_hash = trans.content_hash()

        logger.info(f"✓ Updated {success_count} cards")
        if fail_count > 0:
            logger.warning(f"✗ Failed to update {fail_count} cards")

    def _delete_cards(self, deleted_source_ids: List[str], state: SyncState) -> None:
        """Delete cards for deleted entries.

        Args:
            deleted_source_ids: List of source IDs to delete
            state: Sync state to update
        """
        if not deleted_source_ids:
            return

        logger.info(
            f"Deleting {len(deleted_source_ids)} entries ({len(deleted_source_ids)*2} cards)..."
        )

        note_ids_to_delete = []
        for source_id in deleted_source_ids:
            mapping = state.get_mapping(source_id)
            if mapping:
                if mapping.es_en_note_id:
                    note_ids_to_delete.append(mapping.es_en_note_id)
                if mapping.en_es_note_id:
                    note_ids_to_delete.append(mapping.en_es_note_id)

        if note_ids_to_delete:
            try:
                self.client.delete_notes(note_ids_to_delete)
                logger.info(f"✓ Deleted {len(note_ids_to_delete)} cards")

                # Remove mappings
                for source_id in deleted_source_ids:
                    if source_id in state.mappings:
                        del state.mappings[source_id]

            except AnkiAPIError as e:
                logger.error(f"Failed to delete notes: {e}")

    def _build_note(self, trans: Translation, direction: str) -> Dict:
        """Build Anki note dictionary.

        Args:
            trans: Translation to build note from
            direction: Either "es_en" or "en_es"

        Returns:
            Note dictionary for Anki-Connect
        """
        fields = self._build_fields(trans, direction)

        return {
            "deckName": self.config.deck_name,
            "modelName": self.config.model_name,
            "fields": fields,
            "tags": [self.config.tag_prefix] + trans.tags,
        }

    def _build_fields(self, trans: Translation, direction: str) -> Dict[str, str]:
        """Build note fields dictionary.

        Args:
            trans: Translation to build fields from
            direction: Either "es_en" or "en_es"

        Returns:
            Fields dictionary
        """
        if direction == "es_en":
            front = trans.spanish
            back = trans.english
        else:  # en_es
            front = trans.english
            back = trans.spanish

        # Truncate example if needed
        example = trans.example
        if (
            self.config.include_examples
            and example
            and len(example) > self.config.max_example_length
        ):
            example = example[: self.config.max_example_length] + "..."

        return {
            FIELD_FRONT: front,
            FIELD_BACK: back,
            FIELD_EXAMPLE: example if self.config.include_examples else "",
            FIELD_NOTES: trans.notes if self.config.include_notes else "",
        }
