# ADR: Scaling Forgejo-MCP for Distributed Multi-User Environments

## Status
WIP (Work In Progress) - Early State Workbench

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

### 2. Request-Scoped Observability (Factor XI: Logs)
- Introduce structured span logging (JSON to stdout).
- Pass `TraceID` via `context.Context` from the transport layer down to the Forgejo SDK calls.
- **Adaptive Trace ID Propagation:** The service will adopt IDs from upstream headers (e.g., `X-Request-ID`) when present, but automatically generate unique internal IDs to ensure observability for "Black Box" clients.

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
    |    [ID] Connection Pool Checkout      |
    +-------------------|-------------------+
                        |
            [ X-CORRELATION-ID ]
            (Propagated Header)
                        |
                        v
               [ FORGEJO API ]
           (Backing Service Logs)
```

### 3. Edge-Awareness (XFF Support)
- Support `X-Forwarded-For` and `X-Real-IP` headers to ensure accurate audit logs and enable downstream rate limiting.

### 4. Configuration Evolution (Factor III: Config)
- Ensure all scaling parameters and quotas are overridable via environment variables.
- Prepare for a structured configuration model for complex multi-tenant environments.

### 5. Statelessness & Disposability (Factors VI & IX)
- Maintain strict statelessness; all authentication and tracing state is request-bound.
- Ensure graceful shutdown to drain connection pools and active requests.

## Consequences
- **Pros:** Dramatically improved throughput for concurrent users; better debuggability in production; protection against upstream service exhaustion.
- **Cons:** Increased internal complexity regarding context management; full cross-service correlation depends on upstream participation, though internal tracing remains guaranteed.
