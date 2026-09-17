# ze0: a self-hosted Ruby compiler and runtime, written in Ruby

Plan file, 2026-09-08 (revised the same day: ze0 depends on nothing from zeo; ruby is the only oracle; revised 2026-09-12: the Cranelift shim and the legacy text lowering are deleted, so ze0 owns no non-Ruby source at all). Two repos: `~/dev/zeo` (Rust) and `~/dev/ze0` (Ruby). Built from three codebase surveys, the pinned Cranelift 0.134.3 sources, a design review pass, TenderJIT and the `aarch64` gem, and six rounds of decisions with the user.

## 1. Context

zeo compiles Ruby to native code. The Rust workspace holds 317K lines: `zeo` (front end and Cranelift emitter, 90K), `zeo-rt` (runtime, 141K), `zeo-capi` (MRI C API, 25K), `zeo-abi`, helpers. Beside it, `ze0/` is a 9,906-line Ruby front end; `zeo backend` links its output against `libzeo.a`. ze0 compiles itself to a byte-identical stage-2 fixed point and matches CRuby on 5,753 of 5,944 corpus programs.

The goal: a self-hosted Ruby, as its own project. `~/dev/zeo` stays the Rust implementation; `~/dev/ze0` is the Ruby implementation, split out of `zeo/ze0/` first, and a clean new implementation from there: it links nothing from zeo, runs nothing from zeo, and holds itself to ruby's recordings alone. Compiler and runtime written in Ruby, compiled by themselves to a fixed point, producing native binaries for `aarch64-apple-darwin` and wasm modules for wasmtime, with the native code generator itself swappable between Cranelift (through a small Rust shim) and a pure-Ruby backend. User priorities, in order: (1) a working self-hosted Ruby, (2) zero non-Ruby code of our own, (3) generated-code performance, (4) backend learning. The contract is unchanged: identical to CRuby 4.0.6, or refused by name.

The brief the user supplied assumed a fresh start and left several items `[VERIFY]`. Section 2 settles them. This plan replaces the brief.

## 2. Ground truth that changes the brief

| Brief assumed | Repo or upstream fact |
|---|---|
| A Ruby front end must be written | `ze0/` exists: 9,906 lines, 141 runtime entry points, stage-2 fixed point, 5,753/5,944 matched. `lower.rb` is 7,565 lines in one class. |
| Conservative GC needed | ze0 already keeps every local in a stack slot. Precise roots cost nothing extra. |
| Variadic calls are a risk | Generated code never calls a variadic; every runtime entry is fixed-arity. Keep that rule. |
| No runtime exists | `zeo-rt` is 141K lines of CRuby-identical Rust: 24-byte `Arc` values, release pools, a Bacon-Rajan cycle collector, parallel OS threads with per-object locks, `corosensei` fibers, oniguruma, num-bigint, prism. |
| Compiled Ruby is fast enough for a runtime | Measured 2026-08-24: zeo-compiled Ruby rows ran 8x slower than Rust rows (Pathname bench). Cause: refcount traffic, 24-byte copies, dynamic sends. The new value model and kernel dialect remove those costs. Re-measure at C5. |
| A pure-Ruby backend is "Phase 7, optional" | The `aarch64` gem is a complete pure-Ruby ARM64 encoder with labels; TenderJIT is a working Ruby-written JIT with a three-address IR, a graph-colouring allocator and an arm64 code generator over that gem; `jit_buffer` does `mmap(MAP_JIT)` through Fiddle. The backend is a first-class seam here (Part B), missing only object-file relocations. |

Prior art the design follows: Squeak's Slang (VM in a Smalltalk subset), RPython, Jikes RVM `vmmagic` (unboxed `Address`/`Word`), CRuby's `Primitive` idiom for builtins written in Ruby (`array.rb`, `kernel.rb`), ZJIT's HIR-over-LIR layering, Go's generic-to-arch SSA rewriting, TenderJIT.

## 3. Decisions (locked with the user)

| # | Decision |
|---|---|
| D0 | **Two repos, two implementations, no dependency between them.** `~/dev/zeo` stays the Rust implementation, complete and maintained. `~/dev/ze0` is the Ruby implementation, split out first (Part 0) with its git history, self-contained: its own corpus, tests and vendored prism Ruby half. ze0 never links, runs or reads zeo: no runtime archive, no `zeo backend`, no ABI tables generated from zeo's sources. zeo is reading material for the port and nothing more. |
| D1 | **Scope:** compiler AND runtime in Ruby, in the ze0 repo. **ruby 4.0.6 is the only oracle**: the corpus recordings under `__END__`, and a live `ruby` where a check needs one. Nothing is compared against the Rust emitter or the Rust runtime. The lowering that named `zeo_rt_*` was a refactor scaffold held to text goldens; it is deleted (2026-09-12), and `stage1` now compiles the compiler twice through the `zr` road and compares the object bytes. |
| D2 | **Non-Ruby dependencies allowed:** prism (parser), openssl, libffi, libSystem, `cc`/`ld`/`ar`, wasmtime. Vendored C builds with `cc` through a Ruby script. **No C, Rust or assembler source of our own** — the README names every one of these and says why it is there. Revised 2026-09-16: the vendored C is leaving, zlib first (`rt/kernel/zlib_*.rb`, a port of 1.3.1 in the kernel dialect held to ruby's zlib byte for byte by `tools/zlib_diff.rb`), then oniguruma (a port of Onigmo, CRuby 4.0.6's engine: the compiler in plain Ruby under `rt/core/regexp/onig/`, the matcher in the kernel dialect under `rt/kernel/onig_*.rb`, held to ruby by `tools/regexp_diff.rb`; done 2026-09-16), then prism (a pure-Ruby backend of the gem); the plan is `~/.claude/plans/valiant-tumbling-ember.md`. |
| D3 | **Compiler layers:** Prism → tree HIR (desugared, name-resolved, target-neutral) → one CFG-SSA IR with two op tiers (Ruby-level ops legalized per target into machine ops) → emitters. Two data structures, no third typed HIR. |
| D4 | **Native backend seam:** every backend produces a backend-neutral `Obj` (functions, data, relocations, symbols). `IR::Arm64` writes the machine code, `Obj::MachO` the `.o` that `ld` links, `Obj::JIT` the in-process image, `Obj::Exe` the executable. `Obj::Patch` is the one relocation engine the JIT and the executable writer share. Since B7 (2026-09-12) `Obj::Exe` replaces `ld` for a program that needs no vendored archive, and `cc` links the rest. |
| D5 | **GC:** precise, non-moving mark-sweep over a shadow stack of frame records. No conservative scan, no stack maps. |
| D6 | **Signals (exceptions, break, return, throw):** the status protocol, spelled as a `Qundef` return sentinel. |
| D7 | **Concurrency:** per Ractor one Ruby-running OS thread, one heap, one green-task scheduler, plus a pool of helper OS threads for blocking calls. No GVL. Threads are green tasks preempted at safepoints; Fibers are green tasks switched explicitly; Ractors run in parallel with independent GC. |
| D8 | **Stack switch:** a Ruby-encoded aarch64 stub, delivered as raw function bytes as an `Obj::Function` with no relocations. Parked-OS-thread fibers only as a debug fallback. |
| D9 | **eval:** programs that can `eval` link the compiler (native) plus `Obj::JIT`; eval-free programs carry nothing extra. |
| D10 | **Targets:** `aarch64-apple-darwin` first; wasm on wasmtime second (wasm32 first, wasm64 kept open by an IR pointer-width parameter). Linux and x86-64 are non-goals with seams kept. |
| D11 | **Register allocation:** spill-everything first, linear scan second. |
| D12 | **Optimizer:** IR high-tier passes start after the bootstrap fixed point (Part F). |
| D13 | **C API (zeo-capi):** deferred to an optional last Part; the object header is RBasic-compatible so `rb_*` can be written in the kernel dialect later. |
| D14 | **Names:** `zeo` is the Rust implementation and its CLI; `ze0` is the Ruby implementation and its CLI. Runtime sources in `~/dev/ze0/rt/`, runtime symbols `zr_*`, kernel-dialect module `Machine`, environment `ZR_*`. The Rust road keeps `zeo_rt_*` untouched. |

## 4. Target architecture

```
 app.rb  ─┐                                                        ┌─► IR::Arm64 ─► Obj ─┬─► Obj::Exe ─────────────► binary
 rt/*.rb  ├─ prism ─► HIR ─► analyses ─► IR (high tier) ─► legalize ┤                     └─► Obj::MachO ─► .o ─► cc ─► binary
          │                (per target: zr | Machine)               ├─► Obj::JIT (eval, in process)
          │                                                         ├─► IR::Interp (an oracle, not a road)
          │                                                         └─► IR::Wasm ─► wasm ─► wasmtime
```

