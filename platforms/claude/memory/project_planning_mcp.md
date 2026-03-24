---
name: planning-mcp language and stack
description: planning-mcp MCP server is written in Go, not Python. ci-platform-manager may migrate to Go later.
type: project
---

planning-mcp (new repo at `~/projects/planning-mcp`) is implemented in **Go**.

Key stack decisions:
- MCP SDK: `github.com/mark3labs/mcp-go` (stdio transport)
- SQLite: `modernc.org/sqlite` (pure Go, no CGO)
- Testing: `go test` + `github.com/stretchr/testify`
- Package layout: `cmd/planning-mcp/main.go` entrypoint, `internal/` packages

**Why:** User preference. ci-platform-manager (currently Python) may migrate to Go later — decision not yet finalized.

**How to apply:** When working on planning-mcp, use Go idioms (Effective Go, Go Code Review Comments). Do not suggest Python alternatives. Migration tests (`_test.go` alongside packages, `:memory:` DSN for in-memory SQLite).
