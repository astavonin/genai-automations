"""Command-line interface for anki_sync."""

import sys
import argparse
import json
import logging
from pathlib import Path
from typing import List, Optional

from .config import Config
from .handlers import SetupHandler, PushHandler, PullHandler
from .models import SyncState
from .exceptions import AnkiSyncError
from .utils import setup_logging

logger = logging.getLogger(__name__)


def cmd_setup(args: argparse.Namespace, config: Config) -> int:
    """Execute setup command.

    Args:
        args: Parsed arguments
        config: Configuration

    Returns:
        Exit code (0 for success, non-zero for failure)
    """
    try:
        handler = SetupHandler(config, dry_run=args.dry_run)
        handler.execute()
        return 0
    except AnkiSyncError as e:
        logger.error(f"Setup failed: {e}")
        return 1


def cmd_push(args: argparse.Namespace, config: Config) -> int:
    """Execute push command.

    Args:
        args: Parsed arguments
        config: Configuration

    Returns:
        Exit code (0 for success, non-zero for failure)
    """
    try:
        handler = PushHandler(config, dry_run=args.dry_run)
        handler.execute()
        return 0
    except AnkiSyncError as e:
        logger.error(f"Push failed: {e}")
        return 1


def cmd_pull(args: argparse.Namespace, config: Config) -> int:
    """Execute pull command.

    Args:
        args: Parsed arguments
        config: Configuration

    Returns:
        Exit code (0 for success, non-zero for failure)
    """
    try:
        handler = PullHandler(config, dry_run=args.dry_run)
        handler.execute()
        return 0
    except AnkiSyncError as e:
        logger.error(f"Pull failed: {e}")
        return 1


def cmd_status(args: argparse.Namespace, config: Config) -> int:
    """Execute status command.

    Args:
        args: Parsed arguments
        config: Configuration

    Returns:
        Exit code (0 for success, non-zero for failure)
    """
    try:
        state = SyncState.load(config.state_file)

        print("=== Anki Sync Status ===")
        print(f"Deck: {state.deck_name or '(not initialized)'}")
        print(f"Model: {state.model_name or '(not initialized)'}")
        print(f"Tracked entries: {len(state.mappings)}")
        print(f"Last push: {state.last_push or 'never'}")
        print(f"Last pull: {state.last_pull or 'never'}")

        return 0
    except (AnkiSyncError, json.JSONDecodeError, OSError) as e:
        logger.error(f"Status failed: {e}")
        return 1


def cmd_diff(args: argparse.Namespace, config: Config) -> int:
    """Execute diff command (same as push --dry-run).

    Args:
        args: Parsed arguments
        config: Configuration

    Returns:
        Exit code (0 for success, non-zero for failure)
    """
    try:
        handler = PushHandler(config, dry_run=True)
        handler.execute()
        return 0
    except AnkiSyncError as e:
        logger.error(f"Diff failed: {e}")
        return 1


def cmd_verify(args: argparse.Namespace, config: Config) -> int:
    """Execute verify command.

    Args:
        args: Parsed arguments
        config: Configuration

    Returns:
        Exit code (0 for success, non-zero for failure)
    """
    try:
        from .client import AnkiConnectClient

        client = AnkiConnectClient(config.anki_host, config.anki_port, config.anki_timeout)
        state = SyncState.load(config.state_file)

        print("=== Anki Sync Verification ===")

        # Check connection
        try:
            version = client.version()
            print(f"✓ Connected to Anki-Connect (version {version})")
        except Exception as e:
            print(f"✗ Cannot connect to Anki-Connect: {e}")
            return 1

        # Check deck exists
        decks = client.deck_names()
        if config.deck_name in decks:
            print(f"✓ Deck '{config.deck_name}' exists")
        else:
            print(f"✗ Deck '{config.deck_name}' not found")

        # Check model exists
        models = client.model_names()
        if config.model_name in models:
            print(f"✓ Model '{config.model_name}' exists")
        else:
            print(f"✗ Model '{config.model_name}' not found")

        # Check synced notes
        query = f'deck:"{config.deck_name}" tag:{config.tag_prefix}'
        note_ids = client.find_notes(query)
        print(f"✓ Found {len(note_ids)} synced notes in Anki")

        # Check mappings consistency
        note_ids_set = set(note_ids)  # Convert to set for O(1) lookups
        missing_count = 0
        for source_id, mapping in state.mappings.items():
            if mapping.es_en_note_id and mapping.es_en_note_id not in note_ids_set:
                print(f"✗ ES->EN note {mapping.es_en_note_id} for '{source_id}' not found in Anki")
                missing_count += 1
            if mapping.en_es_note_id and mapping.en_es_note_id not in note_ids_set:
                print(f"✗ EN->ES note {mapping.en_es_note_id} for '{source_id}' not found in Anki")
                missing_count += 1

        if missing_count == 0:
            print("✓ All mapped notes exist in Anki")
        else:
            print(f"✗ {missing_count} mapped notes missing from Anki")

        print("\n✓ Verification complete")
        return 0

    except AnkiSyncError as e:
        logger.error(f"Verify failed: {e}")
        return 1


def main(argv: Optional[List[str]] = None) -> int:
    """Main CLI entry point.

    Args:
        argv: Optional command-line arguments (defaults to sys.argv)

    Returns:
        Exit code (0 for success, non-zero for failure)
    """
    parser = argparse.ArgumentParser(
        prog="anki-sync",
        description="Bidirectional vocabulary sync with Anki Desktop",
    )

    # Global options
    parser.add_argument(
        "--config", type=Path, help="Config file path (default: search standard locations)"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview changes without applying them",
    )
    parser.add_argument("--verbose", "-v", action="store_true", help="Verbose output (DEBUG level)")

    # Subcommands
    subparsers = parser.add_subparsers(dest="command", required=True)

    # Setup command
    subparsers.add_parser("setup", help="Initialize Anki deck and note model")

    # Push command
    subparsers.add_parser("push", help="Push translations to Anki")

    # Pull command
    subparsers.add_parser("pull", help="Pull Anki changes back to translations")

    # Status command
    subparsers.add_parser("status", help="Show sync status")

    # Diff command
    subparsers.add_parser("diff", help="Preview pending changes (same as push --dry-run)")

    # Verify command
    subparsers.add_parser("verify", help="Verify sync integrity")

    # Parse arguments
    args = parser.parse_args(argv)

    # Setup logging before anything else
    setup_logging(verbose=args.verbose)

    # Command dispatch table
    commands = {
        "setup": cmd_setup,
        "push": cmd_push,
        "pull": cmd_pull,
        "status": cmd_status,
        "diff": cmd_diff,
        "verify": cmd_verify,
    }

    try:
        # Load config
        config = Config.load(args.config)

        # Dispatch to command
        return commands[args.command](args, config)

    except AnkiSyncError as e:
        logger.error(str(e))
        return 1
    except Exception as e:
        logger.exception(f"Unexpected error: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
