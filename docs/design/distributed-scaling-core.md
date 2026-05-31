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
- **Adaptive Trace ID Propagation:** Support IDs from upstream headers (e.g., `X-Request-ID`) or generate unique internal IDs.

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

### 3. Edge-Awareness & Multi-Layer Auth
The service supports two primary authentication and deployment postures:

#### A. Direct Access (Single-Layer)
- Standard PAT-based authentication where the client communicates directly with the MCP server.

#### B. Shielded Gateway (Internal Multi-Layer Auth)
- **Layer 1 (Identity):** `forgejo-mcp` optionally validates an OAuth2/OIDC Bearer token at the entry point to enforce organizational access policies.
- **Layer 2 (Authorization):** The server utilizes the user-provided Forgejo PAT (passed via header or payload) to authorize specific API operations.
- **XFF Support:** Proper handling of `X-Forwarded-For` for audit logs when behind network edges.

### 4. Instance Governance & SSRF Protection
The service will implement a pluggable Target Policy to support different deployment needs:

- **Pinned Policy (Default):** Hard-locked to the startup `FORGEJO_URL`. Attempts to target other hosts are rejected.
- **Whitelisted Policy:** Allows dynamic targets matching a provided list of trusted domains (Enterprise/Federated mode).
- **Discovery Policy (Public Gateway):** Allows the client to specify an arbitrary `X-Forgejo-URL`. 
  - *Security Note:* In Discovery mode, the service must implement strict egress filtering (e.g., blocking internal/link-local IP ranges) to prevent its use as an SSRF relay.

### 5. Configuration Evolution (Factor III: Config)
- Ensure all scaling parameters and quotas are overridable via environment variables.

### 5. Statelessness & Disposability (Factors VI & IX)
- Maintain strict statelessness; all identity and tracing state is request-bound.
- Ensure graceful shutdown to drain connection pools and active requests.

## Consequences
- **Pros:** Dramatically improved throughput; better debuggability; "Defense in Depth" for multi-user instances.
- **Cons:** Increased complexity in the authentication middleware; requires client-side coordination for the two-layer credential passing.
