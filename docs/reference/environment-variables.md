# Environment variables

## The compiler

These change what `ze0` and the rake tasks do.

| Variable | Values | Effect |
|---|---|---|
| `ZE0_CACHE` | a directory | Where ze0 keeps the compiled runtime. The default is `~/Library/Caches/ze0/rt` on macOS, `$XDG_CACHE_HOME/ze0/rt` or `~/.cache/ze0/rt` elsewhere, and `tmp/rt` in a checkout. |
| `ZE0_LINK` | `auto` (default), `ruby`, `cc` | The macOS linker. `auto`: ze0's own Mach-O linker, and `cc` for a link it refuses. `ruby`: ze0's linker only; it names what it cannot link. `cc`: the system linker always. |
| `ZE0_JOBS` | a number | How many worker processes assemble a large unit (default: one per core, at most 6). |
| `ZE0_TIMING` | `1` | Prints the seconds each phase of a build takes to stderr. |
| `ZE0_VERIFY` | `1` | Checks dominance and types in every IR function before it is assembled. |
| `ZE0_YJIT` | `0` | Runs the compiler without YJIT. |
| `ZE0_GC` | `0` | Starts the compiler with ruby's own collector settings, and not with ze0's. |
| `ZE0_WASM_WIDTH` | a number | Past this many blocks, a wasm function dispatches to its blocks in two steps, in groups of this size (default 256). |

## Compiled programs

A binary that ze0 built reads these as it starts.

| Variable | Values | Effect |
|---|---|---|
| `ZR_GC_STRESS` | `1` | Collects at every allocation, and poisons freed cells, so a value the collector does not see fails at once. |
| `ZR_MCACHE` | `0` | Fills no call-site cache: every send looks its method up. |
| `ZR_MCACHE` | `verify` | Checks every cache hit against a fresh lookup, and stops at the first that differs. |
| `OPENSSL_DIR` | a prefix | `require "openssl"` opens `libssl.3.dylib` in its `lib` directory and looks nowhere else. |

## The tests

These change the rake test tasks.

| Variable | Values | Effect |
|---|---|---|
| `ZE0_BLESS` | `1` | Writes a snapshot check's expected file again instead of comparing: HIR dumps, the disassembly listing, the eval descriptions, the libSystem list. |
| `ZE0_STRESS` | `1` | Adds a `ZR_GC_STRESS=1` run to each program in `programs_test`. |
| `MT_CPU` | a number | How many workers a tier forks (default: one per core, less two). Minitest's own name for this. |
| `ZE0_RECYCLE_MB` | megabytes | What a worker may reside in before it is closed and forked again (default 600). |
| `N`, `X`, `A` | minitest switches | `N=/utf8/` runs the examples whose name matches, `X=` leaves some out, `A=` passes anything else to minitest. |
| `ZE0_LIMIT` | seconds | The time bound for a program a check runs (default 60). |
| `ZE0_RESIDENT` | megabytes | The memory bound for a program a check runs (default 2048). |
| `ZE0_WASM_MEMORY` | bytes | wasmtime's `max-memory-size` in the checks (default 1 GiB). |
| `ZE0_BUILD_MB` | megabytes | The memory bound for a build (default 2048). A program can raise it with `#@ build-mb:`. |
| `ZE0_RUN_MB` | megabytes | The memory bound for a run (default 1024). |
| `WASMTIME` | a command | The wasmtime the checks run (default `wasmtime`). |
