# ze0: a self-hosted Ruby compiler and runtime, written in Ruby

Plan file, 2026-09-08 (revised the same day: ze0 depends on nothing from zeo; ruby is the only oracle). Two repos: `~/dev/zeo` (Rust) and `~/dev/ze0` (Ruby). Built from three codebase surveys, the pinned Cranelift 0.134.3 sources, a design review pass, TenderJIT and the `aarch64` gem, and six rounds of decisions with the user.

## 1. Context

zeo compiles Ruby to native code. The Rust workspace holds 317K lines: `zeo` (front end and Cranelift emitter, 90K), `zeo-rt` (runtime, 141K), `zeo-capi` (MRI C API, 25K), `zeo-abi`, helpers. Beside it, `ze0/` is a 9,906-line Ruby front end that lowers Ruby to CLIF text plus a JSON sidecar; `zeo backend` links that against `libzeo.a`. ze0 compiles itself to a byte-identical stage-2 fixed point and matches CRuby on 5,753 of 5,944 corpus programs.

The goal: a self-hosted Ruby, as its own project. `~/dev/zeo` stays the Rust implementation; `~/dev/ze0` is the Ruby implementation, split out of `zeo/ze0/` first, and a clean new implementation from there: it links nothing from zeo, runs nothing from zeo, and holds itself to ruby's recordings alone. Compiler and runtime written in Ruby, compiled by themselves to a fixed point, producing native binaries for `aarch64-apple-darwin` and wasm modules for wasmtime, with the native code generator itself swappable between Cranelift (through a small Rust shim) and a pure-Ruby backend. User priorities, in order: (1) a working self-hosted Ruby, (2) zero non-Ruby code of our own, (3) generated-code performance, (4) backend learning. The contract is unchanged: identical to CRuby 4.0.6, or refused by name.

The brief the user supplied assumed a fresh start and left several items `[VERIFY]`. Section 2 settles them. This plan replaces the brief.

## 2. Ground truth that changes the brief

| Brief assumed | Repo or upstream fact |
|---|---|
| A Ruby front end must be written | `ze0/` exists: 9,906 lines, 141 runtime entry points, stage-2 fixed point, 5,753/5,944 matched. `lower.rb` is 7,565 lines in one class. |
| `.clif` text is the whole interface | The `.zeodata` sidecar carries rodata, symbols, call sites, `def` rows, class rows, and two words (`@all`, `@boot`) that the Rust side expands by compiling the EMPTY program through the whole Rust front end (`backend/clif_text.rs:1126`). |
| A ~200-line shim | `zeo backend` is 1,800 exclusive lines plus 11,400 shared lines (`statics.rs`, `capi_names.rs`, `module.rs`, `link.rs`, `zeo-abi`) plus, transitively, the front end. |
| Stack maps are builder-only | Cranelift 0.134.3 parses `call fn0(v1), stack_map=[i64 @ ss0+0]` in text (`cranelift-reader/src/parser.rs:2282`). Not used: the shadow stack (section 8.6) is simpler, Rust-free, and works on wasm. |
| `setjmp`/`longjmp` for exceptions | Cranelift has no `returns_twice`; a `setjmp` from generated code is unsound. The repo already uses a status-word protocol (`docs/explanation/backend.md`). |
| Conservative GC needed | ze0 already keeps every local in a stack slot. Precise roots cost nothing extra. |
| Variadic calls are a risk | Generated code never calls a variadic; every runtime entry is fixed-arity (`clif/ffi/mod.rs:12`). Keep that rule. |
| No runtime exists | `zeo-rt` is 141K lines of CRuby-identical Rust: 24-byte `Arc` values, release pools, a Bacon-Rajan cycle collector, parallel OS threads with per-object locks, `corosensei` fibers, oniguruma, num-bigint, prism. |
| `clif-util compile` as an oracle | It emits no linkable object. `clif-util` only verifies text. |
| `stack_switch` available | The CLIF `stack_switch` instruction lowers on x86-64 only (`isa/x64/lower.isle:3575`); no aarch64 lowering. |
| Compiled Ruby is fast enough for a runtime | Measured 2026-08-24: zeo-compiled Ruby rows ran 8x slower than Rust rows (Pathname bench). Cause: refcount traffic, 24-byte copies, dynamic sends. The new value model and kernel dialect remove those costs. Re-measure at C5. |
| A pure-Ruby backend is "Phase 7, optional" | The `aarch64` gem is a complete pure-Ruby ARM64 encoder with labels; TenderJIT is a working Ruby-written JIT with a three-address IR, a graph-colouring allocator and an arm64 code generator over that gem; `jit_buffer` does `mmap(MAP_JIT)` through Fiddle. The backend is a first-class seam here (Part B), missing only object-file relocations. |

Prior art the design follows: Squeak's Slang (VM in a Smalltalk subset), RPython, Jikes RVM `vmmagic` (unboxed `Address`/`Word`), CRuby's `Primitive` idiom for builtins written in Ruby (`array.rb`, `kernel.rb`), ZJIT's HIR-over-LIR layering, Go's generic-to-arch SSA rewriting, TenderJIT.

## 3. Decisions (locked with the user)

| # | Decision |
|---|---|
| D0 | **Two repos, two implementations, no dependency between them.** `~/dev/zeo` stays the Rust implementation, complete and maintained. `~/dev/ze0` is the Ruby implementation, split out first (Part 0) with its git history, self-contained: its own corpus, tests, vendored prism Ruby half, and a small Rust crate for the Cranelift shim. ze0 never links, runs or reads zeo: no runtime archive, no `zeo backend`, no ABI tables generated from zeo's sources. zeo is reading material for the port and nothing more. |
| D1 | **Scope:** compiler AND runtime in Ruby, in the ze0 repo. **ruby 4.0.6 is the only oracle**: the corpus recordings under `__END__`, and a live `ruby` where a check needs one. Nothing is compared against the Rust emitter or the Rust runtime. Until the Ruby runtime runs `puts 1` (Part C), nothing ze0 compiles links; the lowering that names `zeo_rt_*` today is a refactor scaffold held to its own text goldens, and is archived when the `zr` road passes ladder M1. |
| D2 | **Non-Ruby dependencies allowed:** prism (parser), oniguruma (regex), zlib, openssl, libffi, libSystem, `ld`, Cranelift (inside the shim, optional), wasmtime. Vendored C builds with `cc` through a Ruby script. No C or assembler source of our own. |
| D3 | **Compiler layers:** Prism → tree HIR (desugared, name-resolved, target-neutral) → one CFG-SSA IR with two op tiers (Ruby-level ops legalized per target into machine ops) → emitters. Two data structures, no third typed HIR. |
| D4 | **Native backend seam:** every backend produces a backend-neutral `Obj` (functions, data, relocations, symbols). `clif2obj` (Rust + Cranelift) and `IR::Arm64` (Ruby) are interchangeable per program and per function; both end in a Mach-O `.o` that `ld` links. A Ruby Mach-O writer and a Ruby JIT loader complete the Ruby road. Two spikes prove it early. |
| D5 | **GC:** precise, non-moving mark-sweep over a shadow stack of frame records. No conservative scan, no stack maps. |
| D6 | **Signals (exceptions, break, return, throw):** the status protocol, spelled as a `Qundef` return sentinel. |
| D7 | **Concurrency:** per Ractor one Ruby-running OS thread, one heap, one green-task scheduler, plus a pool of helper OS threads for blocking calls. No GVL. Threads are green tasks preempted at safepoints; Fibers are green tasks switched explicitly; Ractors run in parallel with independent GC. |
| D8 | **Stack switch:** a Ruby-encoded aarch64 stub, delivered as raw function bytes (`define_function_bytes` on the Cranelift road, natively on the Ruby road). No upstream change, no deprecated API. Parked-OS-thread fibers only as a debug fallback. |
| D9 | **eval:** programs that can `eval` link the compiler (native) plus a JIT loader; eval-free programs carry nothing extra. On the Cranelift road the loader is `clif2obj_jit` (Rust); on the Ruby road it is `Obj::JIT`. |
| D10 | **Targets:** `aarch64-apple-darwin` first; wasm on wasmtime second (wasm32 first, wasm64 kept open by an IR pointer-width parameter). Linux and x86-64 are non-goals with seams kept. |
| D11 | **Register allocation:** spill-everything first, linear scan second. |
| D12 | **Optimizer:** IR high-tier passes start after the bootstrap fixed point (Part F). |
| D13 | **C API (zeo-capi):** deferred to an optional last Part; the object header is RBasic-compatible so `rb_*` can be written in the kernel dialect later. |
| D14 | **Names:** `zeo` is the Rust implementation and its CLI; `ze0` is the Ruby implementation and its CLI. Runtime sources in `~/dev/ze0/rt/`, runtime symbols `zr_*`, kernel-dialect module `Machine`, environment `ZR_*`. The Rust road keeps `zeo_rt_*` untouched. |

