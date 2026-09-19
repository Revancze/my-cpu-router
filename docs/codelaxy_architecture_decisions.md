# Codelaxy — Architecture Decision Note

Date: 2026-09-19

This note records the agreed architectural decisions so they are not left only in conversational context.

## Core direction

The revised Codelaxy roadmap is accepted as the working architectural direction.

Hard boundary:

> Codelaxy is not a build system.

Codelaxy core remains provider-agnostic. It observes, identifies, requires, records, invalidates, proves, explains, safely reuses Evidence, and produces Verdicts. Providers decide how fresh proof is produced.

## Decisions that must be fixed already during M0/M1

### 1. Contract details — decide the minimum now

M0/M1 must already freeze the meaning and minimum identity rules of:

- Snapshot
- Requirement
- Evidence
- Verdict

Do not implement all future fields or provider machinery now.

Required architectural meaning:

- Snapshot identifies the exact state being judged.
- Requirement states what must be proven, never how work must be performed.
- Evidence must be bound to exact relevant identity and provenance.
- Verdict applies to one exact Snapshot.

Full provider/evidence behavior belongs to later milestones.

### 2. Staged isolation — establish the law now

Architectural invariant:

> Evidence for a staged Snapshot must not be issued for different content than that staged Snapshot.

M1 must be able to identify the staged Snapshot deterministically.

The final execution-isolation mechanism is deferred to later milestones, especially M3/M5. Possible mechanisms may include a materialized staged tree, temporary worktree, sandbox, archive, or another method that proves the provider verified the exact staged state.

Do not prematurely choose the final mechanism in M1.

### 3. Provider trust model — define the boundary now

Evidence must never be equivalent to an unauthenticated bare `PASS`.

At architecture level, Evidence must have enough provenance to establish who/what produced it and under which relevant identity.

The contract must be able to represent, where relevant:

- provider identity;
- provider version;
- provider configuration identity;
- external tool/toolchain identity;
- invocation/result provenance;
- integrity state;
- provider-supplied opaque context/model fingerprint.

Full provider trust and Evidence validation implementation belongs mainly to M2/M3.

### 4. Entity identity — define stability rules now

Actual Entity machinery belongs to M2.

But the identity rule must be established before then:

> Entity identity must be stable within a provider namespace and must not be an arbitrary UI/order number.

The provider owns provider-specific semantics. Codelaxy core only handles generic Entity identity, relationships, provenance, Requirements, Evidence, invalidation, and explainability.

Rename/reconfiguration/lifecycle semantics must later be explicit rather than inferred from unstable numbering.

## Milestone boundary

M0/M1:

- freeze meanings;
- freeze identity rules;
- freeze safety invariants;
- keep core provider-agnostic;
- implement deterministic read-only Snapshot truth.

M2/M3+:

- implement provider interfaces;
- implement Entity/impact Evidence;
- implement provider provenance/trust details;
- implement Evidence persistence and safe reuse.

M5:

- complete exact staged verification isolation and final staged Verdict behavior.

## Guiding rule

Build the foundations now, not the whole building.

Do not push full provider, Entity, or Evidence execution machinery into M1, but do not leave their fundamental contracts vague enough that M2/M3 would require redesigning the core.
