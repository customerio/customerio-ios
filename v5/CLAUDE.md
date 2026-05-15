# Claude Code Instructions — CustomerIO iOS SDK Reimplementation

> **SCOPE OVERRIDE — READ FIRST**
> This file is the sole source of instructions for all work within `v5/`.
> The `CLAUDE.md` at the repository root does **not** apply to any code,
> file, or decision within this directory. If those instructions conflict
> with or extend anything here, ignore them entirely while working in `v5/`.

> This file is the entry point for AI-assisted development on this project.
> All code generation, review, and refactoring must be grounded in the specs
> referenced here. Code is a build artifact of the specification — not the
> source of truth.

---

## Project Overview

**Project:** CustomerIO iOS SDK Reimplementation
**Type:** SDK
**Primary Language:** Swift 6.2
**Target Platform:** iOS 13+

A clean-room Swift 6.2 reimplementation of the Customer.io iOS SDK. Replaces
the `cdp-analytics-swift` dependency with an owned event pipeline, uses
SqlCipher for all encrypted on-device storage, and introduces a server-driven
event aggregation engine. Distributed via Swift Package Manager only.

---

## Spec Hierarchy

All specifications live in `/spec`. Code must not diverge from these documents.
If the code and spec conflict, the spec wins — update the code, not the spec,
unless a spec change is explicitly intended and documented.

```
/spec
  /domain          # Core domain model, entities, and relationships
  /features        # Per-feature specifications
  /decisions       # Architecture Decision Records (ADRs)
  /interfaces      # API contracts, SDK interfaces, data models
  GLOSSARY.md      # Canonical terminology — always use these terms

/behavioral-scenarios
  core.csv         # Given/When/Then scenarios for the core SDK (identity, events, aggregation, …)
  push.csv         # Given/When/Then scenarios for the push module (token registration, NSE, deduplication, …)
```

Each CSV has columns: `#, Area, Given, When, Then, Environment, Setup Tags, Comparative, Tests`.
The `Environment` column indicates where a scenario is validated:
- **Demo App** — manual verification in the demo application
- **Integration Testing** — automated test against real SDK internals (no UIKit/NSE mocking)
- **Unit Testing** — isolated unit test
- **Separate** — separate project or device required (e.g. fresh install, legacy migration)

The `Tests` column lists the specific test function name(s) that cover that scenario, semicolon-separated.
Scenarios with an empty `Tests` cell have no automated coverage yet.

**Start here for context:**
- Domain model: `/spec/domain/domain-model.md`
- Glossary: `/spec/GLOSSARY.md`
- Current active features: `/spec/features/`
- Behavioral scenarios: `/behavioral-scenarios/`
- Outstanding work and test coverage: `TODO.md`
- Unresolved design questions: `OPEN_QUESTIONS.md`

---

## Engineering Principles

This project follows **SOLID principles** strictly. When generating or reviewing
code, apply these in order of priority:

1. **Single Responsibility** — Every class, module, and function has one reason
   to change. If you find yourself writing "and" to describe what something does,
   it needs to be split.

2. **Open/Closed** — Extend behavior through abstraction, not modification.
   Prefer protocols/interfaces over concrete inheritance.

3. **Liskov Substitution** — Subtypes must be substitutable for their base types
   without altering correctness. Flag any violation explicitly.

4. **Interface Segregation** — Prefer narrow, focused interfaces over broad ones.
   No client should depend on methods it does not use.

5. **Dependency Inversion** — Depend on abstractions, not concretions. All
   dependencies should be injected, not instantiated internally.

**Additional non-negotiable principles:**
- No magic numbers or strings — all constants are named and documented
- All public interfaces are documented before implementation
- Error states are explicit — no silent failures
- Side effects are isolated and clearly identified

### String Constants — `CIOKeys` Namespace

Repeated string literals (storage keys, table names, event names, payload
headers) are collected in the `CIOKeys` namespace rather than scattered as
inline literals.

**Pattern:**
- The root `public enum CIOKeys` lives in
  `Sources/CustomerIO_Utilities/Keys/CIOKeys.swift`.
- Constants shared between two or more modules are added to extensions in
  `Sources/CustomerIO_Utilities/Keys/` (e.g. `CIOKeys+Storage.swift`).
