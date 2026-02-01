# Docker Best Practices

## Multi-Stage Builds

Use multi-stage builds to minimize final image size:

```dockerfile
# Build stage
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o app

# Runtime stage
FROM alpine:3.19
RUN apk --no-cache add ca-certificates
COPY --from=builder /app/app /app
USER nobody
ENTRYPOINT ["/app"]
```

## Layer Caching

Order instructions from least to most frequently changing:

```dockerfile
FROM node:20-alpine

# 1. System dependencies (rarely change)
RUN apk add --no-cache git

# 2. Package dependencies (change occasionally)
COPY package.json package-lock.json ./
RUN npm ci --only=production

# 3. Application code (changes frequently)
COPY . .

CMD ["node", "index.js"]
```

## Base Image Selection

Choose minimal base images:

- **Alpine:** Smallest (5-10 MB), good for most cases
- **Distroless:** No shell, maximum security
- **Slim variants:** Ubuntu/Debian slim (smaller than full)
- **Scratch:** Absolute minimum for static binaries

```dockerfile
# Alpine - small and has package manager
FROM alpine:3.19

# Distroless - no shell, security focused
FROM gcr.io/distroless/static-debian12

# Slim - smaller than full Debian
FROM debian:12-slim

# Scratch - static binaries only
FROM scratch
```

## .dockerignore

Exclude unnecessary files:

```dockerignore
# Version control
.git
.gitignore

# Dependencies
node_modules
vendor

# Build artifacts
*.o
*.a
dist
build

# Documentation
README.md
docs

# CI/CD
.github
.gitlab-ci.yml
Jenkinsfile

# Development
.env
.vscode
.idea
*.log
```

## Security Best Practices

### Run as Non-Root User

```dockerfile
FROM alpine:3.19

# Create non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# ... install and build ...

# Switch to non-root
USER appuser

CMD ["/app"]
```

### Pin Versions

```dockerfile
# Bad - unpredictable
FROM node:latest

# Good - reproducible
FROM node:20.11.0-alpine3.19
```

## Health Checks

```dockerfile
FROM nginx:1.25-alpine

COPY nginx.conf /etc/nginx/nginx.conf
COPY dist /usr/share/nginx/html

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

## BuildKit Features

Enable BuildKit for better caching and features:

```dockerfile
# syntax=docker/dockerfile:1

FROM golang:1.21-alpine AS builder

# Cache mount for go modules
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go build -o app

FROM alpine:3.19
COPY --from=builder /app/app /app
CMD ["/app"]
```

Build with BuildKit:
```bash
DOCKER_BUILDKIT=1 docker build -t myapp .
```

## Resource Limits

```dockerfile
FROM node:20-alpine

# Set memory limits for Node.js
ENV NODE_OPTIONS="--max-old-space-size=512"

CMD ["node", "--max-old-space-size=512", "index.js"]
```

In docker-compose.yml:
```yaml
services:
  app:
    image: myapp
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
        reservations:
          cpus: '0.25'
          memory: 256M
```

## Common Patterns

### Development vs Production

```dockerfile
# Multi-target for dev and prod
FROM node:20-alpine AS base
WORKDIR /app
COPY package*.json ./

FROM base AS development
RUN npm install
COPY . .
CMD ["npm", "run", "dev"]

FROM base AS production
RUN npm ci --only=production
COPY . .
CMD ["node", "index.js"]
```

Build:
```bash
# Development
docker build --target development -t myapp:dev .

# Production
docker build --target production -t myapp:prod .
```

## Summary

1. Use multi-stage builds to minimize size
2. Order layers from least to most frequently changing
3. Choose minimal base images (Alpine, distroless, slim)
4. Use .dockerignore to exclude unnecessary files
5. Run as non-root user
6. Pin versions for reproducibility
7. Add health checks for services
8. Leverage BuildKit for better caching
9. Set appropriate resource limits