Ruby owns all of it: parsing glue, HIR, analyses, IR, legalization, both native emitters and the wasm one, the object model, the Mach-O writer, the executable writer, the JIT loader, the link driver, the CLI, the program cache, the runtime, the class library, the extensions' native halves, the test harness. Everything else is a dependency listed in D2. The Cranelift shim and the legacy text lowering (`zeo_rt_*` names, the 24-byte value ABI, `.clif` and `.zeodata`) were deleted on 2026-09-12, earlier than M1: the `zr` road had taken over every road that produces a binary, and `stage1` moved onto it.

## 5. Roadmap overview

| Part | Name | Depends on | Gate | Size (new Ruby, rough) |
|---|---|---|---|---|
| 0 | Split the repos | nothing | DONE 2026-09-08: `~/dev/ze0` is its own git repo with ze0's 138 commits, the corpus, `bin/ze0 test|check|scan` in Ruby, no reference to zeo; `~/dev/zeo` builds and its gate is green with `ze0/` gone | none (moves, ~600 lines of harness) |
| A | The compiler is Ruby | 0 | the IR and HIR reproduce ze0's own output byte for byte on `test/ze0/` and on the self-compile; hand-written IR turns into a Mach-O `.o` that `ld` links against libSystem and runs | 8-12K (HIR, IR, Obj, CLI) |
| B | The native backend in Ruby, and two spikes | A2 (IR) | B1 spike runs the kernel programs; B2 spike runs `fib` with no Rust; Part: the corpus matches ruby's recordings | 4-6K |
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

- **0.1** `git subtree split -P ze0` seeded `~/dev/ze0` with ze0's 138 commits. zeo lost `ze0/`, `test/ze0/`, the `ze0_refused` fixtures, the two ze0 snapshots, the five ze0 checks, the three-road corpus test, and the `stage2` and `ze0-sweep` xtask commands (commit `51babcca7`); `zeo backend` and its emit flags stay as zeo's own feature.
- **0.2** ze0 carries: the corpus (`test/lang core stdlib compiler aot bench milestones gaps`, ruby-recorded; the zeo-recorded `errors`, `features`, `divergences` are not copied), `test/ze0/`, `test/refused/`, `test/snapshots/`, the `rbconfig` shim, `vendor/ext/<gem>/lib` (the Ruby halves, prism included), `docs/test-format.md`.
- **0.3** The harness in Ruby: `bin/ze0 test <filter>|--all [--show N]` (buckets `skipped refused backend matched diverged crashed timeout`; the native road is a pluggable object, `nil` today, so every compiled program is `backend: no native road yet`), `bin/ze0 check` (minitest: hygiene, refused fixtures, snapshots with `ZE0_BLESS=1`, case format, DATA offset), `bin/ze0 scan`. `lib/ze0/harness/case.rb` is the test-file format and the scrubs.
- **0.4** Scaffolding: README, `.ruby-version` 4.0.6, Gemfile (prism, minitest), `.gitignore`, CI on macOS. `measure.rb` and `PLAN.md` (the front-end-for-zeo era) are on branch `archive/zeo-front-end`.
- Dropped from the original Part 0 by the user's direction: `toolchain.rb`, `.zeo-version`, the `zeo backend` link road, `stage2` (returns when the Ruby runtime links a binary), the builtins-drift check against `zeo_abi`.

### Part A: the compiler is Ruby, the shim is small (verified on ze0's own text)

Nothing runs in this Part: the oracle for a refactor is the object `ze0 stage1` writes, held byte for byte.

- **A1 ∥ Self-goldens (superseded 2026-09-12).** The text goldens went with the legacy lowering. `ze0 stage1` now compiles `tools/stage.rb` twice through the `zr` road, in two processes with a cache of its own each, and demands the same bytes from the compiler's object and the runtime's: a stronger check than the text one, covering HIR, IR, `IR::Arm64` and `Obj::MachO`, and with no text format in the loop. `test/hir/` holds the HIR dumps.
- **A2 The IR (DONE 2026-09-08).** `Ze0::IR` objects (section 8.2) behind the builder API; the lowering builds instructions directly (`stage1` 35 s → 22 s); `IR::Verify` runs before every native build; `IR::Arm64` and `IR::Wasm` consume it. The goldens, the snapshots and `stage1` hold byte for byte.
- **A2b The HIR (revised 2026-09-08).** `lib/ze0/hir/` (section 8.1) is built fresh for the `zr` road, not by moving the legacy lowering onto it: `lower.rb` has 507 methods and 174 node arms, most of them the refcount ABI's ownership ledger, and moving that family by family under byte identity would spend weeks on code the plan archives at M1. The legacy lowering stays as it is, held by its goldens, and is read as the reference for the declaration pass, captures, guards, splicing, refinements and parameter shapes. The HIR is verified by (1) an S-expression dump per `test/ze0/` program in `test/hir/`, reviewed once and then held byte for byte, and (2) the corpus through `lower_zr` against ruby's recordings, which is the oracle that matters. It grows with the ladder: M0's `puts 1` needs `Program`, `Send`, `Literal`; M1 needs the rest of section 8.1.
- **A3 ∥ `clif2obj` (DONE 2026-09-08, DELETED 2026-09-12).** 327 lines of Rust over five pinned Cranelift crates, reading CLIF text and an `Obj`-model sidecar to write the object `IR::Arm64` and `Obj::MachO` already wrote in Ruby. It was a second opinion on machine code and nothing else; `IR::Interp` and per-op disassembly snapshots take that role. `test/native/fixtures.rb` carries the hand-written IR it was first proved on.
- **A4 ∥ The CLI.** `ze0 zr run|build|machine|test|check|stage1|stage2|deps build`: options in CRuby's order, the program cache keyed on inputs, `-I` roots, `--emit obj|wasm`. `capi.rb` and the `zeo_rt_*` names went with the legacy lowering.

Gate: `stage1` is byte-identical, and `test/native/fixtures.rb` links against libSystem alone and runs.

### Part B: the native backend in Ruby, and two spikes

- **B0 The object model (DONE 2026-09-08).** `lib/ze0/obj/`: `Obj`, `Obj::MachO`, `Obj::JIT` per section 8.3, each held by a check (`nm`/`otool` read the object back; a Ruby-written `.o` links and runs; the JIT runs the hand-written IR in process under Fiddle).
- **B1 Spike 1 (DONE 2026-09-08).** `IR::Arm64` (spill-everything) compiles the C0 kernel-dialect programs and the hand-written IR of `test/native/fixtures.rb`; `Obj::MachO` writes the `.o`; the link ends in `cc` against libSystem. Gate: every `test/zr/` and `test/native/` program prints its recorded bytes.
- **B2 Spike 2: pure Ruby end to end.** Superseded 2026-09-08: the real kernel (`rt/kernel/`) and the `zr` lowering reached M0 first, so `fib` runs on them, not on a micro runtime; the gate (a binary of our bytes and libSystem only, printing 75025) stands. The original shape: a micro runtime in the kernel dialect (`rt/spike/`): `zr_write`, fixnum `to_s`, `puts` for Integer and String literals, an overflow trap, `main`. A `--profile micro` lowering for `def`, locals, Integer literals and arithmetic, comparisons, `if`/`while`, calls, `puts`. Program: `def fib(n) = n < 2 ? n : fib(n - 1) + fib(n - 2); puts fib(25)`. Road: prism → HIR → IR → `IR::Arm64` → `Obj::MachO` → `ld` against libSystem only. Gate: the binary holds only our bytes and libSystem, and prints 75025. This fixes the shape of C1's `Machine` lowering early.
- **B3 Instruction selection (DONE 2026-09-12).** `IR::Listing` stands in for the encoder and records what the backend chose, so `test/native/disasm.txt` pins selection for all 93 opcode forms with each relocation written beside the instruction carrying it. The gem has no disassembler and needs none: `aarch64_test.rb` holds the encoding to it over 3000+ runtime functions, which is the other half of the question. `ZE0_BLESS=1` rewrites.
- **B4 Register allocation, step 2 (DONE 2026-09-12).** `IR::Arm64::Regalloc`: liveness to a fixed point over a worklist, one interval a value, `x19`..`x28` in start order. Only the callee-saved ten, so a value in a register survives a call for free and never collides with the lowering's scratch -- and a value the allocator says nothing about keeps its frame home, so being conservative is never being wrong. The runtime is 13.3% smaller (9,938,968 bytes against 11,469,948) and a compute benchmark 2.7x faster (0.070 s against 0.186 s); compiling the runtime costs 6.4 s against 2.6 s. The five refusals stay: the runtime sits at exactly eight parameters and eight call arguments and never above.
- **B5 ABI conformance.** Section 8.4's Apple rules as emitter assertions and as tests (a function with eight args, mixed float args, a sub-32-bit arg).
- **B6 The JIT road.** `zr_eval` loads through `Obj::JIT` (section 8.10). Gate: `test/lang/eval`.
- **B7 No `ld` (DONE 2026-09-12).** `Obj::Exe` writes a complete, signed `MH_EXECUTE` (section 8.3) and is the default linker. It covers every program whose imports are all libSystem's -- `test/native` and `test/zr` entire. It refuses anything reaching `libprism.a` by naming the symbol, and `cc` links those: dead stripping keeps prism out of a program that does not parse at runtime. Oniguruma, which reached even `puts "hello"`, is gone (2026-09-16): `Regexp` is Ruby. Reading clang objects and `ar` archives would close that, and is not scheduled. Dead stripping is not done and is not wanted: an `Obj::Exe` binary of a `test/zr` program is already 100-400 bytes smaller than the one `cc` writes with `-dead_strip`, because a kernel-dialect unit carries almost nothing unreachable.

