# Codelaxy tooling portability

This document defines the runtime boundary used by the Codelaxy command-line
tools. It records the intended architecture; a platform is verified only when
the complete gate has actually run there.

## Supported execution model

The shell layer uses Bash/POSIX paths. Tooling may also start native programs,
including Python, `g++`, test executables, and `clang-format`. On Windows these
programs do not necessarily understand paths formatted for an MSYS shell.

`tools/lib/runtime.sh` therefore owns two path representations:

- `CODELAXY_TEMP_DIR` and `TMPDIR` are shell paths;
- `CODELAXY_NATIVE_TEMP` is converted with `cygpath -m` when available;
- `codelaxy_native_exec` starts native children with `TMPDIR`, `TEMP`, and
  `TMP` all set to the native representation.

No Codelaxy script may use ambient `/tmp` for its own files. Runtime files live
below the current worktree's Git metadata:

```text
<git-dir>/codelaxy/runtime/sessions/session.XXXXXX/
├── temp/
└── snapshots/
```

Linked worktrees receive separate runtime roots because each has its own Git
directory. Session cleanup accepts only the owned `sessions/session.*` shape.

## Shell boundary

The public tools require Bash where they use Bash features such as
NUL-delimited `read`. Delegation is explicit:

```text
Doorman -> staged snapshot -> IronMan -> Verify
```

The runtime root crosses only an explicit, one-hop process boundary. This lets
a staged snapshot, which intentionally has no `.git` directory, create its own
child session without leaking the override into unrelated repositories started
by tests or other child processes. Each process cleans only its own session.

## Global launchers

Files in `tools/bin/` are checkout-independent launchers. At invocation time
they ask Git for the worktree containing the current directory and then run
that worktree's `tools/<name>.sh`. They never retain the path of the checkout
from which they were installed.

Install or refresh all four launchers with:

```bash
bash tools/install-launchers.sh
```

The default destination is `~/.local/bin`. A different directory may be given
as the only argument or through `CODELAXY_BIN_DIR`. That directory must precede
any checkout-specific `tools/bin` entry in `PATH`.

## Test repository boundary

Every tooling fixture that creates a foreign Git repository uses
`tests.git_test_support.isolated_git_environment()` for Git and tool subprocesses.
It removes Git's `rev-parse --local-env-vars` list and indexed config overrides,
while retaining PATH and native runtime settings. Variable discovery runs with
Git environment overrides removed so invalid inherited config cannot break it.
Do not copy ambient `os.environ` directly for a foreign repository.

`tooling_git_environment_test.py` runs all other tooling test modules against
hook-style `GIT_*` pointing at a disposable sentinel repository. It checks refs,
HEAD, config, index bytes, staged changes, and unstaged changes afterwards.
The sentinel is never a developer worktree. The regression discovers future
tooling test modules automatically.

## Platform status

- Linux: tooling regression tests verified in the isolated development copy.
- Windows/MSYS2 plus native MinGW tools: verified through the real commit-hook
  path, including Doorman, staged snapshot isolation, IronMan, C++ tests, and
  tooling regression tests.
- Git for Windows, WSL, and macOS: design targets, not yet verified.

This portability model belongs to the transitional Bash/Python implementation.

The standalone post-P0 C# implementation must preserve the proven repository
and runtime safety properties, but it is not required to preserve the current
MSYS/Bash process architecture.

No successful test on one platform is evidence for another platform.
