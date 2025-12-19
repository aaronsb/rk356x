# ADR-0000: ADR Template and Process

**Status:** Accepted

**Date:** 2025-11-14

**Deciders:** @aaronsb

## Context

This project requires a systematic way to document architectural decisions. Without explicit records, we lose the "why" behind choices - leading to repeated debates, confusion when revisiting code, and difficulty onboarding.

ADRs serve as a ledger of decisions. Like accounting entries, we don't delete past decisions - we make new entries that adjust the balance. The current architectural state is the sum of all ADRs, including supersessions.

## Decision Drivers

- Need to capture decisions as they emerge from experimentation
- Want to acknowledge learning and pivots, not pretend perfect foresight
- Require lightweight process that doesn't slow down development
- Must support "retcon" ADRs that document decisions made implicitly

## Considered Options

### Option 1: No formal process

**Description:** Document decisions ad-hoc in README files or comments.

**Pros:**
- Zero overhead
- Flexible

**Cons:**
- Decisions get lost
- No clear history of changes
- Hard to find "why" later

### Option 2: Heavy ADR process (RFC-style)

**Description:** Formal proposal, review period, voting, implementation tracking.

**Pros:**
- Thorough vetting
- Good for large teams

**Cons:**
- Too heavy for small team / rapid iteration
- Discourages documenting smaller decisions

### Option 3: Lightweight ADR ledger (selected)

**Description:** Simple markdown files with consistent structure, numbered sequentially, supporting supersession.

**Pros:**
- Low friction
- Captures the essential "why"
- Supports honest documentation of pivots
- Git-tracked alongside code

**Cons:**
- Requires discipline to maintain
- Can lag behind rapid experimentation

## Decision

We adopt a lightweight ADR process with the template defined below. ADRs are:

1. **Numbered sequentially** (0000, 0001, ...) - the number is permanent
2. **Stored in `docs/adr/`** as markdown files
3. **Named descriptively** (`NNNN-short-description.md`)
4. **Immutable once accepted** - changes come via new ADRs that supersede

### Template

```markdown
# ADR-NNNN: [Title]

**Status:** Proposed | Accepted | Deprecated | Superseded by ADR-XXXX

**Date:** YYYY-MM-DD

**Deciders:** [List of people involved]

**Technical Story:** [Link to GitHub issue/PR if applicable]

## Context

[Describe the situation requiring a decision. What forces are at play?]

## Decision Drivers

- [Driver 1]
- [Driver 2]
- [Driver 3]

## Considered Options

### Option 1: [Name]

**Description:** [Brief description]

**Pros:**
- [Pro 1]
- [Pro 2]

**Cons:**
- [Con 1]
- [Con 2]

### Option 2: [Name]

[Same structure...]

## Decision

[State the decision and rationale]

## Consequences

### Positive
- [Consequence 1]
- [Consequence 2]

### Negative
- [Consequence 1]
- [Consequence 2]

### Neutral
- [Consequence 1]

## Implementation Notes

[Optional: Migration path, key steps, gotchas]

## References

- [Link 1]
- [Link 2]
```

## Consequences

### Positive

- Decisions are discoverable and searchable
- New team members can understand historical context
- Pivots are documented honestly, not hidden
- Low-friction process encourages adoption

### Negative

- Requires discipline to write ADRs
- Can lag during intense experimentation (acceptable - retcon later)

### Neutral

- ADR numbers are permanent even if superseded
- Old ADRs remain in repo as historical record

## Implementation Notes

- ADRs can be written retroactively ("retcon") when decisions emerged from experimentation
- The index in `docs/adr/README.md` should list all ADRs with current status
- Reference ADR numbers in commit messages and PRs when implementing

## References

- [ADR GitHub organization](https://adr.github.io/)
- [Documenting Architecture Decisions - Michael Nygard](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions)
