# ADR: Scaling Forgejo-MCP for Distributed Multi-User Environments

## Status
Proposed

## Context
Forgejo-MCP was initially designed as a lean, singleton-based MCP server. As we move toward a multi-user remote instance model (via SSE/HTTP), the current architecture faces several bottlenecks:
- **Transport Limitations:** Default Go HTTP clients limit concurrent persistent connections to 2 per host, causing handshake overhead for concurrent users.
- **Observability:** Lack of request-scoped tracing makes it difficult to correlate MCP tool calls with upstream Forgejo API performance.
- **Resource Governance:** No explicit quotas on concurrency or memory pressure, making the service vulnerable to noisy-neighbor effects in a multi-tenant setup.

## Idea
We will transition the service architecture to support distributed scaling and robust multi-tenancy by aligning with 12-Factor principles.

### 1. Connection Pool Optimization (Factor IV: Backing Services)
- Implement a custom `http.Transport` for the Forgejo client.
- Expose `MaxIdleConnsPerHost` and `MaxConnsPerHost` as configurable parameters.
- Default to sane "production-grade" values (e.g., 100/10) to eliminate handshake storms.

### 2. Request-Scoped Observability & Telemetry (Factor XI: Logs)
- **Structured Span Logging:** JSON-formatted event streams to stdout/stderr.
- **Adaptive Trace ID Propagation:** Support IDs from upstream headers (e.g., `X-Request-ID`) or generate unique internal IDs to enable cross-service correlation.
- **Saturation Telemetry:** Emit sanitized resource-state events (e.g., connection pool utilization, goroutine pressure) to allow external monitoring tools (Vector, Prometheus) to trigger proactive horizontal scaling.

#### Request ID Flow Diagram:
```text
       [ CLIENT A ]          [ CLIENT B ]
     (Black Box MCP)       (Managed Proxy)
            |                     |
     [ NO TRACE ID ]       [ X-REQUEST-ID ]
            |                     |
            v                     v
    +---------------------------------------+
    |           FORGEJO-MCP SERVER          |
    |                                       |
    | 1. Detect ID? (No) -> Generate UUID   |
    |    Detect ID? (Yes)-> Adopt X-Req-ID  |
    |                                       |
    | 2. Bind ID to Context (TraceContext)  |
    |                                       |
    | 3. Structured Event Logging:          |
    |    [ID] Tool Execution Start          |
    |    [ID] Saturation: Pool 8/10         |
    +-------------------|-------------------+
                        |
            [ X-CORRELATION-ID ]
            (Propagated Header)
                        |
                        v
               [ FORGEJO API ]
           (Backing Service Logs)
```

### 3. Edge-Awareness & Multi-Layer Auth
The service supports two primary authentication and deployment postures:
- **Direct Access (Single-Layer):** Standard PAT-based authentication.
- **Shielded Gateway (Internal Multi-Layer Auth):** Optional OAuth2/OIDC Bearer token validation at the entry point (Identity), combined with user-provided Forgejo PATs for API execution (Authorization).
- **XFF Support:** Proper handling of `X-Forwarded-For` for audit logs and edge-based rate limiting.

### 4. Instance Governance & SSRF Protection
The service will implement a pluggable Target Policy:
- **Pinned Policy (Default):** Hard-locked to the startup `FORGEJO_URL`.
- **Whitelisted Policy:** Allows dynamic targets matching trusted domains.
- **Discovery Policy (Public Gateway):** Allows arbitrary `X-Forgejo-URL` with strict egress filtering (blocking internal/link-local IP ranges).

### 5. Resource-Aware Health Monitoring (Factor IX: Disposability)
- **Liveness (`/healthz`):** Lightweight process heartbeat.
- **Readiness (`/readyz`):** Reports readiness based on internal saturation limits. Signals `503` when hard limits are reached to trigger reactive orchestrator scaling.
- **Graceful Drain:** Upon `SIGTERM`, immediately signal unreadiness while completing in-flight requests.

### 6. Configuration Evolution (Factor III: Config) & Statelessness
- **Hybrid Configuration Model:** The service will adopt a hierarchical configuration model (supporting Flags -> Environment Variables -> YAML Config File). This ensures ease of use for containerized environments while providing structured management for "Bare Metal" deployments.
- Maintain strict statelessness (Factor VI); all identity and tracing state is request-bound.

## Consequences
- **Pros:** Dramatically improved throughput; proactive/reactive scaling support; "Defense in Depth" for multi-user instances.
- **Cons:** Increased complexity in the transport and middleware layers; requires 12-factor infrastructure for full observability benefits.