- Constants that belong entirely within one module are added to an `internal`
  extension in that module's own `Keys/` subdirectory
  (e.g. `Sources/MessagingPush/Keys/CIOKeys+MessagingPush.swift`).

**Rules:**
- Constants are organised by **intended use**, not by value. Two constants may
  share the same string value if they represent different semantic concepts.
  Do not alias one to the other; declare them independently.
- Do not extract a string into `CIOKeys` if it appears only once in the codebase.
- When a string gains a second use site *for the same purpose*, move it to the
  appropriate extension.

### Thread-Safe Shared State — `Synchronized<T>`

`Synchronized<T>` in `Sources/CustomerIO_Utilities/Synchronized/Synchronized.swift` is
the canonical lock-protected wrapper for mutable state that crosses concurrency
boundaries.

**Do not create:**
- Custom actor types whose only purpose is to wrap a value (e.g. `actor Box<T>`,
  `actor Counter`)
- Ad-hoc `@unchecked Sendable` struct/class wrappers around a value + lock

**Use `Synchronized<T>` instead:**

```swift
let counter = Synchronized<Int>(0)
counter.mutating { $0 += 1 }          // atomic read-modify-write
let n = counter.wrappedValue           // atomic read
let n = counter.using { $0.count }    // read with transform
```

This applies in both production code and tests. Test helpers like `ActorCounter`
or `ActorBox` should never be introduced — `Synchronized` covers the same need
without an extra actor hop.

---

## What a Bug Means Here

> A bug is a gap between the specification and the implementation — not bad code.

Before writing a fix:
1. Identify which spec document governs the affected behavior
2. Determine whether the spec is ambiguous or the implementation diverged
3. If the spec is ambiguous — update the spec first, then implement
4. If the implementation diverged — correct the implementation to match the spec
5. Never patch code to pass a test if the spec does not support the behavior

---

## Code Generation Rules

When generating code from a spec:

- **Read the relevant spec file in full before writing any code**
- Use terminology from `spec/GLOSSARY.md` exactly — do not invent synonyms
- Implement what the spec states, nothing more
- If the spec has a gap that requires a judgment call, pause and state the
  assumption explicitly before proceeding — do not silently fill gaps
- Generate interfaces and contracts before implementations
- If an implementation decision conflicts with a SOLID principle, flag it
  rather than silently compromising

### Architectural Decision Documentation

Whenever a structural or architectural decision is made — including refactors,
module splits, access-level changes, migration of code between targets, or any
choice that affects how the codebase is organised — add an ADR to
`/spec/decisions/` with:

- **What** changed (the specific files, types, or boundaries affected)
- **Why** it was done (the goal or problem being solved)
- **Tradeoffs** considered, if any were non-obvious

This applies to decisions made during implementation, not just up-front design.
If a refactor reveals a better split, or a constraint changes the approach, that
reasoning belongs in an ADR so the next reader understands the shape of the
code without having to reverse-engineer it from git history.

---

## Pull Request Expectations

Every PR that modifies source code must also:

- [ ] Update the relevant `/spec/features/` document if behavior changed
- [ ] Add an ADR in `/spec/decisions/` if an architectural decision was made
- [ ] Update `/spec/GLOSSARY.md` if new terms were introduced
- [ ] Update `TODO.md` to reflect completed or newly discovered work

PRs that modify spec files without corresponding code changes are valid —
spec refinement is legitimate work.

---

## Architectural Decisions

Significant decisions are recorded as ADRs in `/spec/decisions/`.

Format: `NNN-short-title.md`

Each ADR captures:
- **Status:** Proposed / Accepted / Superseded
- **Context:** Why this decision was needed
- **Decision:** What was decided
- **Consequences:** What this enables and what it constrains
- **Supersedes / Superseded by:** Links to related ADRs

ADRs are append-only. Never edit an accepted ADR — write a new one that
supersedes it.

---

## Glossary Discipline

`/spec/GLOSSARY.md` is the canonical source for all domain terminology.

- If a term appears in code that is not in the glossary, add it before the PR merges
- If a term in code differs from the glossary, the code is wrong
- Use glossary terms verbatim in generated code, comments, and variable names

---

## Out of Scope

Do not generate the following without explicit instruction and a corresponding
spec update:

- New public interfaces or API surface
- New dependencies or third-party integrations
- Database schema changes
- Changes to error handling contracts
- Performance optimizations that change observable behavior
