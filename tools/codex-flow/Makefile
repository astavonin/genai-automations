VENV := .venv
ROOT := $(CURDIR)
PYTHON := $(VENV)/bin/python
PIP := $(VENV)/bin/pip
PYTEST := $(VENV)/bin/pytest
BLACK := $(VENV)/bin/black
FLAKE8 := $(VENV)/bin/flake8
MYPY := $(VENV)/bin/mypy
SMOKE_REPO := /tmp/codex-flow-smoke-repo
REVIEW_SMOKE_REPO := /tmp/codex-flow-review-smoke-repo
PIPX_PYTHON ?= python3.12

.PHONY: help venv install-dev install test lint itest-implement itest-review itest-clean implement-itest review-itest itest clean

help:
	@echo "Available commands:"
	@echo "  make venv        - Create virtual environment"
	@echo "  make install-dev - Install package and test dependencies into venv"
	@echo "  make test        - Run tests"
	@echo "  make lint        - Run black, flake8, and mypy"
	@echo "  make itest-implement - Recreate the implementation smoke repo in /tmp and run pytest there"
	@echo "  make itest-review - Recreate the review smoke repo in /tmp and run pytest there"
	@echo "  make itest-clean - Remove smoke repos from /tmp"
	@echo "  make install     - Install codex-flow globally via pipx (editable)"
	@echo "  make clean       - Remove caches and build artifacts"
	@echo ""
	@echo "Install override:"
	@echo "  make install PIPX_PYTHON=/path/to/python3.12"

$(VENV)/bin/pip:
	python3 -m venv $(VENV)

venv: $(VENV)/bin/pip

install-dev: $(VENV)/bin/pip
	$(PIP) install --upgrade pip setuptools wheel
	$(PIP) install -e ".[dev]"

test: install-dev
	$(PYTEST)

lint: install-dev
	$(BLACK) --check codex_flow tests
	$(FLAKE8) codex_flow tests
	$(MYPY) codex_flow

itest-implement: install-dev
	rm -rf $(SMOKE_REPO)
	mkdir -p $(SMOKE_REPO)
	cp -R itest-fixture/. $(SMOKE_REPO)/
	git -C $(SMOKE_REPO) init
	cd $(SMOKE_REPO) && PYTHONPATH=$(SMOKE_REPO) $(ROOT)/$(PYTEST)
	@echo ""
	@echo "Next:"
	@echo "  codex-flow implement $(ROOT)/examples/sample-implementation-request.md"

implement-itest: itest-implement

itest: itest-implement

itest-review: install-dev
	rm -rf $(REVIEW_SMOKE_REPO)
	mkdir -p $(REVIEW_SMOKE_REPO)
	cp -R itest-review-fixture/. $(REVIEW_SMOKE_REPO)/
	git -C $(REVIEW_SMOKE_REPO) init
	git -C $(REVIEW_SMOKE_REPO) config user.name "codex-flow"
	git -C $(REVIEW_SMOKE_REPO) config user.email "codex-flow@example.com"
	git -C $(REVIEW_SMOKE_REPO) add .
	git -C $(REVIEW_SMOKE_REPO) commit -m "Baseline smoke fixture"
	python3 -c 'from pathlib import Path; repo = Path("$(REVIEW_SMOKE_REPO)"); (repo / "src/example.py").write_text("""\"\"\"Example module for codex-flow review smoke testing.\"\"\"\n\n\ndef ping() -> str:\n    \"\"\"Return a constant value used by the baseline test.\"\"\"\n    return \"pong\"\n\n\ndef format_greeting(name: str) -> str:\n    \"\"\"Return a friendly greeting after trimming surrounding whitespace.\"\"\"\n    return f\"Hello, {name.strip()}!\"\n""", encoding="utf-8"); (repo / "tests/test_example.py").write_text("""\"\"\"Tests for the codex-flow review smoke repo.\"\"\"\n\nfrom src.example import format_greeting, ping\n\n\ndef test_ping_returns_pong() -> None:\n    assert ping() == \"pong\"\n\n\ndef test_format_greeting_trims_whitespace() -> None:\n    assert format_greeting(\"  Ada  \") == \"Hello, Ada!\"\n""", encoding="utf-8")'
	cd $(REVIEW_SMOKE_REPO) && PYTHONPATH=$(REVIEW_SMOKE_REPO) $(ROOT)/$(PYTEST)
	@echo ""
	@echo "Next:"
	@echo "  codex-flow review $(ROOT)/examples/sample-review-request.md"

review-itest: itest-review

itest-clean:
	rm -rf $(SMOKE_REPO) $(REVIEW_SMOKE_REPO)

install: install-dev
	pipx install --python "$(PIPX_PYTHON)" -e . --force

clean:
	rm -rf $(VENV) build dist *.egg-info .pytest_cache
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete
