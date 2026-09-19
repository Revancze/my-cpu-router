# Codelaxy Tooling Engine Roadmap — Revised Draft

> Status: working revised roadmap
>
> This document revises the original `docs/tooling-engine-roadmap.md` around one hard architectural boundary:
>
> **Codelaxy is not a build system.**
>
> Codelaxy observes, decides, records, proves, explains, invalidates, and safely reuses evidence.
> It may request work from external providers, but it does not implement build, link, test, formatting,
> dependency-resolution, or other provider semantics itself.

---

## 1. Purpose

The Codelaxy Git tools have grown beyond independent shell helpers.

The purpose of this roadmap is to reconstruct them gradually into a shared evidence-driven engine while preserving:

- current public commands;
- strict separation of authority;
- deterministic reasoning over repository and workspace state;
- safe reuse of previously obtained evidence;
- conservative fallback whenever certainty is insufficient;
- compatibility with Windows through Git Bash and with Linux;
- a stable `main` branch delivered through reviewable pull requests.

Codelaxy must not become a replacement for CMake, Ninja, Make, Bazel, CTest, clang-format, linters, compilers, linkers, or test frameworks.

Those tools remain responsible for performing their own work.

Codelaxy is responsible for knowing:

- what exact state is being judged;
- what evidence is required;
- what evidence already exists;
- whether that evidence is still valid;
- what evidence has become invalid;
- what evidence is missing;
- why a result was reused or had to be obtained again;
- whether an exact staged snapshot may be committed.

---

# 2. Architectural law

## 2.1 Codelaxy is not a build system

This is a hard architectural constraint.

Codelaxy may:

- observe repository state;
- fingerprint exact state;
- model generic entities;
- consume provider assertions about impact;
- invalidate evidence;
- define evidence requirements;
- request evidence from providers;
- validate returned evidence;
- persist evidence;
- safely reuse evidence;
- explain every reuse and invalidation decision;
- produce a verdict for one exact snapshot.

Codelaxy must not:

- define build recipes;
- own compile commands;
- own link commands;
- implement a build scheduler;
- implement a build dependency planner;
- decide how a CMake target is built;
- decide how Bazel should execute a target;
- decide how a compiler should compile;
- decide how a linker should link;
- implement test-framework semantics;
- implement formatter semantics;
- duplicate provider-specific dependency logic in core.

A provider may decide that obtaining fresh evidence requires:

- a build;
- a link;
- a test run;
- a formatter check;
- a linter;
- some other external action.

That decision belongs to the provider and its external tool.

Codelaxy only knows:

> A required proof is currently satisfied, reusable, invalid, missing, incomplete, or otherwise unusable.

---

## 2.2 Requirements describe what must be proven, not how

A `Requirement` says:

> "For this exact snapshot and decision, this evidence must exist and be valid."

A Requirement must never prescribe:

> "Compile A, link B, then run C."

The first form belongs to Codelaxy.

The second form belongs to a build/test/analysis provider.

---

## 2.3 Evidence before optimization

Codelaxy does not "skip work" as its primary concept.

Codelaxy either:

- reuses already valid evidence;
- obtains fresh evidence;
- determines that a requirement is not applicable;
- or refuses to produce a successful verdict.

Preferred language:

- `REUSED`
- `EXECUTED`
- `NOT_REQUIRED`
- `FAILED`
- `UNKNOWN`
- `INVALID`
- `INCOMPLETE`

Avoid framing core behavior as "skip" when the real meaning is evidence reuse.

---

## 2.4 Paranoid default

Codelaxy uses a conservative safety model.

The rule is:

> **If validity cannot be proven, reuse is forbidden.**

Missing, unknown, malformed, stale, incomplete, corrupt, conflicting, unverifiable, or integrity-violating evidence must never satisfy a Requirement.

Uncertainty may only preserve or expand required verification.

It must never reduce it.

Formally:

```text
more uncertainty
never =>
less verification
```

---

## 2.5 Timestamp is not proof

Timestamps may be observed for diagnostics or optimization hints.

They must never establish:

