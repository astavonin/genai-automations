"""Pull handler for syncing Anki changes back to translations."""

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
from ..exceptions import AnkiAPIError
from ..utils.translation_io import load_translations, save_translations

logger = logging.getLogger(__name__)


class PullHandler:
    """Pull Anki changes to translations."""

    def __init__(self, config: Config, dry_run: bool = False):
        """Initialize pull handler.

        Args:
            config: Configuration instance
            dry_run: If True, preview changes without applying
        """
        self.config = config
        self.dry_run = dry_run
        self.client = AnkiConnectClient(config.anki_host, config.anki_port, config.anki_timeout)

    def execute(self) -> None:
        """Pull Anki changes to translations."""
        logger.info("Pulling Anki changes to translations...")

        # 1. Load state
        state = SyncState.load(self.config.state_file)

        # 2. Query Anki for all synced notes
        query = f'deck:"{self.config.deck_name}" tag:{self.config.tag_prefix}'
        try:
            note_ids = self.client.find_notes(query)
            logger.debug(f"Found {len(note_ids)} synced notes in Anki")

            if not note_ids:
                logger.info("No synced notes found in Anki")
                return

            notes_data = self.client.notes_info(note_ids)
        except AnkiAPIError as e:
            logger.error(f"Failed to query Anki notes: {e}")
            return

        # 3. Detect modified notes
        modified_notes = self._detect_modified_notes(notes_data, state)

        # 4. Show pull diff
        self._show_pull_diff(modified_notes)

        if self.dry_run:
            logger.info("[DRY RUN] No changes applied")
            return

        if not modified_notes:
            logger.info("✓ No changes to pull")
            return

        # 5. Load current translations
        translations = self._load_translations()
        trans_by_id = {t.source_id: t for t in translations}

        # 6. Apply Anki changes to translations
        modified_count = 0
        for note, mapping in modified_notes:
            # Get current source_id from mapping (might be old if remapped earlier)
            current_source_id = mapping.source_id

            if current_source_id in trans_by_id:
                trans = trans_by_id[current_source_id]
                old_source_id = trans.source_id

                if self._update_translation(trans, note, mapping, state):
                    mapping.last_pull_mod = note["mod"]
                    modified_count += 1

                # If source_id changed, update the lookup dictionary
                new_source_id = trans.source_id
                if new_source_id != old_source_id and old_source_id in trans_by_id:
                    trans_by_id.pop(old_source_id)
                    trans_by_id[new_source_id] = trans
            else:
                logger.warning(
                    f"Mapping for source_id '{current_source_id}' not found in translations"
                )

        # 7. Save translations FIRST, then state (error handling order)
        try:
            save_translations(self.config.source_file, translations)
            logger.info(f"✓ Updated {modified_count} translations")
        except Exception as e:
            logger.error(f"Failed to save translations: {e}")
            logger.error("State file NOT updated to prevent divergence")
            raise

        # 8. Save state ONLY if translation save succeeded
        state.update_pull_timestamp()
        state.save(self.config.state_file)

        logger.info("✓ Pull complete")

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

    def _detect_modified_notes(
        self, notes_data: List[Dict], state: SyncState
    ) -> List[Tuple[Dict, CardMapping]]:
        """Detect notes that have been modified in Anki.

        Args:
            notes_data: List of note info dictionaries from Anki
            state: Current sync state

        Returns:
            List of (note, mapping) tuples for modified notes
        """
        modified_notes: List[Tuple[Dict, CardMapping]] = []

        for note in notes_data:
            mapping = state.find_by_note_id(note["noteId"])
            if not mapping:
                continue

            # Get card IDs for this note
            card_ids = note.get("cards", [])
            if not card_ids:
                logger.warning(f"Note {note['noteId']} has no cards")
                continue

            # Fetch card info to get modification timestamps
            try:
                cards_info = self.client.cards_info(card_ids)
                # Get the maximum mod timestamp from all cards
                max_mod = max(card["mod"] for card in cards_info)

                # Check if any card was modified since last pull
                if max_mod > mapping.last_pull_mod:
                    # Add mod to note for later use
                    note["mod"] = max_mod
                    modified_notes.append((note, mapping))
            except AnkiAPIError as e:
                logger.warning(f"Failed to get card info for note {note['noteId']}: {e}")
                continue

        logger.debug(f"Detected {len(modified_notes)} modified notes")
        return modified_notes

    def _show_pull_diff(self, modified_notes: List[Tuple[Dict, CardMapping]]) -> None:
        """Show pull diff summary.

        Args:
            modified_notes: List of (note, mapping) tuples
        """
        logger.info("=== Pull Summary ===")
        logger.info(f"Modified notes: {len(modified_notes)}")

        if logger.isEnabledFor(logging.DEBUG) and modified_notes:
            source_ids = [mapping.source_id for _, mapping in modified_notes]
            logger.debug("Modified: %s", source_ids)

    def _update_translation(
        self, trans: Translation, note: Dict, mapping: CardMapping, state: SyncState
    ) -> bool:
        """Update translation from Anki note.

        Args:
            trans: Translation to update
            note: Note info from Anki
            mapping: Card mapping
            state: Sync state to update if source_id changes

        Returns:
            True if translation was modified, False otherwise
        """
        fields = note.get("fields", {})
        modified = False
        old_source_id = mapping.source_id

        # Determine direction from note ID
        if note["noteId"] == mapping.es_en_note_id:
            # Spanish -> English card
            front = fields.get(FIELD_FRONT, {}).get("value", "")
            back = fields.get(FIELD_BACK, {}).get("value", "")

            if front and front != trans.spanish:
                logger.debug(f"Updating spanish: '{trans.spanish}' -> '{front}'")
                trans.spanish = front
                modified = True

            if back and back != trans.english:
                logger.debug(
                    f"Updating english for '{trans.spanish}': '{trans.english}' -> '{back}'"
                )
                trans.english = back
                modified = True

        elif note["noteId"] == mapping.en_es_note_id:
            # English -> Spanish card
            front = fields.get(FIELD_FRONT, {}).get("value", "")
            back = fields.get(FIELD_BACK, {}).get("value", "")

            if front and front != trans.english:
                logger.debug(f"Updating english: '{trans.english}' -> '{front}'")
                trans.english = front
                modified = True

            if back and back != trans.spanish:
                logger.debug(
                    f"Updating spanish for '{trans.english}': '{trans.spanish}' -> '{back}'"
                )
                trans.spanish = back
                modified = True

        # Update example and notes (same for both directions)
        example = fields.get(FIELD_EXAMPLE, {}).get("value", "")
        if example and example != trans.example:
            logger.debug(f"Updating example for '{trans.spanish}'")
            trans.example = example
            modified = True

        notes_field = fields.get(FIELD_NOTES, {}).get("value", "")
        if notes_field and notes_field != trans.notes:
            logger.debug(f"Updating notes for '{trans.spanish}'")
            trans.notes = notes_field
            modified = True

        # CRITICAL FIX: Update state mapping key when spanish changes
        new_source_id = trans.source_id
        if new_source_id != old_source_id:
            logger.info(f"Spanish term changed: '{old_source_id}' → '{new_source_id}'")

            # Create new mapping with new source_id
            new_mapping = CardMapping(
                source_id=new_source_id,
                es_en_note_id=mapping.es_en_note_id,
                en_es_note_id=mapping.en_es_note_id,
                last_push_hash=trans.content_hash(),
                last_pull_mod=mapping.last_pull_mod,
            )

            # Update state: remove old, add new
            state.mappings.pop(old_source_id, None)
            state.mappings[new_source_id] = new_mapping

        return modified
