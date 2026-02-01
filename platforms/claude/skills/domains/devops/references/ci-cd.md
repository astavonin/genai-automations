# CI/CD Pipeline Best Practices

## Pipeline Design Principles

### 1. Keep Pipelines Simple
- Readable and maintainable
- Clear separation of stages
- Avoid complex logic in YAML
- Use scripts for complex operations

### 2. Fail Fast
- Run quick checks first (linting, formatting)
- Expensive operations last (integration tests, deployment)
- Parallel execution where possible

### 3. Cache Dependencies
- Cache package managers (npm, pip, cargo, go modules)
- Cache Docker layers
- Cache build artifacts

## GitHub Actions Example

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Run linter
        run: npm run lint

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'

      - run: npm ci
      - run: npm test

      - name: Upload coverage
        uses: codecov/codecov-action@v3
        if: success()

  build:
    needs: [lint, test]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build Docker image
        run: docker build -t myapp:${{ github.sha }} .

      - name: Save image
        run: docker save myapp:${{ github.sha }} | gzip > image.tar.gz

      - name: Upload artifact
        uses: actions/upload-artifact@v3
        with:
          name: docker-image
          path: image.tar.gz
          retention-days: 7
```

## GitLab CI Example

```yaml
stages:
  - lint
  - test
  - build

variables:
  DOCKER_BUILDKIT: 1

# Template for Node.js jobs
.node-template:
  image: node:20-alpine
  cache:
    key:
      files:
        - package-lock.json
    paths:
      - node_modules/
  before_script:
    - npm ci

lint:
  extends: .node-template
  stage: lint
  script:
    - npm run lint

test:
  extends: .node-template
  stage: test
  script:
    - npm test
  coverage: '/All files[^|]*\|[^|]*\s+([\d\.]+)/'
  artifacts:
    reports:
      coverage_report:
        coverage_format: cobertura
        path: coverage/cobertura-coverage.xml

build:
  stage: build
  image: docker:24-alpine
  services:
    - docker:24-dind
  before_script:
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY
  script:
    - docker build -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA .
    - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
  only:
    - main
    - merge_requests
```

## Caching Strategies

### Package Manager Caches

**npm:**
```yaml
- uses: actions/setup-node@v4
  with:
    cache: 'npm'
```

**pip:**
```yaml
- uses: actions/setup-python@v5
  with:
    cache: 'pip'
```

**cargo:**
```yaml
- uses: actions/cache@v3
  with:
    path: |
      ~/.cargo/bin/
      ~/.cargo/registry/index/
      ~/.cargo/registry/cache/
      ~/.cargo/git/db/
      target/
    key: ${{ runner.os }}-cargo-${{ hashFiles('**/Cargo.lock') }}
```

### Docker Layer Caching

**GitHub Actions with BuildKit:**
```yaml
- name: Set up Docker Buildx
  uses: docker/setup-buildx-action@v3

- name: Build and push
  uses: docker/build-push-action@v5
  with:
    context: .
    push: true
    tags: myapp:latest
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

**GitLab CI:**
```yaml
build:
  image: docker:24-alpine
  services:
    - docker:24-dind
  variables:
    DOCKER_BUILDKIT: 1
  script:
    - docker build
        --cache-from $CI_REGISTRY_IMAGE:latest
        --build-arg BUILDKIT_INLINE_CACHE=1
        -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA .
```

## Secret Management

### GitHub Actions
```yaml
steps:
  - name: Deploy
    env:
      API_KEY: ${{ secrets.API_KEY }}
      DATABASE_URL: ${{ secrets.DATABASE_URL }}
    run: |
      echo "Deploying with credentials..."
```

### GitLab CI
```yaml
deploy:
  script:
    - echo "Using $API_KEY"  # From CI/CD variables
  only:
    - main
```

## Matrix Builds

Use judiciously - only when truly needed:

```yaml
jobs:
  test:
    strategy:
      matrix:
        node-version: [18, 20, 22]
        os: [ubuntu-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node-version }}
      - run: npm ci
      - run: npm test
```

## Concurrency Control

Prevent resource contention:

```yaml
# GitHub Actions
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

# GitLab CI
workflow:
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
      when: always
    - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
      when: always
    - when: never
```

## Artifact Retention

```yaml
# GitHub Actions
- uses: actions/upload-artifact@v3
  with:
    name: build-output
    path: dist/
    retention-days: 7  # Clean up after 7 days

# GitLab CI
artifacts:
  paths:
    - dist/
  expire_in: 1 week
```

## Best Practices Summary

1. **Simple pipelines:** Readable YAML, complex logic in scripts
2. **Fail fast:** Quick checks first, expensive operations last
3. **Cache aggressively:** Package managers, Docker layers, build artifacts
4. **Proper secrets:** Never commit, use CI secret management
5. **Smart parallelization:** Matrix builds only when needed
6. **Concurrency control:** Prevent resource waste
7. **Artifact cleanup:** Set retention policies
8. **Local reproducibility:** Developers can run CI steps locally
