# Local-CI Parity

Principle: What runs in CI should run locally, and vice versa.

## Why Local-CI Parity Matters

1. **Faster debugging:** Reproduce CI failures locally
2. **Confidence:** Know it works before pushing
3. **Productivity:** No "works on my machine" issues
4. **Developer experience:** Consistent tooling everywhere

## Strategies

### 1. Use Same Docker Images

**Bad:**
```yaml
# CI uses ubuntu-latest, developers use various OS
runs-on: ubuntu-latest
```

**Good:**
```yaml
# CI and local both use same Docker image
jobs:
  test:
    container: node:20-alpine
```

Developers run:
```bash
docker run --rm -v $(pwd):/app -w /app node:20-alpine npm test
```

### 2. Shared Scripts (Makefile)

Create a Makefile that works everywhere:

```makefile
.PHONY: test lint build docker-build

# Works locally and in CI
test:
	npm test

lint:
	npm run lint

build:
	npm run build

# Docker-based commands for consistency
docker-test:
	docker run --rm -v $(PWD):/app -w /app node:20-alpine npm test

docker-lint:
	docker run --rm -v $(PWD):/app -w /app node:20-alpine npm run lint
```

CI configuration:
```yaml
# GitHub Actions
steps:
  - run: make test
  - run: make lint

# GitLab CI
script:
  - make test
  - make lint
```

Developers run:
```bash
make test
make lint
# or
make docker-test  # Guaranteed same environment as CI
```

### 3. Environment Variables with Defaults

**config.sh:**
```bash
#!/usr/bin/env bash
set -euo pipefail

# Sensible defaults for local development
export NODE_ENV="${NODE_ENV:-development}"
export DATABASE_URL="${DATABASE_URL:-postgres://localhost/myapp_dev}"
export REDIS_URL="${REDIS_URL:-redis://localhost:6379}"

# CI overrides these via secrets
export API_KEY="${API_KEY:-dev-key-not-for-production}"
```

Both local and CI source this file:
```bash
source config.sh
npm start
```

### 4. Docker Compose for Local Development

**docker-compose.yml:**
```yaml
services:
  app:
    image: node:20-alpine
    volumes:
      - .:/app
    working_dir: /app
    command: npm run dev
    environment:
      - NODE_ENV=development
    ports:
      - "3000:3000"
    depends_on:
      - db
      - redis

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: myapp_dev
      POSTGRES_PASSWORD: devpassword
    ports:
      - "5432:5432"

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
```

Developers:
```bash
docker-compose up
```

CI runs same services:
```yaml
# GitHub Actions
services:
  postgres:
    image: postgres:16-alpine
  redis:
    image: redis:7-alpine
```

### 5. Act for GitHub Actions

Run GitHub Actions locally using `act`:

```bash
# Install act
brew install act  # macOS
# or
curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash

# Run a job locally
act -j test

# Run specific workflow
act pull_request

# Use custom Docker image
act -P ubuntu-latest=node:20-alpine
```

**.actrc** (project configuration):
```
-P ubuntu-latest=catthehacker/ubuntu:act-latest
--container-architecture linux/amd64
```

### 6. GitLab Runner Locally

Run GitLab CI locally:

```bash
# Install gitlab-runner
brew install gitlab-runner

# Execute a job
gitlab-runner exec docker test

# Execute with custom image
gitlab-runner exec docker --docker-image node:20-alpine test
```

### 7. Avoid CI-Specific Magic

**Bad - CI-only scripts:**
```yaml
# Only works in CI
script:
  - |
    if [ "$CI" = "true" ]; then
      special-ci-setup
    fi
  - npm test
```

**Good - Works everywhere:**
```yaml
script:
  - ./scripts/setup.sh  # Works locally and in CI
  - npm test
```

**setup.sh:**
```bash
#!/usr/bin/env bash
set -euo pipefail

# Auto-detect environment
if [ -n "${CI:-}" ]; then
  echo "Running in CI"
else
  echo "Running locally"
fi

# Common setup that works everywhere
npm ci
```

### 8. Document Differences

When differences are unavoidable, document them clearly:

**README.md:**
```markdown
## Running Tests

### Locally
```bash
make test
```

### In CI
Same command: `make test`

**Known Differences:**
- CI uses fresh environment (no cached dependencies)
- CI has access to secrets via environment variables
- CI runs on Ubuntu latest, you may use different OS
```

## Common Pitfalls

### ❌ Platform-Specific Commands
```bash
# Fails on macOS (GNU vs BSD)
sed -i 's/foo/bar/g' file.txt
```

### ✅ Use Portable Commands
```bash
# Works everywhere via Docker
docker run --rm -v $(PWD):/data alpine sed -i 's/foo/bar/g' /data/file.txt
```

### ❌ Hardcoded Paths
```yaml
script:
  - /usr/local/bin/my-tool
```

### ✅ Use PATH or Relative Paths
```yaml
script:
  - my-tool  # Assumes it's in PATH
  - ./scripts/my-tool.sh  # Relative path
```

### ❌ CI-Only Dependencies
```yaml
# Special tools only in CI
before_script:
  - apt-get install special-tool
```

### ✅ Document Installation
```markdown
## Prerequisites

Install `special-tool`:
```bash
# macOS
brew install special-tool

# Linux
apt-get install special-tool

# or use Docker (works everywhere)
docker run --rm special-tool/image
```
```

## Checklist

- [ ] Can developers run `make test` locally?
- [ ] Same Docker images used locally and in CI?
- [ ] Environment variables have sensible defaults?
- [ ] Dependencies documented and installable locally?
- [ ] Docker Compose available for local services?
- [ ] No CI-specific magic in scripts?
- [ ] Unavoidable differences documented?
- [ ] CI can be run locally (act, gitlab-runner)?

## Summary

**Goal:** Zero surprises between local and CI environments.

**Key strategies:**
1. Same Docker images everywhere
2. Makefile or task runner for common commands
3. Environment variables with defaults
4. Docker Compose for services
5. Run CI locally (act, gitlab-runner)
6. Avoid CI-specific logic
7. Document any differences