- identity;
- semantic equivalence;
- evidence validity;
- evidence reuse eligibility;
- dependency validity.

Content/state identity must be proven by appropriate fingerprints and evidence.

---

# 3. Tooling constitution

These are architectural constraints, not implementation suggestions.

1. Every real project change is versioned.
2. One logical change is one logical commit with a meaningful prefix such as:
   - `feat`
   - `fix`
   - `refactor`
   - `test`
   - `docs`
   - `chore`
   - `style`
3. `main` remains clean and stable.
4. Development happens on dedicated branches and reaches `main` through pull requests.
5. Work starts by observing the real repository state with StatusMan.
6. Disk, Git, external tools, providers, and their verifiable output are sources of truth.
7. Build, test, formatting, and verification claims require readable evidence.
8. A warning is not a clean result where warnings are defined as failure by policy.
9. New behavior receives focused tests where practical.
10. Fixed regressions receive regression tests.
11. StatusMan shows the exact intended change before commit.
12. Files are staged explicitly.
13. Broad staging is allowed only after its exact contents are known.
14. MrProper never stages files.
15. A staged file changed by MrProper must be explicitly staged again.
16. Doorman is the final gate for one exact staged snapshot.
17. StatusMan is read-only.
18. StatusMan never repairs, stages, switches branches, fetches, pulls, or otherwise changes repository state.
19. IronMan obtains and validates verification evidence but does not own provider semantics.
20. Doorman never forges IronMan evidence.
21. Force pushes, history resets, and other destructive history changes are forbidden without a specific reason and explanation.
22. Loss of Codelaxy evidence may cost time, but must never require rewriting Git history.
23. Every reuse decision must be explainable.
24. Every evidence invalidation must be explainable.
25. Codelaxy must never silently convert uncertainty into success.
26. New features must preserve provider boundaries.
27. If a proposed feature teaches Codelaxy how to build, link, test, format, or otherwise perform provider work itself, it does not belong in core.

---

# 4. Fixed responsibilities

## 4.1 StatusMan

### Owns

- read-only repository observation;
- snapshot facts;
- presentation of state;
- presentation of evidence facts;
- presentation of affected entities reported by analysis/provider evidence;
- presentation of requirements;
- presentation of reusable, missing, invalid, and incomplete evidence;
- human-readable explainability.

### Must not

- change repository state;
- repair files;
- stage files;
- switch branches;
- fetch or pull;
- produce verification evidence;
- decide commit readiness;
- implement build/test/format semantics.

---

## 4.2 MrProper

### Owns

- normalization of authorized working-tree files;
- reporting which files were inspected;
- reporting which files were modified;
- reporting normalization operations;
- reporting before/after identity;
- preserving Git index integrity.

### Must not

- stage files;
- decide commit readiness;
- forge verification evidence;
- claim semantic equivalence from timestamps;
- expand its authority because it can report its work.

---

## 4.3 IronMan

### Owns

- satisfying verification Requirements for an exact snapshot;
- checking whether valid reusable Evidence already exists;
- requesting fresh Evidence from providers where reuse is not allowed;
- validating returned Evidence;
- storing valid Evidence;
- rejecting malformed, incomplete, corrupt, unverifiable, or mismatched Evidence;
- preserving snapshot integrity;
- explaining why Evidence was reused or obtained again.

### Must not

- implement build semantics;
- implement compiler semantics;
- implement linker semantics;
- implement test-framework semantics;
- implement formatter semantics;
- implement provider-specific dependency logic in core;
- repair files;
- stage files;
- forge successful Evidence;
- assume success from missing information.

### Core definition

> **IronMan is the verification orchestrator responsible for satisfying the evidence requirements of an exact snapshot, using reusable evidence where valid and providers where fresh evidence is required.**

---

## 4.4 Doorman

### Owns

- final commit gate;
- exact staged snapshot identity;
- Requirements for commit readiness;
- obtaining verification status through IronMan;
- final Verdict for one exact staged snapshot;
- denying access if staged state changes during verification.

### Must not

- repair files;
- stage files;
- implement build/test/format semantics;
- forge IronMan results;
- substitute its own verification Evidence;
- approve a snapshot whose identity changed during verification.

---

# 5. Shared read-only analysis layer

Shared analysis may expose:

- `Snapshot`
- `Entity`
- provider assertions
- impact facts
- `Requirements`
- `Evidence`
- validity state
- explainability data

Shared analysis must not produce provider work recipes.

It may say:

```text
Entity E42 is affected.
Requirement R7 is unsatisfied.
Evidence E11 is invalid.
```

It must not say:

```text
Compile foo.cpp.
Link router.exe.
Run test_router.
```

---

# 6. Core data contracts

The revised engine uses four primary versioned records.

## 6.1 Snapshot

Immutable identity of the exact state being reasoned about.

May include identities for:

- HEAD;
- index;
- working tree;
- staged snapshot;
- relevant files/blobs;
- repository state facts.

A Snapshot identifies what is being judged.

---

## 6.2 Requirements

A versioned set of facts describing what must be proven for a particular decision.

A Requirement describes:

> **what must be proven**

It never describes:

> **how to perform the work**

Example:

```text
Requirement:
  verification evidence required for Entity E42
```

Not:

```text
Requirement:
  run cmake --build ...
  then run ctest ...
```

---

## 6.3 Evidence

An immutable, versioned record of externally performed or otherwise authorized verification.

Evidence is bound to all relevant identity needed for safe reuse.

Evidence may include:

- snapshot identity;
- relevant input identity;
- provider identity;
- provider version;
- provider configuration identity;
- external tool identity;
- toolchain identity where relevant;
- environment identity where relevant;
- provider-supplied opaque context/model fingerprint;
- evidence schema version;
- requirement/policy identity;
- integrity information;
- result;
- provenance;
- timestamps as diagnostics only.

Evidence is not merely "cache".

It is proof material used to justify decisions.

---

## 6.4 Verdict

A decision for one exact Snapshot derived from:

- Requirements;
- valid Evidence;
- integrity checks;
- policy.

A Verdict must be explainable from visible facts.

A Verdict must never depend on an undocumented hidden heuristic.

---

# 7. Entity model

Codelaxy core knows the generic concept:

```text
Entity
```

Core does not own provider-specific concepts such as:

- CMake target;
- Bazel target;
- compiler translation unit;
- linker target.

A provider may describe a generic Entity with provider-specific metadata.

Example:

```text
Entity E42
provider_type: cmake-target
provider_name: router_tests
```

Core treats it as an Entity.

It does not learn how that target is built.

---

# 8. Evidence/impact graph

Codelaxy may keep a generic evidence/impact graph.

The graph represents:

- facts;
- provenance;
- Requirements;
- Evidence;
- Entity relationships asserted by providers;
- invalidation relationships;
- snapshot relationships.

Example relationships:

```text
Provider P asserts Entity A affects Entity B.
Evidence E proves Requirement R.
Evidence E belongs to Snapshot S.
Change C invalidates Evidence E.
```

The graph may be used for:

- explainability;
- evidence invalidation;
- requirement satisfaction;
- provenance reconstruction.

The graph must never contain build actions or build recipes.

Forbidden core graph actions include:

```text
Compile
Link
Build target
Compiler invocation
Linker invocation
Build recipe
```

Hard law:

> **The Codelaxy graph represents facts, provenance, requirements and evidence — never build actions or build recipes.**

And:

> **Graph traversal may invalidate evidence or establish an unsatisfied requirement. It must never itself produce a compile, link, or build plan.**

---

# 9. Provider boundary

Providers connect Codelaxy to external tools.

Examples may include providers for:

- CMake;
- Ninja;
- Bazel;
- CTest;
- compilers;
- test frameworks;
- linters;
- formatters;
- custom project tools.

Providers may:

- inspect their external tool;
- obtain provider-specific dependency facts;
- obtain impact facts;
- produce opaque fingerprints;
- execute external verification work;
- return Evidence;
- explain provider-specific results.

Providers own provider-specific semantics.

Core does not.

If Codelaxy determines:

