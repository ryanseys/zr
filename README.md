# ze0: a Ruby front end for zeo's backend

ze0 is a Ruby program that compiles a subset of Ruby to the same Cranelift
IR zeo's Rust emitter produces, as text, and hands it to `zeo backend` to
link. It is about a thousand lines of Ruby and runs three ways: under ruby,
under zeo's JIT, and as a native binary zeo built from it (stage 1). All
three write the same bytes.

The spike asks one question: what does a front end written in Ruby cost,
on zeo's own backend, and what would it take for that front end to compile
itself?

```console
$ ruby ze0/ze0.rb test/ze0/fib.rb -o fib.clif      # or: zeo ze0/ze0.rb ...
$ zeo backend fib.clif -o fib                       # reads fib.zeodata beside it
$ ./fib
6765
$ zeo build ze0/ze0.rb -o ze0                       # stage 1
$ ./ze0 test/ze0/fib.rb -o fib.clif                # the same bytes
```

## The subset

Integer, Float, String, Symbol, `nil`, `true`, `false`; local variables;
`+`, `-`, `*` and the six comparisons with an inline Integer fast path;
`if`/`unless`/`elsif`/`else`, `while`/`until`; top-level `def` with
required parameters; `return`; `puts`; and every other call as the
runtime's cached dynamic send, so `"ab".upcase`, `7 / 0` and `10.gcd(4)`
all answer as ruby does, raise as ruby does, and print ruby's backtrace.

Anything else is refused by name at its line (`Ze0::Unsupported`). The
contract is zeo's: identical to CRuby, or fail.

## Layout

| file | what |
|---|---|
| `ze0.rb` | the command line |
| `lib/ze0/lower.rb` | Prism nodes to CLIF: functions, statements, expressions, ownership |
| `lib/ze0/clif.rb` | a function under construction: slots, symbols, callees, blocks, SSA values |
| `lib/ze0/emit.rb` | the program: rodata, the symbol pool, call sites, `def` rows, the two files |
| `lib/ze0/capi.rb` | the runtime rows the subset calls, transcribed from `clif/capi_names.rs` |
| `lib/ze0/names.rb` | symbol spellings, matching `names.rs` |
| `lib/ze0/json.rb` | a JSON writer, so stage 1 needs no `require "json"` |
| `measure.rb` | the numbers below, taken again |

## What the text says, and what the sidecar says

The `.clif` carries code only: `zeo_toplevel`, one body and one trampoline
per `def`, each calling the runtime by name (`%zeo_rt_frame_enter`) and
naming the program's data by symbol (`%zeo_rodata`, `%zeo_syms`,
`%zeo_callsites`). The `.zeodata` beside it carries what code cannot: the
rodata bytes the offsets index, the interned symbols in slot order, the
call-site count, each `def`'s dispatch and reflection row, and two words,
`@all` for the class tables and `@boot` for the registration rows every
program starts with. `crates/zeo/src/backend/sidecar.rs` is the schema.

ze0 writes the emitter's *outlined* form: a frame's enter and pop, a
line stamp, the release pool's mark and reset, and every dispatch are
calls into the runtime rather than inline loads and stores through the
frame header. That is a third of the text of the inline form and the same
semantics. Ownership follows the emitter's rule: a temporary the code owns
is either moved (into a local, a return, the out slot) or handed to the
pool before it is borrowed; a local's value is only ever borrowed, and
retained when moved. The corpus runs under `ZEO_RT_LEAKCHECK=1` on every
road.

## The differential

`test/ze0/` holds 21 programs, recorded against ruby 4.0.6 like every
other golden (`cargo xtask bless ze0::`). For each, `crates/zeo/tests/corpus/ze0.rs` takes
three roads and demands one answer:

1. `zeo build`, the Rust emitter, against ruby's recording;
2. ze0 under zeo's JIT, then `zeo backend`;
3. stage 1, whose text and sidecar must equal road 2's byte for byte,
   then `zeo backend`.

The three binaries must agree on stdout, stderr and the exit status.
`cargo nextest run -p zeo --test corpus -E 'test(ze0::)'` runs it; the
stage-1 binary is built once beside `zeo`, keyed by the sources, and shared
through a lock file. `crates/zeo/tests/suite/checks/ze0_clif.rs` pins ze0's text for `hello` and
`fib` as snapshots.

## Measurements

Release `zeo`, 2026-09-02, Apple Silicon. Best of three; the "cold" JIT
column is one run with the program cache off (`ZEO_CACHE=0`), which is what
the first `zeo ze0/ze0.rb` on a machine pays to compile ze0 and prism's
Ruby half. The Rust front end column is `parse_lower + analyze` from
`ZEO_TIMINGS=1`, which the boot prelude dominates. Text sizes compare
ze0's output with `--emit-clif` under `ZEO_DEBUG=outline-frames`; the
emitter's text also carries `main` and `zeo_unit_init`, which the backend
materialises for ze0.