## 4. Target architecture

```
 app.rb  ─┐                                                                   ┌─► IR::ClifText ─► clif2obj (Rust) ─► Obj ─┐
 rt/*.rb  ├─ prism ─► HIR ─► analyses ─► IR (high tier) ─► legalize ──────────┼─► IR::Arm64 (Ruby) ──────────────► Obj ─┼─► Obj::MachO ─► .o ─► ld + libzr.a ─► binary
          │                            (per target: zr | Machine)           │                                           └─► Obj::JIT (eval, in process)
          │                                                                   └─► IR::Wasm (Ruby) ─► wasm ─► wasmtime
```

After the plan, Ruby owns: parsing glue, HIR, analyses, IR, legalization, all three emitters, the object model, the Mach-O writer, the JIT loader, the link driver, the CLI, the program cache, the runtime, the class library, the extensions' native halves, the test harness. Rust owns `clif2obj` only, and it is optional once `IR::Arm64` matches it. Everything else is a dependency listed in D2. The legacy text lowering (`zeo_rt_*` names, the 24-byte value ABI) is the scaffold the IR and HIR refactors are verified on; it is archived on a branch once `zr` passes M1.

## 5. Roadmap overview

| Part | Name | Depends on | Gate | Size (new Ruby, rough) |
|---|---|---|---|---|
| 0 | Split the repos | nothing | DONE 2026-09-08: `~/dev/ze0` is its own git repo with ze0's 138 commits, the corpus, `bin/ze0 test|check|scan` in Ruby, no reference to zeo; `~/dev/zeo` builds and its gate is green with `ze0/` gone | none (moves, ~600 lines of harness) |
| A | The compiler is Ruby; the shim is small | 0 | the IR and HIR reproduce ze0's own text byte for byte on `test/ze0/` and on the self-compile; `clif2obj` turns hand-written CLIF into a Mach-O `.o` that `ld` links against libSystem and runs | 8-12K (HIR, IR, Obj, clif2obj, CLI) |
| B | The native backend in Ruby, and two spikes | A2 (IR) | B1 spike matches Cranelift on `test/ze0/`; B2 spike runs `fib` with no Rust; Part: `--native ruby` matches `--native cranelift` on the corpus | 4-6K |
| C | The runtime in Ruby | A2b (HIR), B2 | `ze0 test --all` matches the corpus in three GC columns; the first light is `puts 1` through `zr` (M0) | 60-90K (kernel + corelib + ext halves) |
| D | The wasm target | A2, C2 | ladder M1 and M2 through wasmtime; native and wasm agree byte-for-byte | 4-6K |
| E | Bootstrap to the fixed point | C, B | stage 1 == stage 2, bytes, on both emitters | small |
| F | Performance | E | benches through the Ruby road; no gate, measured | open |
| G | The C API in kernel Ruby (optional) | C | `make test-capi` sweep | 15-25K |

Part A is the foundation and is verified byte-for-byte at every step. Parts B, C, D run in parallel worktrees once their dependencies land (section 12 lists file ownership).

## 6. Parts and slices

Slices are ordered inside a Part; `∥` marks slices that can run in parallel with their neighbours. Each slice names its verification.

### Part 0: split the repos (DONE 2026-09-08)

Result: `~/dev/zeo` is the Rust implementation, `~/dev/ze0` the Ruby one, both self-contained, neither referencing the other.

- **0.1** `git subtree split -P ze0` seeded `~/dev/ze0` with ze0's 138 commits. zeo lost `ze0/`, `test/ze0/`, the `ze0_refused` fixtures, the two ze0 snapshots, the five ze0 checks, the three-road corpus test, and the `stage2` and `ze0-sweep` xtask commands (commit `51babcca7`); `zeo backend`, `--emit-clif` and `--emit-zeodata` stay as zeo's own feature.
- **0.2** ze0 carries: the corpus (`test/lang core stdlib compiler aot bench milestones gaps`, ruby-recorded; the zeo-recorded `errors`, `features`, `divergences` are not copied), `test/ze0/`, `test/refused/`, `test/snapshots/`, `lib/ze0/shims/rbconfig.rb.in`, `vendor/ext/<gem>/lib` (the Ruby halves, prism included), `docs/test-format.md`.
- **0.3** The harness in Ruby: `bin/ze0 test <filter>|--all [--show N]` (buckets `skipped refused backend matched diverged crashed timeout`; the native road is a pluggable object, `nil` today, so every compiled program is `backend: no native road yet`), `bin/ze0 check` (minitest: hygiene, refused fixtures, snapshots with `ZE0_BLESS=1`, case format, DATA offset), `bin/ze0 scan`. `lib/ze0/harness/case.rb` is the test-file format and the scrubs.
- **0.4** Scaffolding: README, `.ruby-version` 4.0.6, Gemfile (prism, minitest), `.gitignore`, CI on macOS. `measure.rb` and `PLAN.md` (the front-end-for-zeo era) are on branch `archive/zeo-front-end`.
- Dropped from the original Part 0 by the user's direction: `toolchain.rb`, `.zeo-version`, the `zeo backend` link road, `stage2` (returns when the Ruby runtime links a binary), the builtins-drift check against `zeo_abi`.

### Part A: the compiler is Ruby, the shim is small (verified on ze0's own text)

Nothing runs in this Part: the oracle for a refactor is ze0's own CLIF text, held byte for byte.

- **A1 ∥ Self-goldens.** `test/goldens/<program>.clif` for every `test/ze0/` program, recorded by ze0 itself (`ze0 check` compares; `ZE0_BLESS=1` rewrites). `ze0 stage1`: ze0 under ruby compiles `ze0.rb` (with `-I vendor/ext/prism/lib`) twice and demands the same bytes, so the self-compile stays deterministic and refusal-free with no binary in the loop. The stage-2 fixed point returns in Part E, when a binary exists.
- **A2 The IR.** Replace text accumulation in `lib/ze0/clif.rb` with `Ze0::IR` objects (section 8.2) behind the same builder API (`ins/val/vals/iconst/hoisted/block/switch`), so `lower.rb` changes little. Step 1 parses the text `ins` receives (ze0 emits about 20 opcodes); step 2 converts call sites to structured calls. Pointer width and addressable slots are IR parameters from the first commit (wasm needs both). Verify: `IR::ClifText` renders today's bytes on the goldens, the snapshots and `stage1`.
- **A2b The HIR.** `lib/ze0/hir/` (section 8.1). `Prism → HIR` absorbs the ten note passes, the declaration pass, and the sugar; `HIR → IR` replaces `lower_expr`'s hundred arms with far fewer. Move one node family at a time. Verify: byte-identical text on the goldens and `stage1` after each family; the hygiene rule (no method named for a `Kernel` method) applies to every HIR class.
- **A3 ∥ `clif2obj`.** New Rust crate `clif2obj/` in the ze0 repo (section 8.9): a few hundred lines over Cranelift 0.134.3, a binary plus a C-ABI staticlib with `clif2obj_compile` and `clif2obj_jit`; the sidecar it reads is the `Obj` model (section 8.3), never zeo's `.zeodata`. `ze0 link` runs `cc`/`ld`. Verify: a hand-written CLIF `main` that calls `write(2)` and `exit(2)` becomes a `.o`, links against libSystem alone, and prints; this is C0.1's shape, so the kernel road has its first light here.
- **A4 ∥ The CLI.** `ze0 run|build|link|test|check|scan|stage1|rt build|deps build` in `lib/ze0/cli/`: options in CRuby's order, the program cache keyed on inputs, `-I` roots, `--emit`. The old `capi.rb` table and the `zeo_rt_*` names stay until the legacy lowering is archived; nothing regenerates them.

Gate: the goldens, the snapshots and `stage1` are byte-identical through A2 and A2b; `clif2obj` links and runs the hand-written program.

### Part B: the native backend in Ruby, and two spikes