```text
Requirement R is unsatisfied.
```

IronMan may ask a provider:

```text
Obtain valid Evidence satisfying R.
```

The provider may internally decide:

```text
build
test
lint
format-check
other action
```

Codelaxy does not need to know the recipe.

---

# 10. Evidence storage

Persistent Evidence lives outside tracked project state.

Preferred storage is repository-local Codelaxy storage associated with the Git repository, never normal tracked source files.

Required properties:

- atomic publication;
- schema versioning;
- corruption detection;
- safe concurrent access;
- interrupted producers never publish apparently valid Evidence;
- removing the Evidence store never damages source code;
- removing the Evidence store never rewrites Git history;
- losing Evidence only causes fresh verification.

Invariant:

```text
evidence store deleted
=> reuse lost
=> fresh verification required
=> source and Git history remain untouched
```

---

# 11. Safety model

Reuse is allowed only when relevant verification identity is proven compatible.

Verification identity may include:

- exact Snapshot identity;
- relevant input identity;
- provider identity;
- provider version;
- provider configuration;
- toolchain identity;
- environment identity;
- provider-supplied opaque model/context fingerprint;
- evidence schema version;
- Requirement or policy identity;
- integrity state;
- previous result.

Not every field must be understood by core.

A provider may compress provider-specific validity information into an opaque fingerprint.

Core only needs to know:

> this fingerprint is relevant to the validity of this Evidence.

If a relevant value changes and compatibility is not explicitly proven:

```text
NO REUSE
```

Different does not automatically mean incompatible.

But:

```text
compatibility not proven
==
invalid for reuse
```

---

# 12. Fine-grained selection rule

Fine-grained reuse below trustworthy provider-reported Entity boundaries is deferred until sufficient provenance exists to prove it safe.

Codelaxy core must not invent:

- call graphs;
- method-level dependency logic;
- method-level coverage logic;
- custom static-analysis semantics

merely to avoid external work.

If a provider can produce trustworthy fine-grained Evidence later, Codelaxy may consume it.

Core must not manufacture it.

---

# 13. Historical baseline

The baseline section records the actual historical behavior from the start of reconstruction.

It does not define the final authority model.

Historical facts such as:

- `verify.sh` compiling tests;
- IronMan invoking verification scripts;
- Doorman creating staged snapshots;
- MrProper formatting files;
- the pre-commit hook delegating to Doorman;

remain valuable as baseline documentation.

They must not be misread as permanent architectural obligations.

---

# 14. Milestones

---

## M0 — Contracts and characterization

### Goal

Create a characterization and contract safety net without changing existing public behavior or expanding any tool's authority.

### Scope

- Add the tooling constitution and roadmap.
- Add black-box tests for the four existing tool boundaries.
- Define versioned:
  - `Snapshot`
  - `Requirements`
  - `Evidence`
  - `Verdict`
- Establish temporary-repository fixtures for:
  - staged;
  - unstaged;
  - untracked;
  - clean;
  - failing-verification scenarios.
- Preserve existing public commands under `tools/bin/*`.

### Characterization rules

Tests must prove not only what each tool may do, but also what it must not do.

Examples:

```text
StatusMan:
  observes only

MrProper:
  may normalize working tree
  must not stage

IronMan:
  obtains verification Evidence
  must not repair or stage

Doorman:
  judges exact staged Snapshot
  must not repair or forge Evidence
```

### Exit criteria

- role violations have automated regression tests;
- StatusMan tests prove repository state is unchanged;
- MrProper tests prove the Git index is unchanged;
- IronMan tests prove:
  - required verification is obtained through authorized providers;
  - Evidence is bound to exact relevant identity;
  - integrity violations invalidate Evidence;
- Doorman tests prove only the exact staged Snapshot is judged;
- public entry points remain compatible.

---

## M1 — Read-only snapshot engine

### Goal

Extract deterministic read-only repository observation from StatusMan without changing public behavior or granting shared code mutating authority.

### Scope

- Implement deterministic:
  - HEAD fingerprint;
  - index fingerprint;
  - working-tree fingerprint.