| program | lines | rust front end ms | ze0 jit cold ms | ze0 jit warm ms | ze0 stage1 ms | backend ms | emitter text bytes | ze0 text bytes |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| ackermann | 11 | 17 | 801 | 21 | 13 | 135 | 25869 | 21620 |
| arithmetic | 8 | 16 | 758 | 21 | 12 | 143 | 22407 | 21632 |
| collatz | 15 | 16 | 787 | 21 | 13 | 136 | 30202 | 23371 |
| compare_chains | 11 | 16 | 750 | 20 | 13 | 137 | 33301 | 29949 |
| def_reflection | 7 | 17 | 759 | 19 | 12 | 133 | 19552 | 15929 |
| division_by_zero | 2 | 17 | 774 | 18 | 10 | 136 | 8694 | 5232 |
| fib | 8 | 17 | 830 | 22 | 13 | 139 | 19282 | 14384 |
| float_mix | 9 | 18 | 786 | 22 | 13 | 134 | 35236 | 20966 |
| generic_sends | 13 | 17 | 784 | 20 | 13 | 137 | 25677 | 24352 |
| hello | 1 | 20 | 793 | 17 | 9 | 129 | 4073 | 2406 |
| if_elsif_else | 20 | 15 | 761 | 22 | 14 | 136 | 27601 | 30487 |
| locals_and_assignment | 19 | 15 | 750 | 20 | 13 | 135 | 25588 | 25090 |
| nested_conditions | 22 | 17 | 790 | 23 | 14 | 143 | 26088 | 21963 |
| overflow_to_bignum | 5 | 17 | 802 | 21 | 11 | 139 | 19605 | 15659 |
| p_of_immediates | 12 | 23 | 772 | 19 | 11 | 155 | 15521 | 15906 |
| return_inside_while | 21 | 17 | 757 | 23 | 14 | 147 | 34042 | 29379 |
| string_methods | 11 | 19 | 792 | 22 | 14 | 148 | 26430 | 22562 |
| tak | 8 | 16 | 777 | 20 | 12 | 134 | 22965 | 17768 |
| unless_and_until | 15 | 15 | 753 | 20 | 12 | 133 | 20743 | 19721 |
| while_sum | 16 | 15 | 744 | 20 | 12 | 133 | 27423 | 23386 |
| wrong_arity | 5 | 18 | 856 | 18 | 10 | 139 | 14302 | 10368 |
| generated_50 | 52 | 15 | 770 | 30 | 22 | 141 | 96293 | 86827 |
| generated_200 | 208 | 16 | 805 | 67 | 59 | 146 | 375132 | 346764 |
| generated_500 | 507 | 17 | 940 | 140 | 132 | 164 | 913965 | 847877 |

What the numbers say:

- **A warm ze0 is as fast as the Rust front end on small programs** and a
  native ze0 is faster: 9 to 14 ms against 15 to 20 ms, because the Rust
  path analyses the boot prelude on every compile and ze0 analyses only
  the program. On the 500-line program the native ze0 takes 132 ms and
  the warm JIT 140 ms, so ze0's own cost is about 0.25 ms per line.
- **The cold JIT costs three quarters of a second**, all of it compiling
  ze0 and prism's Ruby half. The program cache makes every later run
  warm, and the differential harness warms it once before the corpus.
- **`zeo backend` takes about 135 ms flat**, most of it the compile of the
  empty program that gives `@boot` and `@seed` their meaning, then
  Cranelift and the link.
- **ze0's text is 10 to 30 percent smaller** than the emitter's outlined
  text for the same program, with `main` and `zeo_unit_init` left to the
  backend and no `TOPLEVEL_BINDING` install.
- **A ze0 binary is twice the size.** `puts 1` links to 14.4 MB from ze0
  and 7.3 MB from `zeo build`, because ze0 keeps every builtin class
  table (`@all`): with no reachability analysis and a dynamic send that
  can reach any class, that is the honest choice. The emitter's analysis
  keeps 33 tables for that program.
- **Lines.** ze0 is 1,022 lines of Ruby. The emitter's `clif/` is 27,785
  lines of Rust, of which the files the subset's lowering lives in
  (`binop`, `body`, `params`, `stmt`, `expr`, `call`, `frames`, `ctx`,
  `operand`, `ownership`, `control`, `consts`) are 11,695; a per-function
  attribution was not done, and those files lower far more than the
  subset. The backend verb and the sidecar are 759 lines of Rust.

## What the spike found

- **zeo's inline `/` and `%` raised `ZeroDivisionError` from the caller's
  frame.** Ruby's backtrace names `Integer#/`; the corpus program
  `division_by_zero.rb` failed road 1 against ruby's recording. The
  inline path now pushes the synthetic C frame around the raise
  (`clif/binop.rs`). ze0's own road had matched ruby all along, because it
  sends `/` to the runtime.
- **The seed class tables are not enough for a front end without
  reachability analysis.** `method(:twice)` reaches `Method`, which the
  empty program never keeps, and the runtime aborts on a missing table by
  design. The sidecar gained `@all`.
- **Prism's Ruby half runs under zeo unchanged**, and ze0 runs identically
  under ruby, under zeo's JIT and as a native binary: the text is
  byte-for-byte the same on 24 programs.

## Stage 2

Stage 2 is ze0 compiling `ze0.rb`. Its own sources and prism's Ruby half
(about 30,000 lines) use classes and modules, blocks and closures, `Hash`,
`Array` and `String` with their iterators, string interpolation and
mutation, constants, `case`, `rescue`, `require`, `attr_reader`,
`Struct`, `format` and `each_with_index`. Lowering those is the rest of
`clif/`, about 25,000 lines of Rust, and a Ruby front end carrying it is
three to six engineer-months of work. The honest milestone this spike
reaches is stage-1 determinism, plus a 500-line program in the subset
compiled by the native ze0 in 132 ms.
