# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) for the RK356X development infrastructure project.

## What is an ADR?

An Architecture Decision Record captures an important architectural decision made along with its context and consequences.

## Format

We use a simplified ADR format with the following sections:

- **Status**: Proposed | Accepted | Deprecated | Superseded
- **Context**: The issue motivating this decision
- **Decision**: The change being proposed or accepted
- **Consequences**: The resulting context after applying the decision

## Index

| ADR | Title | Status | Date |
|-----|-------|--------|------|
| [0001](./0001-build-system-selection.md) | Build System Selection: Buildroot vs Yocto/Debian | Accepted | 2025-11-14 |

## Creating a New ADR

1. Copy `template.md` to a new file: `XXXX-descriptive-title.md`
2. Fill in all sections
3. Submit for review
4. Update this index when accepted

## ADR Lifecycle

```
Proposed → Accepted → Implemented
    ↓
Deprecated / Superseded (if changed later)
```

## Numbering

ADRs are numbered sequentially starting from 0001. Use leading zeros for numbers under 1000.

## Review Process

1. Author creates ADR in "Proposed" status
2. Team reviews and discusses
3. Engineering lead approves
4. Status changes to "Accepted"
5. Implementation proceeds
6. Reference ADR number in commits/PRs

## References

- [ADR GitHub organization](https://adr.github.io/)
- [Documenting Architecture Decisions](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions)