- Represent:
  - rename;
  - deletion;
  - conflict;
  - untracked;
  - staged;
  - unstaged states.
- Add machine-readable JSON output for internal consumers.
- Keep human StatusMan output as a renderer over the same Snapshot.
- Verify before and after StatusMan execution that observable repository state is unchanged.

### Architectural rule

There is one Snapshot truth.

Renderers consume it.

```text
Snapshot
├── machine-readable renderer
└── human renderer
```

StatusMan must not maintain a second independent interpretation of repository state.

### Exit criteria

- shell and engine observations agree on characterization fixtures;
- JSON output is stable and schema-versioned;
- no StatusMan path performs a mutating Git operation;
- StatusMan execution leaves observable repository state unchanged regardless of implementation path.

### Current project note

M1 is treated as alpha/WIP until all original and revised exit criteria are satisfied.

---

## M2 — Entity impact and dependency evidence

### Goal

Determine which Evidence may have become invalid without creating a Codelaxy-owned build dependency graph.

### M2.1 Provider-owned mapping

Codelaxy does not own explicit test-to-translation-unit mapping.

Provider-specific tools supply relevant facts.

Example:

```text
Provider assertion:
  change in Entity A affects Entity B
```

Codelaxy records:

- assertion;
- provider identity;
- provenance;
- Snapshot identity.

Core does not learn how B is built.

### M2.2 Dependency evidence

Header/compiler/build-system dependency facts are provider responsibility.

Core understands:

```text
dependency Evidence
impact assertion
Entity relationship
```

Core does not hardcode GCC, Clang, MSVC, CMake, or other dependency semantics.

Dependency Evidence must be bound to:

- exact relevant Snapshot;
- provider identity;
- provider version/configuration;
- relevant opaque provider fingerprint where needed.

### M2.3 Impact classification

Core classifies:

- affected Entity;
- invalidated Evidence;
- unsatisfied Requirement.

Core does not classify work as:

- compile;
- link;
- rebuild;
- relink.

Those are provider semantics.

### M2.4 Conservative fallback

Any change that cannot be safely explained means:

```text
impact = UNKNOWN
```

Unknown impact forbids optimistic reuse.

The affected verification set expands conservatively.

Rule:

> We do not know -> we do not trust reuse.

### M2.5 Explainability

Every impact and reuse decision must explain:

- what changed;
- which provider/assertion was used;
- which Evidence became invalid;
- why a Requirement became unsatisfied;
- why reuse remains valid where applicable.

Explainability is a correctness property.

It is not cosmetic UI.

### M2.6 Provider boundary

Provider adapters may gather dependency/impact facts from external tools.

Providers must not become a back door for moving provider-specific build logic into core.

### Exit criteria

- changing an Entity only preserves reuse where non-impact is actually proven;
- a proven relevant change invalidates all Evidence known to depend on it;
- if completeness of impact cannot be proven, invalidation expands conservatively;
- unknown dependency information causes broader verification;
- no core logic emits compile/link/build plans;
- every selected Requirement and every invalidation is explainable;
- a full verification path remains available.

---

## M3 — IronMan evidence and safe reuse

### Goal

Avoid repeating externally performed verification work when complete valid Evidence already exists for the exact verification identity.

### M3.1 Evidence persistence

Persist Evidence outside the working tree.

Use atomic publication.

A crashed or interrupted producer must never leave apparently valid Evidence.

Possible unusable states include:

- `INCOMPLETE`
- `INVALID`
- `UNKNOWN`

Only complete valid Evidence may satisfy a Requirement.

### M3.2 Exact verification identity

Evidence reuse depends on exact relevant identity.

May include:

- Snapshot;
- inputs;
- provider;
- provider version;
- provider configuration;
- toolchain;
- environment;
- Requirement/policy;
- evidence schema;
- opaque provider model/context fingerprint.

Codelaxy must not build its own build graph merely to create a fingerprint.

Providers may supply opaque fingerprints of provider-owned models.

### M3.3 Evidence states

Preferred core states:

```text
EXECUTED
REUSED
NOT_REQUIRED
FAILED
UNKNOWN
INVALID
INCOMPLETE
```

Meanings:

- `EXECUTED`:
  fresh Evidence was obtained.
- `REUSED`:
  already existing Evidence was proven valid.
- `NOT_REQUIRED`:
  policy/Requirements prove that this Evidence is not required for this Verdict.
- `FAILED`:
  requested verification failed.
- `UNKNOWN`:
  validity cannot be established.
- `INVALID`:
  Evidence is known not to apply.
- `INCOMPLETE`:
  Evidence production did not complete safely.

`UNKNOWN`, `INVALID`, and `INCOMPLETE` can never satisfy a Requirement.

### M3.4 Snapshot integrity

Evidence must actually belong to the Snapshot it claims to verify.

If verification runs against a mutable workspace, Codelaxy must protect identity and integrity.

Undeclared relevant mutation invalidates the result.

### M3.5 Explainable reuse

Every:

- `REUSED`
- `EXECUTED`
- `NOT_REQUIRED`
- failure/invalidation decision

must have deterministic human-readable and machine-readable explanation derived from the same decision object.

There must not be separate conflicting truth in CLI and machine output.

### Exit criteria

- complete valid Evidence for an exact verification identity may be reused instead of repeating external verification work;
- a proven relevant change invalidates all Evidence known to depend on it;
- if affected-set completeness cannot be proven, invalidation expands conservatively;
- provider/toolchain/configuration/environment/schema/context changes invalidate reuse unless compatibility is explicitly proven;
- missing, malformed, incomplete, corrupt, stale, unverifiable, conflicting, or integrity-violating Evidence never satisfies a Requirement;
- fresh verification or a denied result is required where Evidence is unusable;
- every reuse decision is explainable.

---

## M4 — MrProper reporting

### Goal

Make normalization observable without granting MrProper new authority.

### M4.1 Report inspected and modified files

MrProper reports through the shared protocol:

- files inspected;
- files modified;
- before identity;
- after identity.

Reporting does not grant authority to:

- stage;
- approve;
- declare commit readiness.

If MrProper reports "inspected only" but the actual fingerprint changes, that is an integrity failure.

### M4.2 Record normalization operations

Record machine-readable operation identity where possible.

Example:

```text
file: src/foo.cpp

operations:
  - trailing-whitespace-removed
  - final-newline-added
  - formatter-applied

before_fingerprint: ...
after_fingerprint: ...

provider: clang-format
provider_version: ...
provider_configuration_fingerprint: ...
```

Core records what happened.

Core does not implement formatter semantics.

If a normalization operation cannot be strongly identified, it must not produce stronger reusable Evidence than the actual proof supports.

### M4.3 Preserve Git index

Prove:

```text
index fingerprint BEFORE
==
index fingerprint AFTER
```

If not:

```text
INTEGRITY VIOLATION
```

MrProper's run must not be treated as normally completed.

### M4.4 Timestamp rule

Never transfer semantic equivalence from timestamps.

Timestamps may be diagnostics only.

### Exit criteria

- every declared modification has identifiable before/after state;
- normalization operations are reported where possible;
- no invocation changes staged blobs;
- Git index identity is proven unchanged;
- a staged file modified in working tree is reported as requiring explicit restage;
- MrProper never performs the restage itself.

---

## M5 — Doorman staged verdict

### Goal

Retain the final staged gate while permitting reuse only where sufficient valid Evidence already exists.

### M5.1 Exact staged Snapshot

Create and fingerprint the exact staged Snapshot.

Every Evidence item used for the final Verdict must apply to that exact staged Snapshot.

Unstaged content must not contaminate the staged verdict.

### M5.2 Check-provider model

Doorman owns Requirements.

Providers own checks.

For whitespace, EOF, formatting, and similar policies:

```text
Doorman:
  requires proof

Provider:
  performs check

Evidence:
  returned to Codelaxy

Doorman:
  evaluates requirement satisfaction
```

Automatic fixing remains in the normalization path, not the final gate.

Recommended authority split:

```text
FIX:
  MrProper / normalization providers

CHECK:
  Doorman Requirements + check providers
```

Doorman must not mutate the staged Snapshot.

### M5.3 IronMan for exact staged Snapshot

Doorman obtains verification status through IronMan for the exact staged Snapshot.

IronMan may:

- reuse valid Evidence;
- obtain fresh Evidence through providers.

Doorman must not synthesize IronMan Evidence.

### M5.4 Complete verification identity

Reuse is permitted only when complete relevant verification identity is proven compatible.

There is no:

> "almost the same"

for successful reuse.

### M5.5 Repository recheck before Verdict

Before granting access, Doorman rechecks the real staged identity.

If staged identity changed during verification:

```text
DENY
```

Do not attempt to patch or incrementally reinterpret the old Verdict.

### Exit criteria

- unstaged content does not influence the staged Verdict;
- Doorman always obtains verification status through IronMan;
- Doorman never forges or substitutes IronMan Evidence;
- complete valid Evidence may satisfy a Requirement without repeating external work;
- any staged identity change during verification denies access;
- final Verdict always names the exact staged Snapshot it applies to.

---

## M6 — StatusMan evidence view and hardening

### Goal

Expose Codelaxy reasoning while keeping StatusMan strictly read-only.

### M6.1 Evidence view

StatusMan displays facts produced by shared analysis and provider Evidence.

Preferred generic terminology:

- affected Entities;
- required verification;
- reusable Evidence;
- missing Evidence;
- invalid Evidence;
- incomplete Evidence.

Core uses `Entity`.

Provider-specific words such as `target` remain provider metadata.

StatusMan does not calculate a private dependency model.

### M6.2 Hardening tests

Add tests for:

- corruption;
- interruption;
- cancelled execution;
- concurrent runs;
- partial writes;
- path normalization;
- relative/absolute paths;
- `..`;
- spaces;
- Unicode;
- case-sensitivity differences;
- symlinks where supported;
- Windows Git Bash;
- Linux.

A partially published Evidence object must never look valid to another process.

### M6.3 Recovery

Document recovery that does not rewrite Git history.

Hard law:

> Loss of Codelaxy Evidence may cost time, but must never require alteration of project history or tracked source state for recovery.

Safe recovery may mean:

```text
invalidate / remove broken Evidence
+
perform fresh verification
```

### M6.4 Performance measurement

Measure at least:

```text
COLD VERIFICATION
  no reusable Evidence

REUSE PATH
  complete valid Evidence exists

PARTIAL INVALIDATION
  only provably affected Evidence is invalid
```

Performance goals must never weaken correctness rules.

Correctness > speed.

### Exit criteria

- every commit Verdict is reconstructable from persisted or directly observable facts and Evidence;
- no hidden heuristic is required to justify success;
- concurrent, crashed, cancelled, or interrupted producers cannot publish Evidence another process may mistake for complete valid Evidence;
- Windows Git Bash and Linux scenarios pass;
- cross-platform reuse is forbidden unless compatibility is proven;
- different platform + no compatibility proof = no reuse.

---

# 15. Provider-driven verification flow

Normal flow:

```text
User changes files
        ↓
Snapshot changes
        ↓
Provider/analysis Evidence determines impact
        ↓
some existing Evidence becomes INVALID
        ↓
some Requirements become UNSATISFIED
        ↓
User or Doorman invokes IronMan
        ↓
IronMan checks for valid reusable Evidence
        ↓
if reusable:
    REUSED
else:
    request provider to obtain fresh Evidence
        ↓
Provider decides how to obtain it
        ↓
CMake / Ninja / CTest / linter / formatter / other tool
        ↓
fresh Evidence
        ↓
IronMan validates and stores it
        ↓
Requirements become SATISFIED
```

Important:

Codelaxy never converts:

```text
Entity changed
```

directly into:

```text
compile
link
build
```

Instead:

```text
Entity changed
↓
Evidence invalid
↓
Requirement unsatisfied
↓
fresh Evidence required
```

The provider decides what external work is necessary.

---

# 16. User-facing mental model

