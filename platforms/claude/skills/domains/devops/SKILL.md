---
name: devops
description: DevOps practices, CI/CD, containerization, and infrastructure automation
---

# DevOps Skill

Infrastructure automation, containerization, CI/CD pipelines, and developer experience optimization.

## Core Principles

### 1. Local-CI Parity
Create identical experiences between local development and CI environments:
- Use same Docker images and versions locally and in CI
- Shared scripts (Makefile, shell scripts, task runners) work in both contexts
- Avoid CI-specific magic - if it runs in CI, developers can run it locally
- Environment variables with sensible defaults for local development
- Document unavoidable differences

### 2. Resource Efficiency
Optimize resource consumption aggressively:
- **Docker Images:** Multi-stage builds, minimal base images (Alpine, distroless, slim), proper layer caching
- **CI Pipelines:** Dependency caching, shallow clones, smart parallelization
- **Memory & CPU:** Appropriate resource limits, avoid unnecessary services
- **Storage:** Clean up artifacts, effective .dockerignore, minimize image sizes
- **Time:** Fast feedback loops, fail fast, skip unnecessary steps

### 3. Developer Experience
Every change should make developers' lives easier:
- Seamless workflows between local and CI
- Easy to understand, debug, and modify
- Clear error messages and validation
- Sensible defaults that work out of the box

## Best Practices

### Docker
- Pin specific versions for reproducibility (not `latest`)
- Order Dockerfile instructions from least to most frequently changing
- Use `.dockerignore` to exclude unnecessary files
- Run as non-root user when possible
- Use health checks for services
- Leverage BuildKit features for better caching

### CI/CD
- Keep pipelines simple and readable
- Use matrix builds judiciously
- Implement proper secret management
- Cache dependencies between runs
- Concurrency controls to prevent resource contention
- Proper artifact retention policies

### Scripting & Automation
- Prefer Makefiles or task runners for common operations
- Write idempotent scripts (safe to re-run)
- Include helpful error messages and validation
- Support dry-run modes for destructive operations
- Follow shell scripting best practices (see `skills/languages/shell/`)

### Environment Management
- Use `.env.example` files with documentation
- Never commit secrets
- Provide sensible defaults
- Support configuration through environment variables

## Quality Checks

Before finalizing DevOps configurations:
- [ ] Can developers run this locally with minimal setup?
- [ ] Does it work the same way in CI?
- [ ] Are resources used efficiently?
- [ ] Proper error handling and helpful messages?
- [ ] Configuration properly documented?
- [ ] Secrets handled securely?
- [ ] Caching implemented where beneficial?
- [ ] Versions pinned for reproducibility?

## References

See `references/` directory for:
- Docker best practices and patterns
- CI/CD pipeline design
- Infrastructure as Code
- Local-CI parity strategies
