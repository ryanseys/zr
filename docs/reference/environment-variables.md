# Environment variables

## The compiler

These change what `zr` and the rake tasks do.

| Variable | Values | Effect |
|---|---|---|
| `ZR_CACHE` | a directory | Where zr keeps the compiled runtime. The default is `~/Library/Caches/zr` on macOS, `$XDG_CACHE_HOME/zr` or `~/.cache/zr` elsewhere, and `tmp/cache` in a checkout. |
| `ZR_LINK` | `auto` (default), `ruby`, `cc` | The macOS linker. `auto`: zr's own Mach-O linker, and `cc` for a link it refuses. `ruby`: zr's linker only; it names what it cannot link. `cc`: the system linker always. |
| `ZR_JOBS` | a number | How many worker processes assemble a large unit (default: one per core, at most 6). |
| `ZR_TIMING` | `1` | Prints the seconds each phase of a build takes to stderr. |
| `ZR_VERIFY` | `1` | Checks dominance and types in every IR function before it is assembled, and that every pass reported the changes it made to the kept analysis (`IR::Analysis`). |
| `ZR_YJIT` | `0` | Runs the compiler without YJIT. |
| `ZR_SELF` | `0` or `1` | Whether `exe/zr` gives `run`, `build` and `machine` to the compiler zr compiled (the cache's `self/zr`). Unset: an installed gem builds that compiler at its first build (about a minute) and gives it every build after; a checkout gives a build to it only while one is current (`rake build:self`). A build is current while no file under `exe/zr`, `lib`, `runtime` or `vendor` has changed since. `1`: build one on a miss in a checkout too. `0`: ruby runs every command. rake tasks and the checks set `0` unless it is set. |
| `ZR_GC` | `0` | Starts the compiler with ruby's own collector settings, and not with zr's. |
| `ZR_WASM_NAMES` | any value | A wasm module carries a `name` section, so wasmtime's traps and profiles name zr's functions. It changes the module's bytes. |
| `ZR_WASM_WIDTH` | a number | Past this many blocks, a wasm function dispatches to its blocks in two steps, in groups of this size (default 256). |

## Compiled programs

A binary that zr built reads these as it starts.

| Variable | Values | Effect |
|---|---|---|
| `ZR_GC_STRESS` | `1` | Collects at every allocation, and poisons freed cells, so a value the collector does not see fails at once. |
| `ZR_GC_VERIFY` | `1` | Holds every minor collection to a full trace, and names the store the write barrier missed. |
| `ZR_GC_TRACE` | `1` | Prints one line to stderr a collection: its kind and reasons, the heap, the live bytes before and after, the payload against its limit, and the marking and sweeping milliseconds. |
| `ZR_MCACHE` | `0` | Fills no call-site cache: every send looks its method up. |
| `ZR_MCACHE` | `verify` | Checks every cache hit against a fresh lookup, and stops at the first that differs. |
| `OPENSSL_DIR` | a prefix | `require "openssl"` opens `libssl.3.dylib` in its `lib` directory and looks nowhere else. |

## The tests

These change the rake test tasks.

| Variable | Values | Effect |
|---|---|---|
| `ZR_BLESS` | `1` | Writes a snapshot check's expected file again instead of comparing: HIR dumps, the disassembly listing, the eval descriptions, the libSystem list. |
| `ZR_STRESS` | `1` | Adds a `ZR_GC_STRESS=1` run to each program in `programs_test`. |
| `MT_CPU` | a number | How many workers a tier forks (default: one per core, or one per 2 GB of memory when that is fewer). Minitest's own name for this. |
| `ZR_RECYCLE_MB` | megabytes | What a worker may reside in before it is closed and forked again (default 600). |
| `N`, `X`, `A` | minitest switches | `N=/utf8/` runs the examples whose name matches, `X=` leaves some out, `A=` passes anything else to minitest. |
| `ZR_LIMIT` | seconds | The time bound for a program a check runs (default 60). |
| `ZR_RESIDENT` | megabytes | The memory bound for a program a check runs (default 2048). |
| `ZR_WASM_MEMORY` | bytes | wasmtime's `max-memory-size` in the checks (default 1 GiB). |
| `ZR_BUILT` | `0` | A test run does not ask for `rake build`'s caches: for a unit file that builds no program, while the runtime is being built for something else. A file that does build then builds the runtime cold. |
| `ZR_BINARIES` | `0` or `1` | The spec tier keeps each example's binary under the cache, named by every input of its bytes, and a later run of an unchanged example skips its build. On by default for a native target, where a kept binary is the program's own few hundred kilobytes and the runtime's are put back from the prelink; `1` keeps wasm modules too, whole; `0` keeps nothing. `rake cache:prune` sweeps them. |
| `ZR_BINARIES_GB` | gigabytes | How much the kept binaries may hold (default 8); a tier drops the ones used longest ago before it starts. |
| `ZR_WASM_COMPILER` | `winch` or `cranelift` | The wasmtime compiler the checks run a module under (default `winch`, the baseline compiler: a test wants the answer, not the speed, and Cranelift spends ten times the CPU on the same 35 MB runtime for every program). `rake bench` keeps Cranelift. |
| `ZR_BUILD_MB` | megabytes | The memory bound for a build (default 2048). A program can raise it with a `build_mb:` row in `Zr::E2E::HOW`. |
| `ZR_RUN_MB` | megabytes | The memory bound for a run (default 1024). |
| `WASMTIME` | a command | The wasmtime the checks run (default `wasmtime`). |