Gate for the Part: `ze0 test --all` matches the corpus, and the disassembly snapshots and `IR::Interp` agree with what runs.

### Part C: the runtime in Ruby (`rt/`)

- **C0 Experiments, in order.** C0.1 kernel spike: `machine def main` calling `write(2)` and `exit(2)` through IR → both native emitters → binary (DONE: `test/zr/hello.rb`). C0.2 raw-function spike: the context-switch stub, two stacks ping-ponging 1e6 times (DONE: `test/zr/switch.rb`, ~10 ms). C0.3 shadow-stack spike: allocate in a loop with a frame record; collect under stress (DONE: `test/zr/gc.rb`, section 8.6 revised from what it found). C0.4 wasm spike: C0.1 through `IR::Wasm` and wasmtime with `fd_write` (DONE: `lib/ze0/ir/wasm.rb`; every `test/native` and `test/zr` program but the raw-function one prints the same under wasmtime, the collector included). Each spike is a permanent test.
- **C1 The kernel dialect.** `lib/ze0/machine/` per section 8.5: types, signatures, intrinsics, `Machine.struct`, `Machine.import`, `defer`, the transitive effects and the rules the compiler enforces. Verify: golden IR per intrinsic; every rule has a refusal fixture. C1a DONE 2026-09-08: `&&`/`||`/`!`/`-x`/`unless`, top-level constants folded at compile time, `Machine.struct` with readers, writers and embedded structs, `Machine.sig` + `Machine.call` through a pointer (a new `call_indirect` in the IR: `blr` on arm64, a funcref table on wasm), `Machine.compile_unit` over several files; `test/zr/{logic,structs,indirect}.rb` and `test/zr/units/pair/` on all three roads. C1b DONE 2026-09-08: the transitive `may collect` effect (`Machine.collects` names the seed; a call through a pointer counts) and the `Value` rule it enforces: every Value a collecting def holds (parameters, locals, a call's answer passed to another call) lives in a root frame the collector walks (`zr_static_kroots`). Constants and struct layouts fold on first use, so the kernel files come in any order. Still open: `defer`, F64, the `Ptr` rule.
- **C2 Object model and dispatch core.** M0 DONE 2026-09-08: `rt/kernel/` (values and type tags, a 64-byte-cell heap with the spike's precise collector over frame records and the globals, RClass with a method table, `zr_send`/`zr_vcall`, RString, `to_s` for Integer/Symbol/nil/true/false/Object, `Kernel#puts`, boot, `main`); `lib/ze0/hir/` (Program, Seq, Send, Literal, SelfRef; dumps in `test/hir/`); `lib/ze0/zr/lower.rb` (`zr_toplevel` with a frame record); `ze0 zr run|build`; `test/programs/` against a live ruby on both native roads, under stress, and under wasmtime. Section 8.7 and 8.8: values, headers, shapes, classes, method tables, caches, symbols, strings (UTF-8/US-ASCII/BINARY first), arrays, hashes, ranges, procs and envs, exceptions, frames and backtraces, `puts`/`p`/`inspect`, `ruby_qsort`. The `zr` lowering (`hir/lower_zr/`) lands beside the legacy one here and takes over `ze0 test`; the legacy lowering, its goldens and `capi.rb` go to branch `archive/legacy-lowering` when M1 passes. Corpus: `puts 1` (M0), `test/ze0/`, then ladder M1. M1 progress 2026-09-08: exceptions as the Qundef signal with CRuby's backtraces; begin/rescue/else/ensure/retry and `Kernel#raise`; classes, modules, `include` (proxy classes), constants, ivars on objects and classes, singleton defs and classes with metaclasses; blocks, procs, `break`/`return` homes; the whole parameter surface (optional, rest, post, keyword, block; splat, keyword and block-pass arguments; multiple assignment and destructuring); Array, String, Hash; the core library in `rt/core/*.rb` (ordinary Ruby, compiled in internal mode so its methods are builtin frames and its blocks leave no row). `test/ze0/`: 11 matched, 50 refused, 18 diverged (each an honest NoMethodError on a missing method). M1 progress 2026-09-09: `test/lang` M1 directories at 1318 matched of 1941 (control 75, variables 87, methods 271, blocks 212, syntax 12, exceptions 220, constants 42, classes 236, modules 91, singleton 72); every crash is an honest `ze0: X is not implemented yet` stop. Landed since: the exception tree and `Kernel#raise`'s protocol, dup and clone, Enumerator (eager) and ArithmeticSequence, Struct over hidden ivars, String's character methods over byte primitives (ASCII only, a stop on anything else), Kernel's conversions, Proc composition and curry, catch and throw as a fourth signal kind, Method and Module reflection (super_method, included_modules, nesting, remove_method, private_constant, subclasses, caller), CRuby's opt_new frame rule, the cref-in-context rule for define_method, a recursion guard for inspect. Next by census: Kernel#format, `super` in define_method bodies, Data, ENV/ARGV/RUBY_* constants, ruby2_keywords, then Float (C5) and bignums.
- **C3 GC.** Section 8.6. Corpus: M1 in three columns.
- **C4 Scheduler, threads, fibers, ractors.** Section 8.10. Corpus: M5.
- **C5 The class library.** `rt/core/*.rb` in corelib mode (section 8.11), ported class by class from `crates/zeo-rt/src/builtins/` in ladder order: Kernel; Integer and Float (shortest round-trip digits, then CRuby's `flo_to_s` formatting rules including the `1e16` exponent thresholds); String and Symbol; Array; Hash; Range; Comparable, Enumerable, Enumerator (fiber-backed external iteration); Struct and Data; the Exception tree (generated from the `zeo-abi` tables); Proc, Method, UnboundMethod; Module and Class reflection; Regexp and MatchData over a Ruby port of Onigmo (`rt/core/regexp/onig/`, `rt/kernel/onig_*.rb`, and `rt/core/regexp_pattern.rb` for re.c's preprocess); Time (Hinnant civil algorithms, `localtime_r` for zones); IO, File, Dir, Stat, Process over libSystem; Marshal 4.8; pack and unpack; sprintf; Encoding (the 103-row registry first, byte mappings as the corpus demands, all tables generated from the oracle by Ruby scripts into `rt/enc/`); Bignum (64-bit limbs, schoolbook and Karatsuba, divide-and-conquer `to_s`); Rational and Complex; Random (MT19937); ObjectSpace; GC; Signal; Ractor; RubyVM::AbstractSyntaxTree over prism. `RUBY_ENGINE` stays `"ruby"`, `RUBY_VERSION` `"4.0.6"`. Measure the Pathname benchmark from `zeo-corelib-dropped` at the end.
- **C6 Extensions.** The 24 `crates/zeo-rt/ext/*` gems keep their Ruby halves (`ext/*/lib`); native halves move to kernel Ruby or FFI: json (parser and generator in Ruby), stringio, strscan (over the Onigmo port), digest (md5 and sha in the kernel dialect), zlib in the kernel dialect (done 2026-09-16) and openssl over vendored C via FFI, socket over libSystem, io-console, etc, fcntl, date, bigdecimal, psych (a Ruby YAML parser), ffi (libffi via FFI plus the direct `call_indirect` tier for scalar signatures), fiddle, prism. One prism source tree serves stage 0 (CRuby's extension), stage 1, and the runtime's FFI binding. Verify: the `zeo-pure-ruby-lane` matrix (one golden against CRuby's C ext, the pure tree under CRuby, the pure tree under zeo).
- **C7 Boot and the program description.** Section 8.13. `libzr.a` = kernel objects + corelib objects + the raw stub, built once by `ze0 rt build`.

Gate: `ze0 test --all` matches the corpus in three columns: plain, `ZR_GC_STRESS=1`, `ZR_GC_VERIFY=1`; the allowlist of known failures only shrinks.

### Part D: the wasm target

- **D1 `IR::Wasm`.** Section 8.14. Verify: LEB128 and structurizer unit tests over hand-written CFGs, including an irreducible one; C0.4.
- **D2 A Ruby wasm linker.** Corelib and kernel are emitted as IR modules once; a program links by function renumbering and data-segment concatenation. No `wasm-ld`.
- **D3 `sys/wasi.rb`.** WASI preview 1 imports; `memory.grow`; preemption via the poll word plus wasmtime epoch interruption. `fork`, signals, `exec`, `pty`, libffi, dlopen (so `eval`), and sockets (until WASI 0.2) refuse by name on wasm.
- **D4 Milestone 1: wasm32, single task.** No Fiber, Thread, Ractor, FFI, eval or signals. Corpus: ladder M1 and M2 minus what needs those, on stdout plus exit status.
- **D5 Milestone 2: stack switching on wasm.** An Asyncify-style unwind/rewind transform in `IR::Wasm` (section 8.13). Ractors on wasm run as green tasks in the one ractor.

Gate: M1 and M2 through wasmtime; native and wasm agree byte-for-byte on stdout and status for every program both accept.

### Part E: bootstrap to the fixed point

- **E1 Stage 0 and 1.** ze0 on CRuby compiles `rt/` to `libzr.a`, then compiles itself against it: stage 1, native, running on the new runtime.
- **E2 Stage 2.** Stage 1 recompiles `rt/` and itself. Compare every artifact (the `.o` from the Ruby backend, the wasm module); `ze0 stage2` returns here, with A1's `stage1` as its first half. Known sources of difference, each guarded: sort ties (the `ruby_qsort` port), `object_id` (a counter, never an address; ze0 keys tables by `node.object_id`), hash order (insertion; lint ze0 for ordering by `.hash`), prism version (one source tree), `RUBY_ENGINE` folding, per-file `frozen_string_literal`, `Dir.glob` order, `inspect` addresses in output, the main task's stack depth under prism's recursive visitors. Report the first differing byte and its line, as the old `stage2.rs` did.
- **E3 Cut the last tie (DONE 2026-09-12).** `clif2obj/` is deleted and the Ruby backend is the only one. A ze0 checkout needs ruby, `cc`/`ld`/`ar`, and the vendored C deps, and the README names each.

Gate: `ze0 stage2` reports byte-identical artifacts from stage 1 and stage 2, and every corpus program compiled by both binaries is byte-identical.

### Part F: performance

Passes on the IR high tier: constant folding, inlining of small kernel functions and `attr_*`, fixnum type inference and guard hoisting, block escape analysis (stack-allocated envs for non-escaping blocks), fused iterator loops (`3.times`, `arr.each`, as the Rust emitter did). Register allocation step 2 if B4 has not landed. Instrument: `benches/` through the Ruby road, the Pathname 200k benchmark, `test/bench`. Perf is never a gate (`zeo-perf-not-a-gate`); every number goes in the commit message.

### Part G (optional): the C API in kernel Ruby

`rb_*` over the RBasic-compatible header, `RString`/`RArray` layouts from `Machine.struct`, `rb_protect` over the status protocol, a handle table for `VALUE`s held by C, `make test-capi` as the gate. Not scheduled.

## 7. The corpus ladder (Parts C and D)

Each rung's per-directory match rate is monotone, enforced by a committed allowlist of known failures that may only shrink.

| Rung | Corpus | Brings in |
|---|---|---|
| M0 | DONE 2026-09-08: `test/zr/` (kernel-dialect programs, native and wasm), `test/rt/` (the kernel through hand-written toplevels), `test/programs/` (`puts 1` and friends on the new runtime, GC on, against a live ruby) | the dialect, both emitters, boot |
| M1 | `test/ze0/` (82); `test/lang/{control,variables,methods,blocks,syntax,exceptions,constants,globals,classes,modules,singleton}` | object model, dispatch, signals, GC in three columns |
| M2 | `test/core/{kernel,object,numeric,string,array,hash,range,comparable,enumerable,struct,format,pack,regexp,encoding,time}` | corelib, the regexp engine, encodings, bignum, float formatting |
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

A CFG in SSA form with block parameters: `Function{name, sig, slots[], symbols[], sigs[], callees[], blocks[]}`, `Block{params[], insts[]}`, `Inst{op, type, args[], results[], targets, sig}`. Types `i8 i32 i64 f64` plus `ptr` (resolved per target: 64 on darwin and wasm64, 32 on wasm32). Addressable slots are first-class (`slot`, `slot_addr`); the native emitters lower them to frame areas, the wasm emitter to a linear-memory shadow-stack region.

Two op tiers in one structure. The high tier carries Ruby-level ops with their site shape: `send`, `send_super`, `yield`, `guard_fixnum`, `fixnum_add` (with an overflow edge), `ivar_get/set`, `const_get`, `gvar_get/set`, `alloc`, `frame_enter/leave`, `stack_check`, `signal_check`, `raise`. `Legalize::ZeoRt`, `Legalize::Zr` and `Legalize::Machine` rewrite each high op into machine ops and runtime calls for that target; `IR::Verify` refuses a high op that reaches an emitter. During Part A the `zeo-rt` lowering may emit the low tier directly so the byte-identity gate stays simple; the `zr` and `Machine` lowerings use the high tier from their first commit. Optimization passes (Part F) run on the high tier.

Emitters: `IR::Arm64` (to `Obj`) and `IR::Wasm`. `IR::Interp` (DONE 2026-09-12) interprets IR as an oracle, so a miscompile in `IR::Arm64` shows as a disagreement rather than a wrong answer nobody can localise; it models the machine the backend targets rather than an abstract one, and `IR::Types` is the one definition of what type a value has, read by the backend and the interpreter alike. `IR::Verify` checks: every block terminated, every use dominated by its definition, types agree, no `Value`-typed SSA use across a fallible call; it runs in tests and under `ZE0_VERIFY=1`.

### 8.3 The object model, the Mach-O writer, the JIT loader (`lib/ze0/obj/`)

`Obj::Function{name, align, bytes, relocs}`, `Obj::Data{name, section: :text_const | :data_const | :bss, align, bytes, relocs}`, `Obj::Reloc{offset, kind, symbol, addend}` with kinds `branch26`, `page21`, `pageoff12`, `got_page21`, `got_pageoff12`, `abs64`; `Obj::Symbol{name, linkage: :local | :export | :import}`.

`Obj::MachO.write(obj)`: a relocatable Mach-O 64: `mach_header_64` (arm64, `MH_OBJECT`), one unnamed `LC_SEGMENT_64` with `__TEXT,__text`, `__TEXT,__const` (pure bytes), `__DATA,__const` (data that carries pointers; absolute relocations in `__TEXT` are refused by `ld` for PIE), `__DATA,__bss` as `S_ZEROFILL`; `LC_BUILD_VERSION` (macos); `LC_SYMTAB` with `nlist_64` rows and the string table; `LC_DYSYMTAB`; per-section `relocation_info` rows with the arm64 types 0 `UNSIGNED`, 2 `BRANCH26`, 3 `PAGE21`, 4 `PAGEOFF12`, 5 and 6 `GOT_LOAD_PAGE21/PAGEOFF12`, 10 `ADDEND`. About 400 lines with `Array#pack`. References: `<mach-o/loader.h>`, `<mach-o/reloc.h>`, `<mach-o/arm64/reloc.h>`; the `object` Rust crate's writer; Homebrew's `ruby-macho` reader.

`Obj::JIT.load(obj, resolve)`: `mmap` with `MAP_JIT`, write under `pthread_jit_write_protect_np(0)`, apply relocations with imports from `dlsym(RTLD_DEFAULT)`, flip to executable, `sys_icache_invalidate`, return `{name => address}`. Under CRuby it uses Fiddle (as `jit_buffer` does); under `ze0/rt` it is kernel Ruby over the same libSystem calls. `MAP_JIT` needs no entitlement for a plain ad-hoc-signed CLI binary, which is what `ld` produces.

`Obj::Exe` (DONE 2026-09-12): `MH_EXECUTE` with `__PAGEZERO`, `__TEXT` (`__text`, `__stubs`, `__const`), `__DATA_CONST` (`__got`, `__const`), `__DATA` (`__data`, `__bss`) and `__LINKEDIT`; `LC_MAIN`, whose `stacksize` is the number `ld` takes from `-stack_size` so both roads give a program the same room; `LC_LOAD_DYLINKER`, `LC_LOAD_DYLIB` libSystem, `LC_DYLD_EXPORTS_TRIE`, `LC_DYLD_CHAINED_FIXUPS` and `LC_CODE_SIGNATURE`. One chained mechanism carries both kinds of fixup: `__got` slots bind and `abs64` slots rebase, threaded per 16 KB page in `DYLD_CHAINED_PTR_64_OFFSET`, the slot holding the chain entry rather than the address. The signature is an ad-hoc `CodeDirectory` of SHA-256 page hashes, which Apple Silicon requires to execute; its size follows from where it starts, so there is no circularity. The UUID is the image's own hash, so two writes of one program give the same bytes. `Obj::Stamps` stays for `stage2`, whose binary reaches prism and so goes through `ld`, which stamps a fresh UUID into every link. An empty segment is not written: an image with a zero-length one does not load.

### 8.4 The aarch64 backend (`lib/ze0/ir/arm64/`)

Instruction selection is nearly 1:1: `iconst` → `movz`/`movk` (or `mov` from `xzr`, or a bitmask immediate); `iadd/isub/band/bor/bxor/imul` → `add/sub/and/orr/eor/mul`; `ishl/sshr/ushr` → `lsl/asr/lsr`; `icmp` + `brif` → `cmp` + `b.cond` (fused when adjacent, else `cset`); `select` → `csel`; `load/store` of 8, 32, 64 bits → `ldr/str` with scaled immediate offsets (`ldrb`, `ldrsb`, `ldr w`); `uextend/sextend/ireduce` → `uxtb/sxtb/uxtw/sxtw` or nothing; `slot_addr` → `add x, x29, #off`; `symbol_value` and `func_addr` → `adrp` + `add` (local) or `adrp` + `ldr` through the GOT (import); `call` → `bl` with a `branch26` relocation; `call_indirect` → `blr`; `return` → epilogue + `ret`; `jump`/`brif` with block params → parallel copies then `b`/`b.cond`; `sadd_overflow` and friends → `adds` + `cset vs`; `f64` ops → `fadd/fsub/fmul/fdiv/fcmp/scvtf/fcvtzs` on `d` registers; `trap` → `brk #0`. Immediates that do not fit are materialized into a scratch register. Encodings come from the `aarch64` gem (generated from the ARM spec, with labels for local branches); we add relocation records for external symbols, which the gem lacks. The context-switch stub (8.10) is assembled by the same encoder.

Register allocation, step 1 (spill everything): every SSA value and block parameter owns a frame slot; an instruction loads its operands into `x9`..`x15` (`d16`..`d23` for floats), computes, stores its result; a jump with arguments stores into the target's parameter slots; no callee-saved register is touched, so the prologue is `stp x29, x30, [sp, #-16]!; mov x29, sp; sub sp, sp, #frame`. Step 2 (linear scan): live intervals over SSA values, block-parameter parallel-copy resolution at edges, callee-saved `x19`..`x28` for values live across calls, spill slots for the rest. TenderJIT's `register_allocator.rb` (graph colouring over an interference graph) and `arm64/register_allocator.rb` are the Ruby reference.

Apple arm64 rules the emitter enforces: `x18` is never allocated; `sp` stays 16-byte aligned at every instruction; `x29` always points at a valid frame record (the `stp x29, x30` pair is the first thing a function does, so the runtime's frame chain and any profiler agree); `x16`/`x17` are never live across a call; sub-32-bit integer arguments are extended by the caller (`uxtb`/`sxtb`, as `abi_param` does today); arguments in `x0`..`x7` and `d0`..`d7`, results in `x0`/`x1` and `d0`; no stack arguments (every signature has at most eight); floats never in integer registers; no variadic calls; no stack probes (the runtime does its own stack check); `adrp`+`add` pairs are never reordered and every `page21` relocation pairs with a `pageoff12`.

### 8.5 The kernel dialect (`Machine`)

The runtime's own language: Ruby syntax, machine semantics, lowered by `lib/ze0/machine/lower.rb` straight to the IR. Types `Word` (i64), `Ptr` (target width), `Value` (a tagged word), `F64`, `I32`, `I8`, `Bool`. Every `machine def` follows a `sig [params] => ret`; locals are typed by inference from literals, intrinsics and declared calls, and a local may not change type. Intrinsics: `Machine.load64/32/8`, `store64/32/8`, `word`, `ptr`, `value`, `i32`, `i8`, `f64`, `bits`, `addr` (a function's address), `bytes` (a read-only literal), `bytesize`, `id` (a symbol id), `slot(n)` (n bytes of the frame), `static(:name, size)` (a `.bss` word shared by every def that names it), `call(:sig, ptr, args...)` (a call through a `Machine.sig`), `extern`. `Machine.import "write", [I32, Ptr, Word] => Word` declares a foreign call (never variadic, never an aggregate by value; `from: "wasi_snapshot_preview1"` names a wasm module, and a `machine def` of an imported name answers that import's calls, so an OS layer defines what its libc lacks). `Machine.struct :RBasic, flags: Word, klass: Value` is the one source of layouts: fields at natural alignment, a field of a struct type embedded in place, `Name.field(p)`/`Name.set_field(p, v)` accessors and `Name.size`. A constant is an integer, a constant, a struct's size or an operator over those. Symbols are `zr_<name>` with the C ABI; a builtin takes `(recv, argc, argv, cref, blk)` (`Machine.sig :builtin`) and a compiled method `(recv, argc, argv, entry, blk, found)` (`Machine.sig :method`): its own `MEntry`, whose `mid` and `cref` its frame records, and the chain node the lookup found it on, which the frame keeps as `defined`.

There is no `defer` and no effect analysis beyond `collects`. `Machine.collects` names the defs that can reach an allocation (computed transitively over the call graph); each one gets a root frame linked from `zr_static_roots`, and every `Value` it holds lives in a slot of that frame: its parameters, its locals, and any `Value` a call, a struct read or `Machine.value` produced that is passed on to another call in the same argument list (`rooted`). `IR::Mem2Reg` makes the non-`Value` locals registers. The kernel's own inlining copies a small def with no early `return`, `while` or `break` into its caller at lowering; `IR::Passes::Inline` then copies any leaf of a unit (no call, no slot read, at most 24 instructions) into its callers before the pipeline, callees first, so a def that returns early, such as `zr_type` or `zr_modify_frozen_p`, is inline at its sites too. The rules the kernel keeps by convention, not by the compiler: a `Ptr` derived from a `Value` (a String's buffer, an Array's slots, a Hash's entries) is read again after any call that can run Ruby, since the call may have reallocated it; a fallible def answers `Value` and `QUNDEF` when a signal is pending; a message buffer (`Buf`) starts in its own 64-byte tail on the stack and mallocs only when it grows, so a raise that never takes it leaks nothing.

```ruby
Machine.struct :RString, basic: RBasic, len: Word, capa: Word, ptr: Ptr
Machine.import "write", [I32, Ptr, Word] => Word

sig [Value] => Word
machine def zr_str_bytesize(s)              # no allocation: s stays in a register
  RString.len(s)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_ary_each(recv, argc, argv, cref, blk)
  i = 0
  while i < RArray.len(recv)                # re-read after every yield: the block may change it
    r = zr_yield1(blk, zr_ary_at(recv, i))  # zr_yield polls for preemption before the call
    return r if r == QUNDEF                 # propagate; the site that passed the block catches Break
    i += 1
  end
  recv
end
```

### 8.6 Memory: frames, roots, the collector

Frame record. Every compiled Ruby function reserves one addressable slot:

```
Frame { prev: Ptr, meta: Ptr (FrameMeta: name, owner, file, kind, params, ...), line: Word,
        self: Value, cref: Value, blk: Value, entry: Ptr (the MEntry a method was called through, 0 otherwise),
        defined: Value, serial: Word (0 until `zr_frame_serial` first gives one), nvalues: Word,
        svars: Value (nil, or [$~, $_] once one is written) }  followed by values: Value[nvalues] (locals, staging slots, prologue slots)
```

Prologue: the entry and `defined` stored, then the stack check against `Task.stack_limit`; the other header stores; a nil-fill of every value slot but a plain required parameter's, which takes its argument straight after the arity check; `f.prev = task.top; task.top = &f`. Epilogue, on the normal and the `QUNDEF` path alike: `task.top = f.prev`. The invariant: no `Value` lives in an SSA register across a call that can allocate or raise. A receiver is stored to a staging slot before its arguments are evaluated, and each argument's result before the next is evaluated; a call reads them back into registers, and the callee's prologue stores them before anything can allocate. A scope that holds a block literal keeps every local in an `REnv{parent, slots, nslots, names, cell, home}`, read and written inline through `REnv.slots`. A method's or a block's Env starts as an image in its own record, flagged `FL_STACK` and marked already, whose `slots` are the record's local slots; the first keeper of the scope (`zr_env_escape`: a Proc made from one of its blocks, a Binding, an eval) copies it to a cell, its parents first, points the image's `slots` at the cell's and keeps the cell in the frame's env slot, so the frame and its blocks read and write the cell from then on and a second keeper gets the same cell. A toplevel, class body or eval keeps a heap Env from its prologue. Keywords travel by the task's `kw` word, set right before the send: `k: v` pairs with plain Symbol keys go as trailing arguments under a static table of the keys (the count, then the ids; one table per key list), and a def declaring keywords reads them by column through its own shape cell, filled once per table after the missing/unknown checks (`zr_kw_shape`); any other keywords go as one flagged Hash (the word 1). A def declaring no keywords makes a table's values one Hash argument (`zr_kw_undeclared`), and `zr_invoke` does the same before a builtin, an accessor or a `method_missing` (`zr_kw_tab_in`), so those see only the Hash form. A block literal is a Proc's image written into a slot of the record of the send that carries it (`make_block`), flagged `FL_STACK` and marked already, so the collector reads nothing through it: what it names, the frame roots. It becomes an `RProc` cell only where a kernel def keeps it past the call (`zr_block_proc`: a `&b` parameter, `proc`/`lambda`/`Proc.new`, a Binding, a Fiber, a Hash default, an at_exit hook, a `define_method` body), and its own block with it, so no cell ever points into a stack. A frame gives its serial when it makes a block, so a descriptor's frame is told from a later frame at the same address as a Proc's is.

Heap. One cell size, 128 bytes, in arenas of 32,768 cells (4 MiB) aligned to their own size, so a cell's arena is its address with the low bits cleared; the arena's exivar slots follow its cells; a malloc'd table lists the arenas and doubles when full, so the heap has no ceiling but the machine's. A free list threads the free cells; `zr_alloc` takes the head and zeroes the cell. Payload buffers (string bytes, array slots, hash entries, env slots) come from malloc and are freed by the sweep (`zr_release`), so a `Ptr` derived from a rooted `Value` stays valid until a mutation reallocates it. The header carries the mark bit (`FL_MARK`) and `FL_ALLOCATED`; there is no side bitmap, no size class, no large-object space and no `PERMANENT` set: class objects and frozen literals are ordinary cells, marked from the globals at every collection.

Collection runs only inside an allocation: when the free list is empty, when the malloc'd payload held passes its limit, at `GC.start`, or at every allocation under `ZR_GC_STRESS=1`. `zr_xmalloc` counts the bytes asked for into `Heap.malloced` and `zr_xfree` takes the block's own size off (`zr_os_malloc_size`), stopping at zero, so the count runs under the payload held; the limit is 64 MiB or twice the payload found live after a collection. `zr_collect` marks from the roots (every task's frame chain, the kernel root frames, the globals, the constant and symbol tables, the finalizer queue, a suspended fiber's chain through its Fiber), drains an explicit mark stack, prunes the weak tables, sweeps every arena eagerly, and grows the heap to twice what the sweep found live and one arena more, so a small program runs a while between collections that each mark the runtime's own objects again. A freed cell is poisoned and loses `FL_ALLOCATED`; marking aborts on a reference to one, which is the invariant that matters: no live object points at a freed one. Under stress the free list starts just past the last cell handed out, so a stale pointer meets the poison, not a reused cell. A finalizer runs at `GC.start` and at the next preemption poll after any other collection, never inside the sweep. `object_id` is handed out on first request and kept with the object.

### 8.7 Values, headers, ivars

CRuby's tagging: fixnum `...1`, flonum `...10` (CRuby's rotation, so `1.0.equal?(1.0)` matches), `false = 0`, `nil = 8`, `true = 0x14`, `undef = 0x34`, static symbols `id << 8 | 0x0c`, heap pointers 8-aligned and nonzero. Chosen because flonum identity and `nil.object_id == 8` are observable. Header: 16 bytes `{flags, klass}` (RBasic): the type in the low five bits, then `FL_ALLOCATED`, `FL_MARK`, `FL_EXIVAR`, `FL_FREEZE`, `FL_SINGLETON`, the string and hash flags, and the encoding index in bits 24..31. An operator site tests its operands inline: two fixnums take the integer path; a flonum with a flonum or a fixnum takes the double path (`float_path`: `zr_float_value`'s rotation, the f64 instruction, `zr_float_new`'s rotation back, a cell for a double the rotation cannot carry; a comparison exact, so a fixnum past 2^53 takes the call), under both Integer's and Float's gates (`GATE_*`, `GATE_FLO_*`), which a redefinition closes for good. A sum, difference or comparison with an Integer literal has no double path: those count and index.

Instance variables are a linear table per object, `RObject{basic, iv: IvTab{rows, len, cap}}` of `(id, value)` rows: the first five in the cell after the table, the rest malloc'd once the table grows past them (a release or a copy frees only those); a non-`T_OBJECT` keeps its ivars in the arena's exivar slot. There are no shapes: an ivar site's cell holds a guess of the row's index, checked against the row's id on every use, inline at the site for a plain object, class or module read outside a ractor (`guessed_ivar_row`), and in the kernel for the rest. Strings are `{len, capa, ptr}` with the encoding in the flags, the bytes in the cell after the header while they fit `STR_EMBED_CAPA` (87) and in a malloc'd buffer of `capa` + 1 bytes past that (`FL_EMBED`), `ptr` reaching them either way so a reader never asks which; Arrays `{len, capa, ptr, base}` (`base` lets `shift` move the start, and `pop`, `shift`, `unshift` and `reverse!` are builtins); Enumerable's methods read one value per element through `zr_enum_each`, a stack Proc handed to `each` that packs what each yields as `rb_enum_values_pack` does; Hashes keep an insertion-ordered entry array `(key, value, live, hash)` and open-addressed bins over it once the table holds more than eight entries (a smaller one is scanned by code), with FNV-1a for String keys, seeded per process at boot so `String#hash` differs from run to run as ruby's does. Sorting is a port of CRuby's `ruby_qsort`, so tied orders match.

### 8.8 Dispatch and signals

Dispatch. A class carries its method table as rows `(mid, entry)` in `ClassExt.mtab`, scanned linearly; its constant table has an open-addressed index (`cidx`/`cbins`). A method entry is `MEntry{mid, fn, arity, kind, meta, cref, vis, orig, from, core, ivar}` (88 bytes: a Method's cell embeds one): `kind` says compiled def, builtin, attr reader or writer, Struct member reader or writer, alias, `define_method` body or a `method_missing` stand-in. An accessor's `fn` is its ivar id and a Struct accessor's the member's index, with the row guess for the ivar (a struct's hidden `__values__` Array) in `ivar`; a `define_method` body's `cref` is its Proc, and `ivar` the eval cref the first call makes (owner as definee, naming the entry for `super`, a trace and a `break`). A call of a `define_method` body allocates nothing: `zr_bmethod_call` writes the Proc's image to its own stack with the receiver as self, flagged a stack's, and the block the call was given goes to the body as its own block, kept in its frame's `defined` slot. Struct and Data accessors are those entries (rt/kernel/struct.rb), with no frame: the arity error is the caller's and a trace sees a C call. A send site in compiled Ruby owns four `CallCache{klass, stamp, entry, found, fn}` cells in `.bss` (`CALL_WAYS`): the first the site tests itself, the rest the kernel tests when the first misses, filling the first empty or stale one, else the last. Each is keyed on the receiver's class and one global method stamp; `zr_methods_changed` moves the stamp on every change to any method table or ancestor chain, and on every collection that frees a class, iclass or cref (an address can come back as another). The site tests the cell itself: a fixnum's class is Integer, a flonum's Float at a site named as numeric code names a Float, a heap object's is in its header, and when the class is the cell's and the cell's stamp is the site stamp (the method stamp's shadow, -1 under `ZR_MCACHE=0` or `verify`) it calls `cell.fn` with `(recv, argc, argv, entry, blk, found)`, the callee checking its own arity; `fn` is a compiled def itself, an accessor's own function, `zr_builtin_fn` for a builtin (the dispatch's steps for a builtin alone), or `zr_invoke_fn` for any other kind. Anything else is `zr_send_cached`, which asks the cell (`zr_call_cache_hit`), else the global cache `(class, mid)`, else walks the ancestors, applies refinements, boxes and visibility, else `method_missing`, and fills the cell. A site under `using` always asks the kernel; a dispatch clears the activation when it returns. Constant sites hold `ConstCache{key, stamp, value}` on the constant stamp, tested at the site; ivar sites hold the row guess, and the first assignment of a plain object's ivar appends its row in one kernel step. `not` and `!` answer inline for nil, true and false while none of their classes redefines `!` (`GATE_NOT`); any other receiver sends through a cell of its own. The fixnum fast paths (`+ - * < <= > >= ==`, `[]`) stay inline in emitted code behind a gate word in `.bss` that a redefinition of the operator on a core class sets. A `when` value sends `===` through a cell of its own with no visibility rule; `recv[i]`, `recv[i] = v` and `recv << v` test the receiver's class inline and take the kernel's fast entry for the core Array, Hash or String, else a cell. A `super` site owns a `SuperCache{node, mid, stamp, entry, found, fn}` keyed on the chain node it runs from and the name; a super under `using` resolves under the refinements of its scope, and a refinement answers at its own place in the chain, after a subclass's own method. `Symbol#to_proc` answers one lambda per symbol from a rooted table. `ZR_MCACHE=0` fills no cell and `ZR_MCACHE=verify` checks every hit against a fresh lookup (a core send's own entry is left out of the cell under verification).

Signals. A compiled function answers `Value`; `undef` (0x34) means a signal is pending in `Task.pending` with its kind in `Task.pending_kind`: `PENDING_RAISE`, `PENDING_BREAK`, `PENDING_RETURN` or `PENDING_THROW`, a `Kill` travelling as a raise. After a fallible call the site tests `undef` and takes the function's landing block. A home is `(record address, serial)`; a catch walks the current task's chain for it, so a dead or foreign-task home raises `LocalJumpError` at the proc call. `rescue` reads the kind and takes the exception; `ensure` saves the pending signal into a record slot, runs, then restores it unless the ensure body raised. `throw` first checks the task's list of catch tags and raises `UncaughtThrowError` at the throw site. Kernel loops propagate `QUNDEF` at once; a backtrace is captured from the frame chain at raise time. Preemption: a poll word in `.bss` beside the task word (`zr_poll_slot`) that every safe point reads -- a loop back edge, a `next` or `redo`, and a method's entry in a program's compiled Ruby (never in the runtime's own, whose scheduler and waits live there), and every kernel `zr_yield` -- set by a timer thread every 100 ms once a second thread started, by a caught signal, and by a collection that queued a finalizer; when set, `zr_preempt_expired` clears it, runs the signal handlers and the queued finalizers, and hands the turn to the thread scheduler when a second thread has armed it. Under wasm, which has no timer thread, the safe points count down a `.bss` word instead and the kernel runs at zero.

### 8.9 Tasks, scheduling, ractors

Model. Ruby's own definition: Thread is concurrency, Ractor is parallelism. Per ractor: one Ruby-running OS thread, a run queue of tasks, a kqueue (darwin) or `poll_oneoff` (wasm) loop, a wakeup fd, a timer. Only one task runs per ractor, so every builtin is atomic by construction and no lock exists on the Ruby path.

A task owns: a machine stack (mmap with a guard page), the frame-chain head and record serial, the pending signal, the `$!` stack, catch tags, fiber-locals and thread-locals (two tables), the cref and eval-home stacks, the `super` resume state, recursion guards, pending interrupt bits, the stack limit. The `Ec` bundle in `crates/zeo-rt/src/ec.rs` is the inventory to carry over; `$~`/`$_` move into the frame record.

Preemption. A detached timer thread stores into each ractor's poll word every 100 ms (CRuby's quantum). Compiled code polls the word at loop back-edges and method entry (one load plus a branch, as `zeo_rt_pending_interrupts` is polled today); the slow path switches tasks on the task's own stack. Kernel code never polls; it is preempted only when it calls back into Ruby, so it re-reads lengths and pointers after every callback (CRuby's C-method discipline; the `Ptr` rule in 8.5 enforces the intra-function half).

Stack switch. `zr_switch(from, to)`: `stp x19..x28, x29, x30` and `d8..d15` into `from`, save `sp`; load the same from `to`; `ret`. A new stack starts with `x30 = zr_task_entry`, `sp = top`. About 26 words, assembled by the 8.4 encoder, delivered as an `Obj::Function` with no relocations. The scheduler swaps the task bundle before calling it.

Blocking. `Mutex`, `Queue`, `ConditionVariable`, `Thread#join`, `sleep` park and unpark on the scheduler; deadlock detection is "every task parked" and prints CRuby's message. Sockets go non-blocking on kqueue. Calls that cannot be async (`read` on files and pipes, `waitpid`, `getaddrinfo`, `system`, `flock`, `fsync`, `blocking: true` FFI) go to a small pool of helper OS threads that never touch Ruby objects, only buffers: the task parks, the helper completes and posts to the wakeup fd, the task requeues. This pool is the correctness floor for `test/core/thread`, `io`, `timeout`, `open3`, `socket` and ships in the first threaded milestone. Stack overflow: a prologue `sp < limit` check (a depth counter on wasm) as an IR op, raising `SystemStackError` before the record is linked. Thread kill and process exit deliver `Kill` (skips `rescue`, runs `ensure`); an unreachable suspended fiber is simply swept, as CRuby runs no `ensure` there. Signals: `sigaction` handlers are kernel functions that only set a flag; trap procs run at the main ractor's next safepoint.

Ractors. `Ractor.new` starts an OS thread with its own heap and scheduler. Messages copy deeply into the receiver's heap; `move` copies then poisons the source. `Ractor.make_shareable` deep-freezes and sets `SHARED` on every node in place, so identity is preserved as in CRuby; a ractor's private collection never frees or scans into `SHARED` objects (sound because shareable objects reference only shareable objects); on ractor exit, pages holding a `SHARED` object move to the global pool; `SHARED` objects are reclaimed only by a global collection at a rendezvous. Classes, modules, dynamic symbols and interned frozen strings are always allocated in the global pool. The rendezvous reuses the poll word: every ractor parks at its next safepoint (a ractor in a helper call is already parked); it is required for shared reclamation, ancestry mutation (a `super` walk may be running elsewhere), `ObjectSpace.each_object`, and process exit. Non-main ractors get `Ractor::IsolationError` on global and class-ivar writes; `$stdout` and friends are ractor-local. `fork` keeps the current task only.

### 8.10 The eval road

An eval-capable program links the compiler (`libze0.a`, ze0 compiled natively) and `Obj::JIT`. `zr_eval(src, binding, cref, file, line)` lowers with every static decision off (the eight traps in `zeo-eval-compiler` apply: hoisted defs, caller locals as env slots, run-time definee, cref chain as values, fresh id bases above the program's), emits IR, and runs `IR::Arm64` and `Obj::JIT`. Cached by `(src, scope names, cref, mode)`. Whether a program can eval is a HIR fact (`Eval` reachable, `instance_eval(str)`, `Binding#eval`, a surviving `require`), and it decides the link line. The compiler is lowered once per runtime digest and road files into an object of its own (`Zr::Road`, `road-*.o` in the cache), and a program that evals links it beside the runtime's object, so its own build lowers only itself. A `require` whose name is computed, or whose literal name no root holds, runs `Kernel#require` when the program runs: it searches `$LOAD_PATH` and then the compile-time roots, runs the compiled toplevel of a file the program holds (`zr_unit_table`), and compiles any other file then.

### 8.11 Corelib mode

`rt/core/*.rb` is ordinary Ruby, one file per class, compiled once into `libzr.a` in a mode that: resolves `Primitive.zr_str_bytesize(self)` to a direct kernel call; honours `Primitive.attr! :leaf` (no frame record); registers every `def` as a builtin row with arity and `Method#parameters` from its signature; emits those rows as data (8.13). This is CRuby's own approach for `array.rb`, `kernel.rb` and `numeric.rb`. Hot primitives (string bytes, array storage, hash lookup, fixnum and flonum arithmetic, `to_s`, `sort`) are kernel functions; semantics live in Ruby.

### 8.12 Boot and the program description

Per class a static `zr_class` in `.data`: RBasic header with `PERMANENT`, name symbol, superclass relocation, a static sorted `(symbol_id, method_entry*)` array (binary search; the first runtime `def` copies it to a heap table, copy-on-write), static constants, the root shape and known ivar transitions, per-feature row lists for `require`-gated builtins. Corelib symbol, class and shape ids are fixed when `libzr.a` is built; a program's ids start after them, carried in its sidecar as `first_program_sym`, `first_program_class`, `first_program_shape`, the way `first_user_class` is today. `zr_main(argc, argv, desc)` in kernel Ruby: create the main ractor, heap and task; link parent and child lists; zero the site words; apply the program's rows; intern symbols; run the toplevel, `at_exit` handlers, finalizers, flush; exit status per `capi/lifecycle.rs:66`.

### 8.13 The wasm emitter (`IR::Wasm`)

Block params become locals with parallel copies at edges; control flow is structurized with Ramsey's Beyond Relooper (the bring-up hack: one `loop` + `br_table` over a block-index local); i64 ops map 1:1; addressable slots become a bump region in a linear-memory shadow stack; `symbol_value` and `func_addr` become data offsets and table indices; `call_indirect` uses a typed table. LEB128 and canonical section order; signed LEB128 is the classic bug, test it first. Milestone 1 is wasm32: `Value` stays i64 with a 32-bit pointer payload (CRuby's wasm build does this), because prism and openssl have wasm32 toolchain ports today (zlib and the regexp engine are Ruby since 2026-09-16) and wasi-libc for wasm64 is incomplete; the IR keeps wasm64 open. Stack switching (milestone 2): an Asyncify-style unwind/rewind transform for every function that can be on the stack at a switch; with dynamic dispatch that is nearly every function, so about 2 to 3x code size and roughly half the speed on wasm, and no rewind through host frames. Swap to wasmtime's stack-switching proposal when it lowers on aarch64 hosts: a wasm feature we adopt, not an upstream change we make.

## 9. Verification

Command surface: `ze0 test [dirs | --all] [--gc plain|stress|verify] [--show N]`, buckets `skipped / refused / backend / matched / diverged / crashed / timeout`; `ze0 check [<file>...]`, a process per check file and per shard a file declares, `ZE0_JOBS` at a time; `ze0 stage1` (Part A), `ze0 stage2` (Part E).

- **The oracle is ruby, only:** the recording under `__END__` (ruby 4.0.6, never re-run) for every corpus program; a live `ruby` where a check must write its own program (the DATA check). Nothing is compared against the Rust emitter or runtime.
- **Byte identity, the refactor oracle:** `test/goldens/`, `test/snapshots/` and `stage1` after A2, A2b and every IR change.
- **Corpus:** `ze0 test <dirs>` after every slice; `--all` at Part gates; per-directory match rates monotone under the allowlist. Only `diverged`, `crashed` and `timeout` are defects. Never a corpus-wide census in one process (`zeo-no-mass-census`).
- **The roads, per program:** (a) the recording; (b) the binary, in three GC columns (Part B and C); (c) `--emit wasm` (Part D). Compare stdout, normalized stderr, exit status.
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
| A `Value` in a register across an allocating call | use-after-free | the 8.5 effect rules are compiler errors; `ZR_GC_STRESS` (collect every allocation, reuse freed cells last) on the whole corpus in CI; poisoned cells and a mark-time abort, proven by C0.3's deliberately broken program |
| A kernel loop leaves an object poisoned on the `Qundef` path (`iter_lev`, temp locks) | permanent errors | `defer { }` is the only cleanup form; an early `return Qundef` outside it is refused |
| A blocking syscall stalls a whole ractor | `thread`, `io`, `timeout` divergences | the helper pool ships in the first threaded milestone, before kqueue readiness |
| Compiled-Ruby corelib too slow (the 8x finding) | priority 3 | tagged words, no refcounts, inline caches, kernel primitives for hot paths; measured at C5; Part F |
| Green threads change observable scheduling | thread goldens | CRuby also interleaves at safepoints with a 100 ms quantum; the goldens are CRuby's |
| Stage 2 differs | bootstrap unsound | the E2 guard list; `ruby_qsort` port; counter `object_id`; one prism tree |
| Backend miscompiles are silent | wrong answers, crashes | `IR::Interp` over the same IR; per-op disassembly snapshots against the `aarch64` gem |
| Spill-everything code is slow | perf, and the GC-stress column | linear scan (B4, done 2026-09-12): 2.7x on a compute benchmark |
| Mach-O writer errors surface late | lost time | parse the `.o` back before linking (`nm`, `otool`) |
| Asyncify tax on wasm | wasm speed and size | wasm is the second target; milestone 1 is single-task; adopt the stack-switching proposal when it reaches aarch64 hosts |
| Encoding tables and Onigmo encoders past UTF-8 and ASCII | divergences | port the generators, not the tables; `tools/regexp_diff.rb` counts the cases that need another encoder as unported |
| No second opinion on machine code | a miscompile reads as a wrong answer | `IR::Interp` over the IR, per-op disassembly snapshots against the `aarch64` gem, and the corpus against ruby's recordings |
| `lower.rb` at 7.5K lines in one class | velocity | A2 and A2b split it into HIR build, analyses and per-family lowerings |
| A refactor of the lowering goes unchecked | silent divergence | `test/hir/` dumps, `stage1` over the object bytes, and `test/zr`, `test/rt`, `test/programs` against ruby |
| One backend, and it allocates ten registers | code slower than a real allocator would write | perf is never a gate; every number goes in the commit that earns it |

## 11. Non-goals

Linux and x86-64 (seams kept: target triple, pointer width, `sys_*.rb`, object format, the stub table; nothing verified there, per the standing macOS-only rule); Windows; a moving or generational collector (precise roots keep it possible); an interpreter or bytecode tier (the contract stays "compiled, CRuby-identical or refused"); the C API before Part G; wasm64 and WASI 0.2 before milestone 2; reading clang objects and `ar` archives, which is what would let `Obj::Exe` link a program that reaches the vendored C; ripper and `callcc`, which stay declined as today.

## 12. Toolchain, layout, ownership

Stage-0 host: CRuby 4.0.6 (`.ruby-version`, the oracle). Gems used by the compiler under CRuby: prism, `aarch64` (or our own encoder table), `jit_buffer`-style Fiddle calls for `Obj::JIT`. Vendored C (prism; zlib and Onigmo are Ruby ports since 2026-09-16) built by `ze0 deps build` with `cc`. Apple tools: `cc` (required, to compile the vendored C and to link a program that reaches it), `ld` through it, `ar` for the vendored archives, `otool`/`nm` (dev-only checks). `Obj::Exe` links everything else. wasmtime for Part D. The README names every one.

Layout of `~/dev/ze0` as one RubyGem (2026-09-14; the README's Layout section is the file-by-file map):

```
ze0.gemspec, Gemfile, Rakefile   the gem: a ruby-platform gem, require path lib/ only
exe/ze0                          the gem's CLI; lib/ze0/cli.rb holds run, build, machine, deps, version
bin/ze0                          the checkout's CLI: the gem's commands, plus test, bench, check, stage1, stage2
ext/ze0/extconf.rb               builds the vendored C into vendor/build/<target>/ as the gem installs
lib/ze0.rb, lib/ze0/version.rb   the entry
lib/ze0/paths.rb                 root, rt, vendor, build and cache directories, named once
lib/ze0/target.rb                the targets ze0 emits, and what this host can build
lib/ze0/{hir,zr,machine,ir}/     the compiler's front and middle
lib/ze0/backend/{aarch64,wasm}/  the backends, under one Backend::Refused
lib/ze0/obj/macho/, obj/elf/     the object writers; native/link/{darwin,static}.rb the linkers
lib/ze0/harness/                 the test-file format and the corpus sweep (repository only)
rt/{kernel,core,ext}/            the runtime; beside lib/, never on a load path
rt/{kernel,core,ext}/os/<os>/    the runtime's OS layer; rt/kernel/os.rb names its calls
rt/kernel/arch/<arch>/           the runtime's machine layer
vendor/c, vendor/ext, vendor/lib the vendored C, extension gems' Ruby halves, ruby's stdlib
tools/, test/, docs/             repository only
```

Targets. The gem platform is the host the compiler runs on; a target is what ze0 emits. `Ze0::Target` names each triple, and picks its backend, object writer, linker and runtime layer. aarch64-apple-darwin builds all of them today. aarch64-linux-musl links a static binary with its host's `cc`, or with a cross toolchain named by the triple (`aarch64-linux-musl-gcc`, `Target#tool`), and has its own layer over musl: plain three-argument `fcntl`, `ioctl` and `open` (AAPCS64 on Linux passes a variadic argument in a register), poll(2) for the waits, and the program on a mapped stack of `Native::Link::STACK` bytes, since RLIMIT_STACK bounds the main thread's. A static binary has no dynamic symbols, so eval's loader and ffi refuse by name there. wasm32-wasi has its own layer: `rt/kernel/os/wasi/` answers the libc calls the portable kernel imports over WASI preview 1 (`Machine.import ..., from: "wasi_snapshot_preview1"`), and the wasm backend owns only a floor of memory, write and exit. The table tools (`tools/{errno,fcntl,etc,socket}.rb`) write the layer of the ruby that runs them, so each OS's tables come from that OS's ruby: ruby.wasm under wasmtime for wasi.

Parallel ownership for worktrees (`parallelize` skill): A owns `lib/ze0/cli/`, `lib/ze0/hir/`, `lib/ze0/ir/` (core); B owns `lib/ze0/ir/arm64/`, `lib/ze0/obj/`, `rt/spike/`; C owns `rt/`, `lib/ze0/machine/`, `lib/ze0/hir/lower_zr/`; D owns `lib/ze0/ir/wasm*`, `rt/kernel/sys_wasi.rb`.

Working rules that apply throughout (from the repo's memory): small focused commits with plain-English bodies; targeted tests per commit, the full gate at Part boundaries; one Bash, one intent, never two test suites at once; no corpus-wide census in one process; a gap file carries no analysis; a divergence is CRuby-identical or FAIL, never a silent drop; perf numbers in the commit that earns them.

## 13. What to do first

1. Part 0, the split: DONE 2026-09-08.
2. A1 (`stage1`) and A3 (hand-written IR against libSystem) in parallel: the refactor oracle and the first native light, both cheap.
3. A2 then A2b, each verified byte for byte.
4. B0 and B1 as soon as A2 lands: the Ruby backend on kernel programs. Then B2, the pure `fib`, which fixes the shape of the kernel dialect.
5. C0.1 to C0.4 beside B1; C1 and C2 next, with the `zr` lowering; `puts 1` through `zr` is M0 and the first corpus light.
6. A4, B3 to B6, C3 onward in parallel worktrees per section 12; archive the legacy lowering when M1 passes.
7. Report at each Part gate with the corpus numbers before the next Part starts.

## 14. Glossary

- **Value:** a 64-bit tagged word (8.7). **Qundef:** the `0x34` sentinel meaning "signal pending" (8.8).
- **Record / frame record:** the per-function shadow-stack entry the GC scans (8.6). **Home:** `(record, serial)` a `break` or `return` targets.
- **Task:** a green thread or fiber with its own machine stack (8.10). **Rendezvous:** every ractor parked at a safepoint.
- **High tier / low tier:** Ruby-level IR ops vs machine ops (8.2). **Legalize:** the per-target rewrite from high to low.
- **Obj:** the backend-neutral object model (8.3).
- **Kernel dialect / `Machine`:** the runtime's typed subset of Ruby (8.5). **Corelib mode:** ordinary Ruby compiled with `Primitive` access (8.12).
- **Ladder:** the ordered corpus directories that gate Parts C and D (section 7).

## 15. References

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
