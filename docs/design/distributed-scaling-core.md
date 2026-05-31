# ADR: Scaling Forgejo-MCP for Distributed Multi-User Environments

## Status
WIP (Work In Progress) - Early State Workbench

## Context
Forgejo-MCP was initially designed as a lean, singleton-based MCP server. As we move toward a multi-user remote instance model (via SSE/HTTP), the current architecture faces several bottlenecks:
- **Transport Limitations:** Default Go HTTP clients limit concurrent persistent connections to 2 per host, causing handshake overhead for concurrent users.
- **Observability:** Lack of request-scoped tracing makes it difficult to correlate MCP tool calls with upstream Forgejo API performance.
- **Resource Governance:** No explicit quotas on concurrency or memory pressure, making the service vulnerable to noisy-neighbor effects in a multi-tenant setup.

## Decision
We will transition the service architecture to support distributed scaling and robust multi-tenancy.

### 1. Connection Pool Optimization
- Implement a custom `http.Transport` for the Forgejo client.
- Expose `MaxIdleConnsPerHost` and `MaxConnsPerHost` as configurable parameters.
- Default to sane "production-grade" values (e.g., 100/10) to eliminate handshake storms.

### 2. Request-Scoped Observability
- Introduce structured span logging.
- Pass `TraceID` via `context.Context` from the transport layer down to the Forgejo SDK calls.
- Enhance `LogAPICall` to include correlation IDs.

### 3. Edge-Awareness (XFF Support)
- Support `X-Forwarded-For` and `X-Real-IP` headers to ensure accurate audit logs and enable downstream rate limiting.

### 4. Configuration Evolution
- Prepare for a structured configuration model to manage complex resource quotas that exceed the capabilities of simple environment variables.

## Consequences
- **Pros:** Dramatically improved throughput for concurrent users; better debuggability in production; protection against upstream service exhaustion.
- **Cons:** Increased internal complexity regarding context management; requires callers (proxies/LLMs) to be configured for tracing to see full benefits.
