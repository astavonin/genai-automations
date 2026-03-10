# Architecture Diagram Examples

## Component Diagram

Shows system structure and service relationships.

```mermaid
graph TD
    A[Client] --> B[API Gateway]
    B --> C[Service 1]
    B --> D[Service 2]
    C --> E[Database]
    D --> E
```

## Sequence Diagram

Documents interaction flows and timing between components.

```mermaid
sequenceDiagram
    Client->>API: Request
    API->>Service: Process
    Service->>DB: Query
    DB-->>Service: Result
    Service-->>API: Response
    API-->>Client: Result
```

## State Diagram

Documents state machines and valid transitions.

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Processing: Start
    Processing --> Success: Complete
    Processing --> Failed: Error
    Success --> [*]
    Failed --> Retry
    Retry --> Processing
```

## Architecture Diagram (C4-style)

Shows system context with external actors.

```mermaid
graph TB
    subgraph System
        API[API Service]
        Worker[Background Worker]
        Cache[(Redis Cache)]
        DB[(PostgreSQL)]
    end
    User([User]) --> API
    API --> Cache
    API --> DB
    API --> Worker
    Worker --> DB
    External([External API]) --> Worker
```

## Tips

- Keep diagrams focused — split large systems into multiple views
- Use consistent naming across all diagrams in a document
- Add notes for non-obvious relationships
- Prefer architecture/sequence/state diagrams; fall back to flowcharts when needed
