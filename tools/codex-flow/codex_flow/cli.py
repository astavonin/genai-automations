"""CLI for codex-flow."""

from __future__ import annotations

import argparse
from pathlib import Path

from .exceptions import CodexFlowError
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
    implement_parser.add_argument("request", type=Path, help="Path to the implementation request.")

    review_parser = subparsers.add_parser(
        "review", help="Run a review workflow from a review request."
    )
    review_parser.add_argument("request", type=Path, help="Path to the review request.")

    return parser


def main(argv: list[str] | None = None) -> int:
    """Run the codex-flow CLI."""
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        if args.command == "implement":
            output_path = run_implementation(args.request)
        else:
            output_path = run_review(args.request)
    except CodexFlowError as err:
        parser.exit(status=1, message=f"codex-flow: {err}\n")

    print(output_path)
    return 0