- **B0 The object model.** `lib/ze0/obj/`: `Obj`, `Obj::MachO` (relocatable writer), `Obj::JIT` (loader) per section 8.3. Verify: a hand-built `Obj` round-trips through `otool -l`, `nm` and a Ruby reader test; a `.o` from `Obj::MachO` links beside one from `clif2obj`.
- **B1 Spike 1: the Ruby backend against `clif2obj` on kernel programs.** `IR::Arm64` (spill-everything) compiles the C0 kernel-dialect programs and the hand-written CLIF of A3; `Obj::MachO` writes the `.o`; `ze0 link` links against libSystem. Mixed mode `--native ruby:<function-filter>` compiles a subset with Ruby and the rest with Cranelift through `raw_functions`, so a miscompile bisects to one function. Gate: the same bytes on stdout from both roads for every `test/zr/` program (Cranelift is a second opinion on machine code, never the oracle for Ruby semantics).
- **B2 Spike 2: pure Ruby end to end.** A micro runtime in the kernel dialect (`rt/spike/`): `zr_write`, fixnum `to_s`, `puts` for Integer and String literals, an overflow trap, `main`. A `--profile micro` lowering for `def`, locals, Integer literals and arithmetic, comparisons, `if`/`while`, calls, `puts`. Program: `def fib(n) = n < 2 ? n : fib(n - 1) + fib(n - 2); puts fib(25)`. Road: prism → HIR → IR → `IR::Arm64` → `Obj::MachO` → `ld` against libSystem only. Gate: the binary holds only our bytes and libSystem, and prints 75025. This fixes the shape of C1's `Machine` lowering early.
- **B3 Instruction selection.** Section 8.4. Verify: disassembly snapshots per IR op in `test/native/`.
- **B4 Register allocation, step 2.** Linear scan (section 8.4). Gate: byte-identical program output against step 1 on the corpus.
- **B5 ABI conformance.** Section 8.4's Apple rules as emitter assertions and as tests (a function with eight args, mixed float args, a sub-32-bit arg).
- **B6 The pure JIT road.** `--native ruby` makes `zr_eval` load through `Obj::JIT` (section 8.11). Gate: `test/lang/eval` with no Rust linked.
- **B7 Optional: no `ld`.** `Obj::Exe` writes a complete executable with an ad-hoc code signature (section 8.3). Scheduled only if the user wants zero Apple tools at build time.

Gate for the Part: `ze0 test --all --native ruby` matches the corpus wherever `--native cranelift` does; then `clif2obj` becomes optional (E3).

### Part C: the runtime in Ruby (`rt/`)

- **C0 Experiments, in order.** C0.1 kernel spike: `machine def main` calling `write(2)` and `exit(2)` through IR → both native emitters → binary. C0.2 raw-function spike: the context-switch stub, two stacks ping-ponging 1e6 times. C0.3 shadow-stack spike: allocate in a loop with a frame record; collect under `ZR_GC_STRESS=1` with `ZR_GC_VERIFY=1` (section 8.6). C0.4 wasm spike: C0.1 through `IR::Wasm` and wasmtime with `fd_write`. Each spike becomes a permanent test.
- **C1 The kernel dialect.** `lib/ze0/machine/` per section 8.5: types, signatures, intrinsics, `Machine.struct`, `Machine.import`, `defer`, the transitive effects and the rules the compiler enforces. Verify: golden IR per intrinsic; every rule has a refusal fixture.
- **C2 Object model and dispatch core.** Section 8.7 and 8.8: values, headers, shapes, classes, method tables, caches, symbols, strings (UTF-8/US-ASCII/BINARY first), arrays, hashes, ranges, procs and envs, exceptions, frames and backtraces, `puts`/`p`/`inspect`, `ruby_qsort`. The `zr` lowering (`hir/lower_zr/`) lands beside the legacy one here and takes over `ze0 test`; the legacy lowering, its goldens and `capi.rb` go to branch `archive/legacy-lowering` when M1 passes. Corpus: `puts 1` (M0), `test/ze0/`, then ladder M1.
- **C3 GC.** Section 8.6. Corpus: M1 in three columns.
- **C4 Scheduler, threads, fibers, ractors.** Section 8.10. Corpus: M5.
- **C5 The class library.** `rt/core/*.rb` in corelib mode (section 8.12), ported class by class from `crates/zeo-rt/src/builtins/` in ladder order: Kernel; Integer and Float (shortest round-trip digits, then CRuby's `flo_to_s` formatting rules including the `1e16` exponent thresholds); String and Symbol; Array; Hash; Range; Comparable, Enumerable, Enumerator (fiber-backed external iteration); Struct and Data; the Exception tree (generated from the `zeo-abi` tables); Proc, Method, UnboundMethod; Module and Class reflection; Regexp and MatchData over oniguruma via FFI (the `regexp/translate.rs` and `charrange.rs` preprocessing ported); Time (Hinnant civil algorithms, `localtime_r` for zones); IO, File, Dir, Stat, Process over libSystem; Marshal 4.8; pack and unpack; sprintf; Encoding (the 103-row registry first, byte mappings as the corpus demands, all tables generated from the oracle by Ruby scripts into `rt/enc/`); Bignum (64-bit limbs, schoolbook and Karatsuba, divide-and-conquer `to_s`); Rational and Complex; Random (MT19937); ObjectSpace; GC; Signal; Ractor; RubyVM::AbstractSyntaxTree over prism. `RUBY_ENGINE` stays `"ruby"`, `RUBY_VERSION` `"4.0.6"`. Measure the Pathname benchmark from `zeo-corelib-dropped` at the end.
- **C6 Extensions.** The 24 `crates/zeo-rt/ext/*` gems keep their Ruby halves (`ext/*/lib`); native halves move to kernel Ruby or FFI: json (parser and generator in Ruby), stringio, strscan (onig), digest (md5 and sha in the kernel dialect), zlib and openssl over vendored C via FFI, socket over libSystem, io-console, etc, fcntl, date, bigdecimal, psych (a Ruby YAML parser), ffi (libffi via FFI plus the direct `call_indirect` tier for scalar signatures), fiddle, prism. One prism source tree serves stage 0 (CRuby's extension), stage 1, and the runtime's FFI binding. Verify: the `zeo-pure-ruby-lane` matrix (one golden against CRuby's C ext, the pure tree under CRuby, the pure tree under zeo).
- **C7 Boot and the program description.** Section 8.13. `libzr.a` = kernel objects + corelib objects + the raw stub, built once by `ze0 rt build`.

Gate: `ze0 test --all` matches the corpus in three columns: plain, `ZR_GC_STRESS=1`, `ZR_GC_VERIFY=1`; the allowlist of known failures only shrinks.

### Part D: the wasm target

- **D1 `IR::Wasm`.** Section 8.14. Verify: LEB128 and structurizer unit tests over hand-written CFGs, including an irreducible one; C0.4.
- **D2 A Ruby wasm linker.** Corelib and kernel are emitted as IR modules once; a program links by function renumbering and data-segment concatenation. No `wasm-ld`.
- **D3 `sys/wasi.rb`.** WASI preview 1 imports; `memory.grow`; preemption via the poll word plus wasmtime epoch interruption. `fork`, signals, `exec`, `pty`, libffi, dlopen (so `eval`), and sockets (until WASI 0.2) refuse by name on wasm.
- **D4 Milestone 1: wasm32, single task.** No Fiber, Thread, Ractor, FFI, eval or signals. Corpus: ladder M1 and M2 minus what needs those, on stdout plus exit status.
- **D5 Milestone 2: stack switching on wasm.** An Asyncify-style unwind/rewind transform in `IR::Wasm` (section 8.14). Ractors on wasm run as green tasks in the one ractor.

Gate: M1 and M2 through wasmtime; native and wasm agree byte-for-byte on stdout and status for every program both accept.

### Part E: bootstrap to the fixed point

- **E1 Stage 0 and 1.** ze0 on CRuby compiles `rt/` to `libzr.a`, then compiles itself against it: stage 1, native, running on the new runtime.
- **E2 Stage 2.** Stage 1 recompiles `rt/` and itself. Compare every artifact (CLIF text, sidecar, `.o` from the Ruby backend, wasm); `ze0 stage2` returns here, with A1's `stage1` as its first half. Known sources of difference, each guarded: sort ties (the `ruby_qsort` port), `object_id` (a counter, never an address; ze0 keys tables by `node.object_id`), hash order (insertion; lint ze0 for ordering by `.hash`), prism version (one source tree), `RUBY_ENGINE` folding, per-file `frozen_string_literal`, `Dir.glob` order, `inspect` addresses in output, the main task's stack depth under prism's recursive visitors. Report the first differing byte and its line, as the old `stage2.rs` did.
- **E3 Cut the last tie.** When B's gate holds, `clif2obj/` becomes an optional build (`ze0 --native cranelift` refuses when it is absent) and the default is the Ruby backend. Then a ze0 checkout needs ruby, `cc`/`ld`, and the vendored C deps.

Gate: `ze0 stage2` reports byte-identical artifacts from stage 1 and stage 2 on both native emitters, and every corpus program compiled by both binaries is byte-identical.

### Part F: performance

Passes on the IR high tier: constant folding, inlining of small kernel functions and `attr_*`, fixnum type inference and guard hoisting, block escape analysis (stack-allocated envs for non-escaping blocks), fused iterator loops (`3.times`, `arr.each`, as the Rust emitter did). Register allocation step 2 if B4 has not landed. Instrument: `benches/` through the Ruby road, the Pathname 200k benchmark, `test/bench`. Perf is never a gate (`zeo-perf-not-a-gate`); every number goes in the commit message.

### Part G (optional): the C API in kernel Ruby

`rb_*` over the RBasic-compatible header, `RString`/`RArray` layouts from `Machine.struct`, `rb_protect` over the status protocol, a handle table for `VALUE`s held by C, `make test-capi` as the gate. Not scheduled.

## 7. The corpus ladder (Parts C and D)

Each rung's per-directory match rate is monotone, enforced by a committed allowlist of known failures that may only shrink.

| Rung | Corpus | Brings in |
|---|---|---|
| M0 | `test/zr/` (new: kernel-dialect programs with expected output, native and wasm); `puts 1` on the new runtime with GC on | the dialect, both emitters, boot |
| M1 | `test/ze0/` (82); `test/lang/{control,variables,methods,blocks,syntax,exceptions,constants,globals,classes,modules,singleton}` | object model, dispatch, signals, GC in three columns |
| M2 | `test/core/{kernel,object,numeric,string,array,hash,range,comparable,enumerable,struct,format,pack,regexp,encoding,time}` | corelib, oniguruma, encodings, bignum, float formatting |
| M3 | `test/core/{gc,objectspace,marshal,warning,rubyvm}`; `test/lang/{pattern,require,programs,misc,eval,refinements}` | eval road, heap enumeration, Marshal |
| M4 | `test/core/{io,process}`; pure-Ruby `test/stdlib/*` (set, ostruct, forwardable, delegate, erb, optparse, uri, pathname, csv, shellwords); then stringio, strscan, date, digest, zlib, openssl, json, yaml | IO, Process, extensions |
| M5 | `test/core/thread`; `test/stdlib/{timeout,monitor,thread,open3,pty,socket,net,webrick}`; `test/lang/boxes`; Ractor | scheduler, helper pool, ractors, boxes |
| M6 | `test/milestones` (rubygems, bundler, minitest, rspec); `test/aot`; `test/bench`; `ze0 stage2` | everything |

## 8. Designs

### 8.1 The HIR (`lib/ze0/hir/`)

Why a HIR: compilers with more than one target or an optimizer keep one language-semantics layer above the CFG IR (rustc: HIR then MIR; Swift: SIL; Go: typed AST then one SSA IR whose generic ops are rewritten to arch ops; ZJIT: an SSA HIR with a Ruby type lattice over a LIR shared by x86-64 and arm64). Crystal goes straight from a typed AST to LLVM and can, with one target. ze0 today is Crystal-shaped, and this plan adds a second runtime ABI, a kernel dialect, a wasm target and later an optimizer.

Shape: a tree, one node class per kind, desugared and name-resolved. Nodes: `Program{units, classes, defs}`, `Scope{locals, captures, cref, definee, owner, block channel}`, `Def{params, body, visibility, singleton, guard}`, `ClassBody`, `Block{params, captures, body}`, `Send{recv, name, args, splat, kw, block, site shape, caller class}`, `Yield`, `Super{explicit?, args}`, `Local{slot|cell}`, `Ivar`, `Gvar`, `Const{cref path}`, `Assign`, `If`, `While{head, exits}`, `Case`, `Match{pattern}`, `Begin{rescues, else, ensure}`, `Raise`, `Return`, `Break`, `Next`, `Redo`, `Retry`, `Defined{form}`, `Literal`, `Interp`, `MultiAssign{targets, rest}`, `Ffi{layout}`, `Eval`, `Using{slot, range}`.

Desugared away in `hir/build.rb`: op-assign and `||=`/`&&=` on every target, safe navigation, multiple assignment, string and symbol interpolation, `case/when` and `case/in`, class-body macros (`attr_*`, visibility verbs, `module_function`, `include`), the whole parameter surface into one `Params` shape, `rescue` modifiers, `for`, flip-flops, `__FILE__`/`__LINE__`/`__ENCODING__`, `defined?` forms. Analyses (`hir/analyze/*.rb`): declarations, captures, guards (`RUBY_ENGINE`/`RUBY_VERSION` folding), redefinitions, eval homes, `using` activations, FFI typedefs. The Rust `crates/zeo/src/hir/node.rs` is the vocabulary reference and `analyze/captures.rs` shows which capture facts an emitter wants. Every later consumer (the three lowerings, the kernel-dialect checker, `Primitive` resolution, the eval road's "every static decision off" mode) reads HIR, never Prism.

### 8.2 The IR (`lib/ze0/ir/`)

Exactly CLIF's model, restricted to what ze0 emits: `Function{name, sig, slots[], symbols[], sigs[], callees[], blocks[]}`, `Block{params[], insts[]}`, `Inst{op, type, args[], results[], targets, sig}`. Types `i8 i32 i64 f64` plus `ptr` (resolved per target: 64 on darwin and wasm64, 32 on wasm32). Addressable slots are first-class (`slot`, `slot_addr`); the native emitters lower them to frame areas, the wasm emitter to a linear-memory shadow-stack region.

Two op tiers in one structure. The high tier carries Ruby-level ops with their site shape: `send`, `send_super`, `yield`, `guard_fixnum`, `fixnum_add` (with an overflow edge), `ivar_get/set`, `const_get`, `gvar_get/set`, `alloc`, `frame_enter/leave`, `stack_check`, `signal_check`, `raise`. `Legalize::ZeoRt`, `Legalize::Zr` and `Legalize::Machine` rewrite each high op into machine ops and runtime calls for that target; `IR::Verify` refuses a high op that reaches an emitter. During Part A the `zeo-rt` lowering may emit the low tier directly so the byte-identity gate stays simple; the `zr` and `Machine` lowerings use the high tier from their first commit. Optimization passes (Part F) run on the high tier.

Emitters: `IR::ClifText` (today's bytes, for `clif2obj`), `IR::Arm64` (to `Obj`), `IR::Wasm`. `IR::Interp` interprets IR as an oracle (the role `clif-util interpret` plays for Cranelift). `IR::Verify` checks: every block terminated, every use dominated by its definition, types agree, no `Value`-typed SSA use across a fallible call; it runs in tests and under `ZE0_VERIFY=1`. `clif-util` can parse the text emitter's output as an external check.

### 8.3 The object model, the Mach-O writer, the JIT loader (`lib/ze0/obj/`)

`Obj::Function{name, align, bytes, relocs}`, `Obj::Data{name, section: :text_const | :data_const | :bss, align, bytes, relocs}`, `Obj::Reloc{offset, kind, symbol, addend}` with kinds `branch26`, `page21`, `pageoff12`, `got_page21`, `got_pageoff12`, `abs64`; `Obj::Symbol{name, linkage: :local | :export | :import}`. Sidecar v2's `data` and `raw_functions` entries are this model, so on the Cranelift road Ruby supplies everything but function bodies and `clif2obj` fills those in.

`Obj::MachO.write(obj)`: a relocatable Mach-O 64: `mach_header_64` (arm64, `MH_OBJECT`), one unnamed `LC_SEGMENT_64` with `__TEXT,__text`, `__TEXT,__const` (pure bytes), `__DATA,__const` (data that carries pointers; absolute relocations in `__TEXT` are refused by `ld` for PIE), `__DATA,__bss` as `S_ZEROFILL`; `LC_BUILD_VERSION` (macos); `LC_SYMTAB` with `nlist_64` rows and the string table; `LC_DYSYMTAB`; per-section `relocation_info` rows with the arm64 types 0 `UNSIGNED`, 2 `BRANCH26`, 3 `PAGE21`, 4 `PAGEOFF12`, 5 and 6 `GOT_LOAD_PAGE21/PAGEOFF12`, 10 `ADDEND`. About 400 lines with `Array#pack`. References: `<mach-o/loader.h>`, `<mach-o/reloc.h>`, `<mach-o/arm64/reloc.h>`; the `object` Rust crate's writer; Homebrew's `ruby-macho` reader.

`Obj::JIT.load(obj, resolve)`: `mmap` with `MAP_JIT`, write under `pthread_jit_write_protect_np(0)`, apply relocations with imports from `dlsym(RTLD_DEFAULT)`, flip to executable, `sys_icache_invalidate`, return `{name => address}`. Under CRuby it uses Fiddle (as `jit_buffer` does); under `ze0/rt` it is kernel Ruby over the same libSystem calls. `MAP_JIT` needs no entitlement for a plain ad-hoc-signed CLI binary, which is what `ld` produces.

`Obj::Exe` (optional, B7): `MH_EXECUTE` with `__PAGEZERO`, `__TEXT`, `__DATA`, `__LINKEDIT`, `LC_MAIN`, `LC_LOAD_DYLINKER`, `LC_LOAD_DYLIB` libSystem, `LC_DYLD_CHAINED_FIXUPS` for imports, and `LC_CODE_SIGNATURE` with an ad-hoc `CodeDirectory` of SHA-256 page hashes, which Apple Silicon requires to execute. Until then `ld` signs ad hoc, as today.

### 8.4 The aarch64 backend (`lib/ze0/ir/arm64/`)

Instruction selection is nearly 1:1: `iconst` → `movz`/`movk` (or `mov` from `xzr`, or a bitmask immediate); `iadd/isub/band/bor/bxor/imul` → `add/sub/and/orr/eor/mul`; `ishl/sshr/ushr` → `lsl/asr/lsr`; `icmp` + `brif` → `cmp` + `b.cond` (fused when adjacent, else `cset`); `select` → `csel`; `load/store` of 8, 32, 64 bits → `ldr/str` with scaled immediate offsets (`ldrb`, `ldrsb`, `ldr w`); `uextend/sextend/ireduce` → `uxtb/sxtb/uxtw/sxtw` or nothing; `slot_addr` → `add x, x29, #off`; `symbol_value` and `func_addr` → `adrp` + `add` (local) or `adrp` + `ldr` through the GOT (import); `call` → `bl` with a `branch26` relocation; `call_indirect` → `blr`; `return` → epilogue + `ret`; `jump`/`brif` with block params → parallel copies then `b`/`b.cond`; `sadd_overflow` and friends → `adds` + `cset vs`; `f64` ops → `fadd/fsub/fmul/fdiv/fcmp/scvtf/fcvtzs` on `d` registers; `trap` → `brk #0`. Immediates that do not fit are materialized into a scratch register. Encodings come from the `aarch64` gem (generated from the ARM spec, with labels for local branches); we add relocation records for external symbols, which the gem lacks. The context-switch stub (8.10) is assembled by the same encoder.

Register allocation, step 1 (spill everything): every SSA value and block parameter owns a frame slot; an instruction loads its operands into `x9`..`x15` (`d16`..`d23` for floats), computes, stores its result; a jump with arguments stores into the target's parameter slots; no callee-saved register is touched, so the prologue is `stp x29, x30, [sp, #-16]!; mov x29, sp; sub sp, sp, #frame`. Step 2 (linear scan): live intervals over SSA values, block-parameter parallel-copy resolution at edges, callee-saved `x19`..`x28` for values live across calls, spill slots for the rest. TenderJIT's `register_allocator.rb` (graph colouring over an interference graph) and `arm64/register_allocator.rb` are the Ruby reference.

Apple arm64 rules the emitter enforces: `x18` is never allocated; `sp` stays 16-byte aligned at every instruction; `x29` always points at a valid frame record (the `stp x29, x30` pair is the first thing a function does, so the runtime's frame chain and any profiler agree); `x16`/`x17` are never live across a call; sub-32-bit integer arguments are extended by the caller (`uxtb`/`sxtb`, as `abi_param` does today); arguments in `x0`..`x7` and `d0`..`d7`, results in `x0`/`x1` and `d0`; no stack arguments (every signature has at most eight); floats never in integer registers; no variadic calls; no stack probes (the runtime does its own stack check); `adrp`+`add` pairs are never reordered and every `page21` relocation pairs with a `pageoff12`.

### 8.5 The kernel dialect (`Machine`)

The runtime's own language: Ruby syntax, machine semantics. Types `Word` (i64), `Ptr` (target width), `Value` (a tagged word), `F64`, `I32`, `Bool`. Every `machine def` declares parameter and return types; locals are typed by inference from literals, intrinsics and declared calls. Intrinsics: `Machine.load64/32/8`, `store*`, `addr`, `fixnum?`, `tag`, bit ops, wrapping arithmetic, `Machine.memcpy`. `Machine.import "write", [:i32, :ptr, :usize] => :isize` declares a foreign call (never variadic, never an aggregate by value). `Machine.struct :RBasic, flags: :u64, klass: :Value` is the one source of layouts (and of the C API's later). `Machine.const` for constants. `defer { }` is the one cleanup form: a non-allocating block lowered to the function's single landing block, run on both the normal and the `Qundef` exit (iteration levels, temp locks, `Dir.chdir` restore).

Effects, computed transitively over the call graph: `may_alloc`, `may_raise`, `may_call_ruby`. Every foreign and indirect call has all three unless annotated `noalloc`, which is allowed only on leaf libSystem calls. Rules the compiler enforces, as refusals by name at the line: a `may_raise` function returns `Value` (a Word- or Ptr-producing raising function takes an out pointer); in a `may_alloc` function every `Value`-typed variable is memory-resident in the frame record (every def a store, every use a load; `Word`/`Ptr`/`F64` stay SSA); an allocation writes its result to an out-slot in the caller's record before returning; a `Ptr` derived from a `Value` is dead after a `may_call_ruby` call and must be re-derived; no blocks, exceptions, Ruby objects or dynamic sends. Symbols are `zr_<name>` with the C ABI. Kernel frames link into the task chain like Ruby frames unless declared `leaf`.

```ruby
Machine.struct :RString, basic: :RBasic, len: :word, capa: :word, ptr: :ptr, enc: :i32, cr: :i32
Machine.import "write", [:i32, :ptr, :usize] => :isize, noalloc: true

machine def str_bytesize(s: Value) -> Word            # leaf: no record, s stays in a register
  RString.len(s)
end

machine def str_new(bytes: Ptr, n: Word) -> Value      # may_alloc: Value locals live in the record
  s = zr_alloc(RString.size, T_STRING)                 # stored to this frame's record before use
  RString.set_len(s, n)
  RString.set_ptr(s, zr_buf_alloc(n))                  # a raw buffer, not GC-managed
  Machine.memcpy(RString.ptr(s), bytes, n)
  s
end

machine def ary_each(ary: Value, blk: Value) -> Value  # may_call_ruby, may_raise
  i = 0
  while i < RArray.len(ary)                            # re-read after every yield: the block may mutate
    r = zr_yield(blk, RArray.ptr(ary), i)              # RArray.ptr re-derived here, never cached across
    return Qundef if r == Qundef                       # propagate; the block-passing site catches Break
    i += 1
  end
  ary
end
```

### 8.6 Memory: frames, roots, the collector

Frame record. Every compiled Ruby function reserves one addressable slot:

```
Frame { prev: Ptr, meta: Ptr (FrameMeta: name, file, owner, param names), line: Word, serial: Word,
        self: Value, nvalues: Word, values: Value[nvalues] (locals, temps, the args buffer), svars: Value[2] }
```

Prologue: stack check; nil-fill `values`; `f.serial = ++task.serial; f.prev = task.top; task.top = &f`. Epilogue, shared by the normal and the `Qundef` path: `task.top = f.prev`. The invariant: no `Value` lives in an SSA register across a call that can allocate or raise. A receiver is stored before its arguments are evaluated; each argument's result is stored before the next is evaluated. This is the discipline ze0's ownership ledger already imposes (`hand_over` before `borrow`, `lower.rb:7521`); the args buffer at `lower.rb:6141` moves inside the record. Values arriving in registers at a callee are safe because nothing allocates between the call and the callee's prologue store; the dispatcher (`zr_send`: cache miss, `method_missing` argument arrays, rest binding) is kernel code under the 8.5 rules. Captured locals live in a heap `Env{parent, self, nslots, slots}` per scope activation that has captures, not per-variable cells.

Heap. Per ractor: 64 KiB pages from `mmap` (darwin) or `memory.grow` (wasm), size classes 16..512 by 16, a large-object space, side mark bitmaps, lazy sweep into free lists. Payload buffers (string bytes, array slots, hash entries) come from a raw non-GC allocator and are freed by the sweep, so a `Ptr` derived from a rooted `Value` stays valid until a mutation reallocates it. Static objects (class objects, frozen literals in `.data`) carry `PERMANENT` and are never marked or swept; class objects live in `.data`, not `.rodata`, since they hold relocations and are mutable.

Collection runs only inside an allocation: the threshold (adaptive on bytes allocated since the last collection), `GC.start`, or every allocation under `ZR_GC_STRESS=1`. Roots: every task's frame chain (a suspended fiber's chain is traced when its Fiber object is marked, not as a global root), ractor globals, constants, the symbol table, at_exit procs, the program's data slots. Mark with an explicit stack; trace by type descriptor. Weak refs, `WeakMap`, finalizers (run on the owning ractor's thread at a safepoint, never in the sweep), `ObjectSpace.each_object` by heap enumeration, `object_id` as a monotone counter in a side table.

Checkers, from the first allocation: `ZR_GC_STRESS=1` collects at every allocation; `ZR_GC_VERIFY=1` scans every task's machine stack conservatively at each collection (bounds are known: per-task mmap'd stacks) and aborts on a heap pointer precise marking did not mark. Every corpus program becomes a root-precision test. Freed cells are poisoned in debug builds.

### 8.7 Values, headers, shapes

CRuby's tagging: fixnum `...1`, flonum `...10` (CRuby's rotation, so `1.0.equal?(1.0)` matches), `false = 0`, `nil = 8`, `true = 0x14`, `undef = 0x34`, static symbols `id << 8 | 0x0c`, heap pointers 8-aligned and nonzero. Chosen because flonum identity and `nil.object_id == 8` are observable, and because Part G gets RBasic for free. Header: 16 bytes `{flags, klass}` (RBasic layout): type tag (`T_OBJECT`, `T_STRING`, ... numbering), frozen, `PERMANENT`, `SHARED` (8.10), shape id; mark bits live in the side bitmap. Shapes: a global shape tree; an object's shape id is in `flags`; transitions on first ivar assignment; an ivar site caches `(shape id, slot index)`. Strings: `{len, capa, ptr, enc, coderange}`. Hashes: insertion-ordered open addressing, siphash13 for `String#hash`. Sorting: a port of CRuby's `ruby_qsort` (`util.c`), so tied orders match, which the bootstrap needs too.

### 8.8 Dispatch and signals

Dispatch. Classes carry a method table (open addressing by symbol id), linearized ancestors rebuilt on `include`/`prepend`, and a class serial. `zr_send(site, self, mid, argc, argv, blk)`: site cell hit on class serial → call; else the global cache `(serial, mid)` → method entry; else walk the ancestors; else `method_missing`, `respond_to_missing?`, refinements (per-site activation slots, as today), visibility against the site's caller class. A site is ONE word in `.bss` pointing to an immutable cell `(serial or shape id, entry)`, filled by allocate-then-release-store, so it is ractor-safe by construction; constant and ivar caches use the same cell shape. Method entries: owner, name, visibility, kind (compiled body, kernel builtin, attr, alias), params, code pointer. Fast paths stay inline in emitted code: fixnum `+ - * < ==` guarded by a `zr_patched` bit per class and a `zr_gates` word, both `.bss` data the code loads inline (the repo measured these at up to 54% on typed loops). Writers of method tables, constants and ancestry take the VM-wide lock; ancestry changes take the rendezvous (8.10).

Signals. A compiled function returns `Value`; `undef` means "a signal is pending in `task.pending`". After a fallible call: `icmp_imm eq v, 0x34; brif` to the function's landing block. Kinds: `Raise(exc)`, `Break(val, home)`, `Next(val)`, `Redo`, `Retry`, `Return(val, home)`, `Throw(tag, val)`, `Kill`. A home is `(record address, serial)`; a catch walks the current task's chain for it, so a dead or foreign-task home raises `LocalJumpError` at the proc call (`pr = proc { break }; [1].each(&pr)`). `rescue` reads the kind and takes the exception; `ensure` saves the pending signal into a record temp, runs, then restores unless the ensure body raised (CRuby's rule); `Kill` skips `rescue` and runs `ensure`. `throw` first checks the per-task catch-tag stack and raises `UncaughtThrowError` at the throw site with its own backtrace. Kernel loops propagate `Qundef` immediately and run their `defer` cleanup. Debug builds assert the sentinel and the pending slot agree, and that `Qundef` is never stored into an object slot. Backtraces read the frame chain at raise time.

### 8.9 The Cranelift shim (`clif2obj/`)

Inputs: CLIF text and sidecar v2. Steps: parse functions; declare every function `Local` with the target call conv; declare imports for `%zr_*`/`%zeo_rt_*` names; declare sidecar data objects and relocations, `Export` the ones a program names; rewrite `TestCase` names to `User` names; `define_function_bytes` for raw functions; verify; emit `.o`. Flags: `opt_level=speed`, `preserve_frame_pointers=true`, `is_pic=true`, `enable_probestack=false`, `unwind_info=false` on Mach-O. No signature table in Rust: the sidecar declares each import's signature and the link fails on a missing symbol; Ruby owns the table. `clif2obj_jit` uses `cranelift-jit` with a resolver callback (`dlsym(RTLD_DEFAULT)` needs `-export_dynamic` on eval-capable programs, as `loads_cext` does today). Pin `=0.134.3` for all seven crates; bump together.

### 8.10 Tasks, scheduling, ractors

Model. Ruby's own definition: Thread is concurrency, Ractor is parallelism. Per ractor: one Ruby-running OS thread, a run queue of tasks, a kqueue (darwin) or `poll_oneoff` (wasm) loop, a wakeup fd, a timer. Only one task runs per ractor, so every builtin is atomic by construction and no lock exists on the Ruby path.

A task owns: a machine stack (mmap with a guard page), the frame-chain head and record serial, the pending signal, the `$!` stack, catch tags, fiber-locals and thread-locals (two tables), the cref and eval-home stacks, the `super` resume state, recursion guards, pending interrupt bits, the stack limit. The `Ec` bundle in `crates/zeo-rt/src/ec.rs` is the inventory to carry over; `$~`/`$_` move into the frame record.

Preemption. A detached timer thread stores into each ractor's poll word every 100 ms (CRuby's quantum). Compiled code polls the word at loop back-edges and method entry (one load plus a branch, as `zeo_rt_pending_interrupts` is polled today); the slow path switches tasks on the task's own stack. Kernel code never polls; it is preempted only when it calls back into Ruby, so it re-reads lengths and pointers after every callback (CRuby's C-method discipline; the `Ptr` rule in 8.5 enforces the intra-function half).

Stack switch. `zr_switch(from, to)`: `stp x19..x28, x29, x30` and `d8..d15` into `from`, save `sp`; load the same from `to`; `ret`. A new stack starts with `x30 = zr_task_entry`, `sp = top`. About 26 words, assembled by the 8.4 encoder, delivered as an `Obj::Function` with no relocations (`raw_functions` on the Cranelift road, natively on the Ruby road). The scheduler swaps the task bundle before calling it.

Blocking. `Mutex`, `Queue`, `ConditionVariable`, `Thread#join`, `sleep` park and unpark on the scheduler; deadlock detection is "every task parked" and prints CRuby's message. Sockets go non-blocking on kqueue. Calls that cannot be async (`read` on files and pipes, `waitpid`, `getaddrinfo`, `system`, `flock`, `fsync`, `blocking: true` FFI) go to a small pool of helper OS threads that never touch Ruby objects, only buffers: the task parks, the helper completes and posts to the wakeup fd, the task requeues. This pool is the correctness floor for `test/core/thread`, `io`, `timeout`, `open3`, `socket` and ships in the first threaded milestone. Stack overflow: a prologue `sp < limit` check (a depth counter on wasm) as an IR op, raising `SystemStackError` before the record is linked. Thread kill and process exit deliver `Kill` (skips `rescue`, runs `ensure`); an unreachable suspended fiber is simply swept, as CRuby runs no `ensure` there. Signals: `sigaction` handlers are kernel functions that only set a flag; trap procs run at the main ractor's next safepoint.

Ractors. `Ractor.new` starts an OS thread with its own heap and scheduler. Messages copy deeply into the receiver's heap; `move` copies then poisons the source. `Ractor.make_shareable` deep-freezes and sets `SHARED` on every node in place, so identity is preserved as in CRuby; a ractor's private collection never frees or scans into `SHARED` objects (sound because shareable objects reference only shareable objects); on ractor exit, pages holding a `SHARED` object move to the global pool; `SHARED` objects are reclaimed only by a global collection at a rendezvous. Classes, modules, dynamic symbols and interned frozen strings are always allocated in the global pool. The rendezvous reuses the poll word: every ractor parks at its next safepoint (a ractor in a helper call is already parked); it is required for shared reclamation, ancestry mutation (a `super` walk may be running elsewhere), `ObjectSpace.each_object`, and process exit. Non-main ractors get `Ractor::IsolationError` on global and class-ivar writes; `$stdout` and friends are ractor-local. `fork` keeps the current task only.

### 8.11 The eval road

An eval-capable program links the compiler (`libze0.a`, ze0 compiled natively) and a loader (`libclif2obj.a` on the Cranelift road, `Obj::JIT` on the Ruby road). `zr_eval(src, binding, cref, file, line)` lowers with every static decision off (the eight traps in `zeo-eval-compiler` apply: hoisted defs, caller locals as env slots, run-time definee, cref chain as values, fresh id bases above the program's), emits IR, and either renders CLIF text for `clif2obj_jit` or runs `IR::Arm64` and `Obj::JIT`. Cached by `(src, scope names, cref, mode)`. Whether a program can eval is a HIR fact (`Eval` reachable, `instance_eval(str)`, `Binding#eval`, a surviving `require`), and it decides the link line.

### 8.12 Corelib mode

`rt/core/*.rb` is ordinary Ruby, one file per class, compiled once into `libzr.a` in a mode that: resolves `Primitive.zr_str_bytesize(self)` to a direct kernel call; honours `Primitive.attr! :leaf` (no frame record); registers every `def` as a builtin row with arity and `Method#parameters` from its signature; emits those rows as data (8.13). This is CRuby's own approach for `array.rb`, `kernel.rb` and `numeric.rb`. Hot primitives (string bytes, array storage, hash lookup, fixnum and flonum arithmetic, `to_s`, `sort`) are kernel functions; semantics live in Ruby.

### 8.13 Boot and the program description

Per class a static `zr_class` in `.data`: RBasic header with `PERMANENT`, name symbol, superclass relocation, a static sorted `(symbol_id, method_entry*)` array (binary search; the first runtime `def` copies it to a heap table, copy-on-write), static constants, the root shape and known ivar transitions, per-feature row lists for `require`-gated builtins. Corelib symbol, class and shape ids are fixed when `libzr.a` is built; a program's ids start after them, carried in its sidecar as `first_program_sym`, `first_program_class`, `first_program_shape`, the way `first_user_class` is today. `zr_main(argc, argv, desc)` in kernel Ruby: create the main ractor, heap and task; link parent and child lists; zero the site words; apply the program's rows; intern symbols; run the toplevel, `at_exit` handlers, finalizers, flush; exit status per `capi/lifecycle.rs:66`.

### 8.14 The wasm emitter (`IR::Wasm`)

Block params become locals with parallel copies at edges; control flow is structurized with Ramsey's Beyond Relooper (the bring-up hack: one `loop` + `br_table` over a block-index local); i64 ops map 1:1; addressable slots become a bump region in a linear-memory shadow stack; `symbol_value` and `func_addr` become data offsets and table indices; `call_indirect` uses a typed table. LEB128 and canonical section order; signed LEB128 is the classic bug, test it first. Milestone 1 is wasm32: `Value` stays i64 with a 32-bit pointer payload (CRuby's wasm build does this), because oniguruma, prism, zlib and openssl have wasm32 toolchain ports today and wasi-libc for wasm64 is incomplete; the IR keeps wasm64 open. Stack switching (milestone 2): an Asyncify-style unwind/rewind transform for every function that can be on the stack at a switch; with dynamic dispatch that is nearly every function, so about 2 to 3x code size and roughly half the speed on wasm, and no rewind through host frames. Swap to wasmtime's stack-switching proposal when it lowers on aarch64 hosts: a wasm feature we adopt, not an upstream change we make.

