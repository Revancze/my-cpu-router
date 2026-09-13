# Codelaxy Tooling Engine Roadmap

## Purpose

The Codelaxy Git tools have grown beyond independent shell helpers. This
roadmap describes their gradual reconstruction into a shared engine while
preserving their current commands and their strictly separated authority.

The migration must remain usable on Windows through Git Bash and on Linux.
Every milestone must leave `main` stable and must be delivered through a
reviewable pull request.

## Tooling constitution

These rules are architectural constraints, not implementation suggestions.

1. Every real project change is versioned. One logical change is one logical
   commit with a meaningful `feat`, `fix`, `refactor`, `test`, `docs`, `chore`,
   or `style` prefix.
2. `main` remains clean and stable. Development happens on dedicated branches
   and reaches `main` through pull requests.
3. Work starts by observing the real repository state with StatusMan. Disk,
   Git, the compiler, and tests are the sources of truth.
4. Build, test, and Git claims require readable command output.
5. A warning is not a clean build. C++ compilation uses at least `-Wall`,
   `-Wextra`, and `-Wpedantic`.
6. IronMan passes before a commit. New behavior receives a focused test where
   practical, and a fixed regression receives a regression test.
7. StatusMan shows the exact intended change before commit.
8. Files are staged explicitly. Broad staging is allowed only after its exact
   contents are known.
9. MrProper never stages files. A staged file changed by MrProper must be
   explicitly staged again.
10. Doorman is the final gate. It checks staged content, whitespace, final
    newlines, and formatting, creates a staged snapshot, and invokes IronMan
    against that snapshot.
11. StatusMan is read-only. It never repairs, stages, switches branches,
    fetches, pulls, or otherwise changes the repository.
12. A bug found before the first proper feature commit is fixed in that
    commit. A bug found after commit receives its own `fix:` commit. Amend is
    reserved for a suitable local, unpushed mistake.
13. Force pushes, history resets, and other destructive history changes are
    forbidden without a specific reason and an explanation of their effects.
14. The complete path is implementation, verification, exact inspection,
    explicit staging, Doorman, commit, push, and pull request.

## Fixed responsibilities

| Tool | Owns | Must not do |
|---|---|---|
| StatusMan | Observe Git and report facts | Change the repository or contact the remote |
| MrProper | Normalize changed working-tree files | Stage files or decide commit readiness |
| IronMan | Build, test, and verify integrity | Repair source files or stage them |
| Doorman | Decide whether staged changes may be committed | Repair files or bypass IronMan |

StatusMan is called first, but being first does not make it a mutating
orchestrator. Each other tool obtains an observation or plan from the shared
read-only analysis layer and remains responsible for its own authorized work.

## Baseline at the start of reconstruction

The baseline was inspected on `main` at commit `b7f4c7f`.

- StatusMan reports a clean synchronized tree with score 100.
- `tools/statusman.sh` contains about 2,000 lines and combines Git collection,
  analysis, file inspection, and terminal rendering.
- `tools/verify.sh` discovers every `*_test.cpp` and compiles every test with
  every project `.cpp` except `main.cpp`.
- `tools/ironman.sh` always invokes the complete verification script.
- `tools/doorman.sh` creates a staged snapshot and always invokes IronMan in
  that snapshot.
- `tools/mrproper.sh` formats changed C++ files and delegates text cleanup to
  `tools/mrproper.py`; it does not stage changes.
- The pre-commit hook delegates to Doorman.
- There is no project build-system description or explicit dependency map.

The baseline verification also demonstrates the coupling problem: an
unrelated test can fail to build because `verify.sh` attaches `route_io.cpp`
and therefore its `nlohmann/json.hpp` dependency to every test binary.

## Target architecture

The public commands and their presentation remain stable. Shell launchers
become small compatibility entry points over shared Python modules.

```text
tools/
├── bin/
│   ├── statusman
│   ├── mrproper
│   ├── ironman
│   └── doorman
├── codelaxy/
│   ├── contracts.py
│   ├── git_snapshot.py
│   ├── dependency_graph.py
│   ├── impact.py
│   ├── evidence.py
│   └── protocol.py
└── existing shell entry points
```

The engine exchanges four versioned records:

| Record | Meaning |
|---|---|
| `Snapshot` | Immutable identity and observed Git state |
| `Plan` | Required normalization, build, and test work |
| `Receipt` | Work actually executed or safely reused by a tool |
| `Verdict` | Commit readiness for one exact staged snapshot |

StatusMan may read and display evidence, but it never writes it. Evidence is
written only by the tool that performed the work. Cached state lives below the
repository Git directory, never in tracked files or the working tree.

## Safety model

A timestamp is diagnostic information, not proof. Reuse is allowed only when
all relevant fingerprints still match:

- exact input files or staged blobs;
- dependency graph and test mapping;
- compiler identity and compiler flags;
- build configuration;
- tool and evidence schema versions.

Missing, unknown, stale, or corrupt dependency information always expands the
work. It must never cause a required build or test to be skipped.

Method-level test selection is deliberately deferred. The first safe engine
works at file, translation-unit, target, and test level. Method-level reuse
requires trustworthy call and coverage data and retains a conservative
fallback.

## Milestones

### M0 - Contracts and characterization

Goal: create a safety net without changing visible tool behavior.

- Add this constitution and roadmap.
- Add black-box tests for the four existing tool boundaries.
- Define versioned `Snapshot`, `Plan`, `Receipt`, and `Verdict` data contracts.
- Establish temporary-repository fixtures for staged, unstaged, untracked,
  clean, and failing-test scenarios.
- Preserve the existing `tools/bin/*` commands.

Exit criteria:

- role violations have automated regression tests;
- StatusMan tests prove that Git state is unchanged;
- MrProper tests prove that the index is unchanged;
- IronMan tests prove build/test execution and integrity detection;
- Doorman tests prove that only the staged snapshot is judged.

### M1 - Read-only snapshot engine

Goal: extract Git observation from StatusMan without changing its output.

- Implement deterministic HEAD, index, and working-tree fingerprints.
- Represent rename, deletion, conflict, untracked, staged, and unstaged states.
- Add a machine-readable JSON mode for internal consumers.
- Keep the human StatusMan display as a renderer over the same snapshot.
- Verify before and after every StatusMan run that repository state is
  byte-for-byte equivalent from Git's perspective.

Exit criteria:

- shell and engine observations agree on characterization fixtures;
- JSON output is stable and schema-versioned;
- no StatusMan path performs a mutating Git command.

### M2 - File and target dependency graph

Goal: stop compiling unrelated source files into every test.

- Introduce an explicit initial mapping from tests to production translation
  units.
- Record header dependencies with compiler dependency output where available.
- Separate compile, link, and test impact.
- Treat build scripts, compiler flags, and unknown files conservatively.
- Print why every selected or skipped test was classified that way.

Exit criteria:

- changing a shell script does not rebuild unrelated C++ targets;
- changing a `.cpp` rebuilds its translation unit and affected link targets;
- changing a public header rebuilds transitive consumers;
- an unknown dependency triggers a safe wider verification;
- the full suite remains available through an explicit mode.

### M3 - IronMan evidence and reuse

Goal: avoid repeating verified work for identical inputs.

- Persist per-build and per-test receipts outside the working tree.
- Bind every receipt to its exact input, toolchain, flags, and graph
  fingerprints.
- Distinguish `executed`, `reused`, `skipped-not-affected`, and `failed`.
- Preserve the integrity check around every non-snapshot run.
- Make reused results visible in terminal output.

Exit criteria:

- a second IronMan run over identical inputs executes no expensive work;
- a relevant change invalidates exactly the affected receipts;
- changed toolchain or flags invalidate build evidence;
- malformed or missing evidence causes execution, never silent success.

### M4 - MrProper reporting

Goal: make cleanup work observable without granting new authority.

- Report inspected and modified files in the shared protocol.
- Record exact normalization operations.
- Prove before and after that the Git index is unchanged.
- Never transfer semantic equivalence merely from a timestamp.

Exit criteria:

- every modification is listed;
- no invocation changes staged blobs;
- a staged file modified in the working tree is reported as requiring restage.

### M5 - Doorman staged verdict

Goal: retain the final staged gate while eliminating unnecessary repetition.

- Create and fingerprint the staged snapshot as today.
- Run whitespace, EOF, and formatting checks against that snapshot.
- Invoke IronMan for that exact snapshot.
- Allow IronMan to reuse only evidence whose complete fingerprint matches.
- Recheck the real repository state before granting access.

Exit criteria:

- unstaged content never influences the verdict;
- Doorman always invokes IronMan and never forges its result;
- valid evidence may be reused without rebuilding;
- any staged change during verification denies access.

### M6 - StatusMan evidence view and hardening

Goal: expose the engine's reasoning while keeping StatusMan read-only.

- Display affected targets, required tests, reusable evidence, and missing
  checks.
- Add corruption, interruption, concurrent-run, path, and platform tests.
- Document recovery that does not rewrite Git history.
- Measure full and incremental execution time.

Exit criteria:

- every commit verdict can be explained from visible facts;
- concurrent tools cannot publish partial evidence;
- Windows Git Bash and Linux scenarios pass.

## First implementation slice

After this roadmap, the first code change is M0 characterization infrastructure.
It must not refactor the production scripts yet. The tests first capture their
current public behavior and authority boundaries in disposable Git
repositories. Only after that safety net passes may Git collection be extracted
from StatusMan.

## Definition of done for every pull request

1. StatusMan output before work is recorded.
2. The change solves one named milestone or defect.
3. New behavior has focused tests.
4. IronMan passes with no warnings.
5. StatusMan shows only intended files.
6. Intended files are staged explicitly.
7. Doorman grants access for the staged snapshot.
8. The logical commit is pushed to a non-`main` branch.
9. A pull request explains behavior, verification evidence, and fallback rules.