## StatusMan

Question:

> "What is the state and what does Codelaxy currently know?"

Role:

```text
observe + explain
```

---

## MrProper

Question:

> "Normalize authorized working-tree content and report exactly what changed."

Role:

```text
normalize + report
```

---

## IronMan

Question:

> "Are all required verification proofs satisfied for this exact Snapshot?"

Role:

```text
reuse valid Evidence
or
obtain fresh Evidence through providers
```

---

## Doorman

Question:

> "May this exact staged Snapshot be committed?"

Role:

```text
final staged Verdict
```

---

# 17. Status terminology

Prefer these core concepts:

```text
Snapshot
Entity
Requirement
Evidence
Verdict
Provider
Assertion
Provenance
Impact
Invalidation
```

Avoid making these core concepts:

```text
Build target
Compile action
Link action
Build recipe
Build scheduler
Test recipe
Formatter recipe
```

Those belong to providers/external tools.

---

# 18. Definition of done for every pull request

1. StatusMan output before work is recorded.
2. The change solves one named milestone or defect.
3. New behavior has focused tests.
4. Regression fixes have regression tests.
5. IronMan establishes complete valid verification Evidence for the exact state being delivered.
6. No unresolved integrity failure remains.
7. StatusMan shows only intended files.
8. Intended files are staged explicitly.
9. Doorman grants access for the exact staged Snapshot.
10. The logical commit is pushed to a non-`main` branch.
11. A pull request explains:
    - behavior;
    - verification Evidence;
    - invalidation/fallback rules;
    - provider-boundary impact.
12. No change expands Codelaxy into owning:
    - build semantics;
    - link semantics;
    - compiler semantics;
    - test-framework semantics;
    - formatting semantics;
    - provider-specific dependency-resolution semantics.
13. Any new capability preserves the rule:

> Codelaxy decides what must be proven and whether valid proof already exists.
> Providers decide how fresh proof is produced.

---

# 19. Scope guard for future ideas

Every proposed feature must first answer:

## Question A

Does this feature help Codelaxy:

- observe;
- identify;
- decide;
- require;
- record;
- invalidate;
- prove;
- explain;
- safely reuse Evidence?

If yes, it may belong in core.

## Question B

Does this feature teach Codelaxy how to:

- compile;
- link;
- build;
- execute a build recipe;
- understand provider-specific build semantics;
- implement a test framework;
- implement a formatter;
- replace an existing provider?

If yes, stop.

It belongs in:

- a provider;
- an adapter;
- an external tool;
- or a separate project.

---

# 20. Final architecture summary

```text
                         EXTERNAL TOOLS

   CMake   Ninja   Bazel   CTest   compiler   linter   formatter
      \      |       |       |        |          |         /
       \     |       |       |        |          |        /
                    PROVIDERS
                        |
                 facts / Evidence
                        |
                        v

+------------------------------------------------------------+
|                         CODELAXY                           |
|                                                            |
|  Snapshot                                                  |
|  Entity                                                    |
|  Requirements                                              |
|  Evidence                                                  |
|  Provenance                                                |
|  Impact / invalidation                                     |
|  Reuse validation                                          |
|  Explainability                                            |
|  Verdict                                                   |
|                                                            |
|  NO build recipes                                          |
|  NO compile planner                                        |
|  NO link planner                                           |
|  NO build scheduler                                        |
+------------------------------------------------------------+

        |                 |                 |            |
        v                 v                 v            v

   StatusMan          MrProper          IronMan       Doorman

   observe            normalize         satisfy       final
   explain            report            evidence      staged gate
```

---

# 21. Core philosophy

The central idea of Codelaxy is not:

> "How do we avoid running tools?"

It is:

> "What exactly has already been proven, for which exact state, by which authority, and is that proof still valid?"

If valid proof exists:

```text
REUSE
```

If validity cannot be proven:

```text
VERIFY AGAIN
```

If verification fails:

```text
NO SUCCESSFUL VERDICT
```

That is the safety model.

That is the evidence model.

And that is the boundary that prevents Codelaxy from becoming another build system.