## 9. Verification

Command surface: `ze0 test [dirs | --all] [--native cranelift|ruby|ruby:<filter>] [--emit clif|wasm] [--gc plain|stress|verify] [--show N]`, buckets `skipped / refused / backend / matched / diverged / crashed / timeout`; `ze0 check`; `ze0 stage1` (Part A), `ze0 stage2` (Part E).

- **The oracle is ruby, only:** the recording under `__END__` (ruby 4.0.6, never re-run) for every corpus program; a live `ruby` where a check must write its own program (the DATA check). Nothing is compared against the Rust emitter or runtime.
- **Byte identity, the refactor oracle:** `test/goldens/`, `test/snapshots/` and `stage1` after A2, A2b and every IR change.
- **Corpus:** `ze0 test <dirs>` after every slice; `--all` at Part gates; per-directory match rates monotone under the allowlist. Only `diverged`, `crashed` and `timeout` are defects. Never a corpus-wide census in one process (`zeo-no-mass-census`).
- **The roads, per program:** (a) the recording; (b) `--native cranelift` in three GC columns (Part C); (c) `--native ruby`, the same (Part B and C); (d) `--emit wasm` (Part D). Compare stdout, normalized stderr, exit status.
- **Backend:** mixed-mode bisection on any divergence between (b) and (c); `IR::Interp` as a third opinion; disassembly snapshots in `test/native/`; the `.o` parsed back before linking.
- **Refusals:** one fixture per named refusal in `test/refused/`; a fixture that starts compiling is deleted the same day.
- **Kernel dialect:** golden IR per intrinsic; every effect rule has a refusal fixture; the C0 spikes are permanent tests in `test/zr/`.
- **Scheduler:** `test/core/thread` (129), `test/core/fiber`, deadlock messages against the oracle, 10k fibers, a blocked-`gets` producer and consumer, `Timeout.timeout` around a blocking read, `Thread#kill` of a blocked thread.
- **Ractors:** `test/core/ractor`; `a.equal?(Ractor.make_shareable(a))`; two ractors filling one call site under `ZR_GC_STRESS=1`; a parallelism smoke on two cores.
- **wasm:** the ladder through wasmtime; structurizer and LEB128 unit tests.
- **Performance (never a gate):** `benches/` at C5 and Part F; the Pathname 200k benchmark (CRuby 1.018 s; the Rust implementation's 0.359 s is a reference number, not a comparison ze0 runs).

## 10. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| A `Value` in a register across an allocating call | use-after-free | the 8.5 effect rules are compiler errors; `ZR_GC_STRESS` and `ZR_GC_VERIFY` on the whole corpus in CI; poisoned cells |
| A kernel loop leaves an object poisoned on the `Qundef` path (`iter_lev`, temp locks) | permanent errors | `defer { }` is the only cleanup form; an early `return Qundef` outside it is refused |
| A blocking syscall stalls a whole ractor | `thread`, `io`, `timeout` divergences | the helper pool ships in the first threaded milestone, before kqueue readiness |
| Compiled-Ruby corelib too slow (the 8x finding) | priority 3 | tagged words, no refcounts, inline caches, kernel primitives for hot paths; measured at C5; Part F |
| Green threads change observable scheduling | thread goldens | CRuby also interleaves at safepoints with a 100 ms quantum; the goldens are CRuby's |
| Stage 2 differs | bootstrap unsound | the E2 guard list; `ruby_qsort` port; counter `object_id`; one prism tree |
| Ruby backend miscompiles are silent | wrong answers, crashes | per-function mixed mode against Cranelift; `IR::Interp`; disassembly snapshots |
| Spill-everything code is slow | pure-road perf | linear scan (B4); Cranelift stays selectable until B's gate |
| Mach-O writer errors surface late | lost time | parse the `.o` back before linking; link mixed objects with Cranelift's |
| Asyncify tax on wasm | wasm speed and size | wasm is the second target; milestone 1 is single-task; adopt the stack-switching proposal when it reaches aarch64 hosts |
| Encoding tables and Onigmo-vs-Oniguruma gaps | divergences | port the generators, not the tables; keep `regexp/charrange.rs`'s four papers-over |
| Cranelift version churn | shim breakage | exact pins, quarterly bump, a test that the `.o` names no build-machine CPU feature; the Ruby backend removes the dependency |
| `lower.rb` at 7.5K lines in one class | velocity | A2 and A2b split it into HIR build, analyses and per-family lowerings |
| Nothing ze0 compiles runs until C0/B2 | refactors unchecked end to end | the text goldens and `stage1` check every refactor byte for byte; `clif2obj` and the kernel spikes come first in Part A and C so the pure road lights up early |
| Two backends in play for months | confusion | `--native` selects; mixed mode bisects; zeo is never modified for ze0's sake |

## 11. Non-goals

Linux and x86-64 (seams kept: target triple, pointer width, `sys_*.rb`, object format, the stub table; nothing verified there, per the standing macOS-only rule); Windows; a moving or generational collector (precise roots keep it possible); an interpreter or bytecode tier (the contract stays "compiled, CRuby-identical or refused"); the C API before Part G; wasm64 and WASI 0.2 before milestone 2; `ld`-free executables unless B7 is requested; ripper and `callcc`, which stay declined as today.

## 12. Toolchain, layout, ownership

Stage-0 host: CRuby 4.0.6 (`.ruby-version`, the oracle). Gems used by the compiler under CRuby: prism, `aarch64` (or our own encoder table), `jit_buffer`-style Fiddle calls for `Obj::JIT`. Vendored C (prism, oniguruma, zlib, openssl, libffi) built by `ze0 deps build` with `cc`. Apple tools: `ld` (required, signs ad hoc), `otool`/`llvm-objdump`/`nm`/`codesign` (dev-only checks). wasmtime for Part D. Cranelift 0.134.3 for `clif2obj` while it exists.

Layout of `~/dev/ze0` after Part A (Part 0 created the top-level shape; `~/dev/zeo` is untouched beyond losing `ze0/`):

```
ze0.rb, bin/ze0                  the CLI (ze0.rb stays the historical entry point)
.ruby-version                    the stage-0 host, which is also the oracle
lib/ze0/shims/rbconfig.rb.in     the ambient rbconfig shim
lib/ze0/harness/                 the test-file format and the corpus sweep
vendor/ext/<gem>/lib             the Ruby halves ze0 splices (prism among them)
docs/plan.md, docs/test-format.md
test/                            the corpus, test/ze0/, test/refused/, test/checks/, test/snapshots/, test/goldens/
lib/ze0/hir/                 node, build, analyze/, lower_legacy/ (until archived), lower_zr/, lower_machine/
lib/ze0/ir/                  function, block, inst, ops_high, legalize_*, verify, interp, clif_text, wasm, arm64/
lib/ze0/obj/                 model, macho, jit, exe
lib/ze0/machine/             types, effects, struct, import, aarch64
lib/ze0/cli/                 run, build, link, cache, test, check, stage1, stage2
lib/ze0/capi.rb              the legacy runtime table, archived with the legacy lowering
rt/kernel/                   value, heap, gc, frame, signal, dispatch, shape, symbol, string, array, hash, qsort, task, sched, pool, ractor, sys_darwin, sys_wasi
rt/core/                     one file per Ruby class
rt/enc/                      generated tables
rt/ext/<gem>/                native halves in kernel Ruby or FFI
rt/spike/                    the B2 micro runtime
rt/{boot,main}.rb
clif2obj/                 the optional Rust shim
test/zr/, test/native/           new corpora
```

Parallel ownership for worktrees (`parallelize` skill): A owns `clif2obj/`, `lib/ze0/cli/`, `lib/ze0/hir/`, `lib/ze0/ir/` (core); B owns `lib/ze0/ir/arm64/`, `lib/ze0/obj/`, `rt/spike/`; C owns `rt/`, `lib/ze0/machine/`, `lib/ze0/hir/lower_zr/`; D owns `lib/ze0/ir/wasm*`, `rt/kernel/sys_wasi.rb`.

Working rules that apply throughout (from the repo's memory): small focused commits with plain-English bodies; targeted tests per commit, the full gate at Part boundaries; one Bash, one intent, never two test suites at once; no corpus-wide census in one process; a gap file carries no analysis; a divergence is CRuby-identical or FAIL, never a silent drop; perf numbers in the commit that earns them.

## 13. What to do first

1. Part 0, the split: DONE 2026-09-08.
2. A1 (goldens, `stage1`) and A3 (`clif2obj` on hand-written CLIF against libSystem) in parallel: the refactor oracle and the first native light, both cheap.
3. A2 then A2b, each verified byte for byte.
4. B0 and B1 as soon as A2 lands: the Ruby backend against `clif2obj` on kernel programs. Then B2, the pure `fib`, which fixes the shape of the kernel dialect.
5. C0.1 to C0.4 beside B1; C1 and C2 next, with the `zr` lowering; `puts 1` through `zr` is M0 and the first corpus light.
6. A4, B3 to B6, C3 onward in parallel worktrees per section 12; archive the legacy lowering when M1 passes.
7. Report at each Part gate with the corpus numbers before the next Part starts.

## 14. Glossary

- **Value:** a 64-bit tagged word (8.7). **Qundef:** the `0x34` sentinel meaning "signal pending" (8.8).
- **Record / frame record:** the per-function shadow-stack entry the GC scans (8.6). **Home:** `(record, serial)` a `break` or `return` targets.
- **Task:** a green thread or fiber with its own machine stack (8.10). **Rendezvous:** every ractor parked at a safepoint.
- **High tier / low tier:** Ruby-level IR ops vs machine ops (8.2). **Legalize:** the per-target rewrite from high to low.
- **Obj:** the backend-neutral object model (8.3). **Mixed mode:** some functions from `IR::Arm64`, the rest from `clif2obj`, in one link.
- **Kernel dialect / `Machine`:** the runtime's typed subset of Ruby (8.5). **Corelib mode:** ordinary Ruby compiled with `Primitive` access (8.12).
- **Ladder:** the ordered corpus directories that gate Parts C and D (section 7).

## 15. References

- Cranelift 0.134.3 sources under `~/.cargo/registry/src/*/cranelift-{codegen,reader,module,object,jit}-0.134.3`: stack maps in text (`reader/src/parser.rs:2282`), `define_function_bytes` (`module/src/module.rs:981`), `stack_switch` x64-only (`codegen/src/isa/x64/lower.isle:3575`), Apple aarch64 ABI (`codegen/src/isa/aarch64/abi.rs:161`).
- Exceptions in Cranelift: https://cfallin.org/blog/2025/11/06/exceptions/ (not used; the status protocol is simpler and portable).
- Stack-switching proposal status: https://github.com/bytecodealliance/wasmtime/issues/10248 (x64 only).
- ZJIT: https://railsatscale.com/2025-12-24-launch-zjit/ and https://docs.ruby-lang.org/en/master/jit/zjit_md.html (SSA HIR with a type lattice, lowered to a LIR shared by x86-64 and arm64).
- TenderJIT: https://github.com/tenderlove/tenderjit (`lib/tenderjit/ir.rb`, `register_allocator.rb`, `arm64/code_gen.rb`, `arm64/register_allocator.rb`).
- `aarch64` gem: https://github.com/tenderlove/aarch64 (full ISA encoder, labels, `to_binary`, `write_to`); `jit_buffer` gem (`MAP_JIT` 0x800 on darwin, `pthread_jit_write_protect_np`, Fiddle `to_function`).
- Mach-O: `<mach-o/loader.h>`, `<mach-o/reloc.h>`, `<mach-o/arm64/reloc.h>`; the `object` Rust crate's writer; Homebrew's `ruby-macho`; `cs_blobs.h` for `CodeDirectory`.
- Apple arm64 ABI: https://developer.apple.com/documentation/xcode/writing-arm64-code-for-apple-platforms
- Beyond Relooper: https://www.cs.tufts.edu/~nr/pubs/relooper.pdf
- CRuby: `array.rb`, `kernel.rb`, `numeric.rb` (`Primitive`); `util.c` (`ruby_qsort`); `object.c` (flonum and special constants); `thread.c` (the 100 ms quantum); `gc.c` (`object_id` table).
- Slang, RPython, Jikes RVM `vmmagic`, MMTk: kernel-dialect and GC patterns.
- Repo memory: `zeo-corelib-dropped` (the 8x measurement), `zeo-cycle-collector` (why tracing was impossible before), `zeo-eval-compiler` (the eight eval traps), `zeo-ze0-frontier` (the 44/29/115 remainder), `ze0/PLAN.md` on branch `archive/zeo-front-end` (the three facts, the site-table rule), `crates/zeo-rt/src/ec.rs` in zeo (per-task state), `gvl.rs` (poll-word preemption). zeo is read for the port, never linked.
