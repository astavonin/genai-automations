"""Tests for the codex-flow review smoke repo."""

from src.example import ping


def test_ping_returns_pong() -> None:
    assert ping() == "pong"
