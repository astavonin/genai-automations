"""CLI for codex-flow."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import cast

from .exceptions import CodexFlowError
from .progress import PROGRESS_MODES, ProgressConfig, ProgressMode
from .runner import run_implementation, run_review


def build_parser() -> argparse.ArgumentParser:
    """Create the top-level argument parser."""
    parser = argparse.ArgumentParser(
        prog="codex-flow",
        description="Run Codex implementation and review workflows from Markdown requests.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    implement_parser = subparsers.add_parser(
        "implement", help="Run an implementation workflow from a design document."
    )
    _add_progress_arguments(implement_parser)
    implement_parser.add_argument("request", type=Path, help="Path to the implementation request.")

    review_parser = subparsers.add_parser(
        "review", help="Run a review workflow from a review request."
    )
    _add_progress_arguments(review_parser)
    review_parser.add_argument("request", type=Path, help="Path to the review request.")

    return parser


def _add_progress_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--progress",
        choices=PROGRESS_MODES,
        default="plain",
        help="Progress output mode. Progress is written to stderr.",
    )
    parser.add_argument(
        "--no-progress-log",
        action="store_true",
        help="Do not persist normalized progress events under the external codex-flow state dir.",
    )


def main(argv: list[str] | None = None) -> int:
    """Run the codex-flow CLI."""
    parser = build_parser()
    args = parser.parse_args(argv)
    progress_config = ProgressConfig(
        mode=cast(ProgressMode, args.progress),
        log_enabled=not args.no_progress_log,
    )

    try:
        if args.command == "implement":
            output_path = run_implementation(args.request, progress_config)
        else:
            output_path = run_review(args.request, progress_config)
    except CodexFlowError as err:
        parser.exit(status=1, message=f"codex-flow: {err}\n")

    print(output_path)
    return 0
