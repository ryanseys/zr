# ze0: a Ruby front end for zeo's backend

ze0 is a Ruby program that compiles a subset of Ruby to the same Cranelift
IR zeo's Rust emitter produces, as text, and hands it to `zeo backend` to
link. It is about 4,600 lines of Ruby and runs four ways: under ruby, under
zeo's JIT, as a native binary zeo built from it (stage 1), and as a native
binary ze0 built from itself (stage 2). All four write the same bytes.

**ze0 compiles itself.** ze0 plus prism's Ruby half is about 44,000 lines,
and ze0 lowers all of it: the binary ze0-under-ruby produces and the binary
that binary produces are byte-identical, 62 MB of CLIF and its sidecar.

```console
$ ruby ze0/ze0.rb test/ze0/fib.rb -o fib.clif      # or: zeo ze0/ze0.rb ...
$ zeo backend fib.clif -o fib                       # reads fib.zeodata beside it
$ ./fib
6765
$ zeo build ze0/ze0.rb -o ze0                       # stage 1, by the Rust emitter
$ ./ze0 test/ze0/fib.rb -o fib.clif                # the same bytes

$ P=crates/zeo-rt/ext/prism/lib                     # stage 2, by ze0 itself
$ ruby ze0/ze0.rb -I $P ze0/ze0.rb -o a.clif && zeo backend a.clif -o ze0_1
$ ./ze0_1 -I $P ze0/ze0.rb -o b.clif
$ cmp a.clif b.clif && cmp a.zeodata b.zeodata      # the fixed point
```

`-I` names a root a plain `require` searches. A feature no root carries is
one the runtime already holds, and the `require` opens its gate where it
stands.

## The subset

Integer, Float, String, Symbol, `nil`, `true`, `false`; string
interpolation; Array, Hash and Range literals; regexp literals; local
variables, `$globals`, `@ivars` and constants, each with `=`, `+=`, `||=`
and `&&=`; multiple assignment in every shape; `+`, `-`, `*` and the six
comparisons with an inline Integer fast path; `&&`, `||`, `!` and the
ternary; `if`/`unless`/`elsif`/`else`, `while`/`until` and their modifier
forms, with `break` and `next` carrying values; `case`/`when`, with or
without a subject; `begin`/`rescue`/`else`/`ensure`, `raise` and `retry`'s
refusal; `defined?`.

`def` and blocks with the whole parameter surface -- optional, rest, post,
keyword, double-splat, block, destructuring and `...` forwarding -- plus
`->() {}`, `_1`/`_2` and `it`; `return`; blocks closing over the names they
read, with `next`, `break`, `yield` and `block_given?`; a splat, a
double-splat and `&block` at a call site.

`class` and `module` with inheritance, instance methods, `def self.x`,
`class << self`, `class << obj`, instance variables, their own constants
and `private_constant`, nested to any depth; `attr_reader` and the other
accessors; `private`, `public`, `protected` and `module_function` in both
their positional and their argument forms; `include`, `extend` and
`prepend`; `alias`; a `def` inside a block, installed on whatever definee
the runtime resolves; `super` in every channel, bare or with arguments,
with a splat or keywords, in a class or a module; a builtin exception or
`BasicObject` as a superclass, and a gated builtin REOPENED after its
`require`.

`require_relative` and `require` resolve at compile time: the target is
parsed and spliced in at the call's position, once per file, and each
file's top level is its own scope. `autoload` names a file that provides a
constant, and the splice follows the constant -- the file goes in where a
statement first reaches it. A `require` no root carries names a feature the
runtime holds, and opens its gate where it stands.

An `if` whose condition a whole-program compile can settle -- `RUBY_ENGINE`,
`RUBY_VERSION` and their comparisons -- leaves only the branch that runs,
so a `def` in the branch written for another engine is never compiled.

`puts` and every other call are the runtime's cached dynamic send, so
`"ab".upcase`, `7 / 0`, `10.gcd(4)`, `x.send(:+, 1)` and `x.method(:to_s)`
all answer as ruby does, raise as ruby does, and print ruby's backtrace.

Anything else is refused by name at its line (`Ze0::Unsupported`). Today
that chiefly means pattern matching (`case`/`in`), `class Foo::Bar`, the
`rescue` modifier, `def obj.method`, a `return` from inside a block, an
`ensure` a jump crosses, class variables, `$1` and `$~`, `for` and `redo`,
a block-local variable, an interpolated regexp or symbol, a computed
`require`, `load` and `eval`. The contract is zeo's: identical to CRuby, or
refused. `ze0/PLAN.md` is the order the rest arrives in.

## Layout

| file | what |
|---|---|
| `ze0.rb` | the command line |
| `lib/ze0/lower.rb` | Prism nodes to CLIF: functions, statements, expressions, ownership |
| `lib/ze0/scope.rb` | one function being lowered: its locals, its `self`, its exits |
| `lib/ze0/params.rb` | a parameter list, in the slot order the binder uses |
| `lib/ze0/clif.rb` | a function under construction: slots, symbols, callees, blocks, SSA values |
| `lib/ze0/emit.rb` | the program: rodata, the symbol pool, call sites, `def` rows, the two files |
| `lib/ze0/capi.rb` | the runtime rows the subset calls, transcribed from `clif/capi_names.rs` |
| `lib/ze0/guards.rb` | the `if` conditions a whole-program compile can decide |
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
program starts with. A program with classes adds a row per class -- its
name, its superclass by NAME and its ivar slots -- and every `def` names
the class it sits on. Ids are assigned when the program is LINKED, after
the last id the empty program reaches, so ze0 never learns one: where its
code needs an id, it reads `zeo_class_ids` the way it reads `zeo_syms` for
an interned symbol. `crates/zeo/src/backend/sidecar.rs` is the schema.

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

`test/ze0/` holds 37 programs, recorded against ruby 4.0.6 like every
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

A golden checks that what compiles is CORRECT. The other half of the
contract -- that what does not compile is refused by NAME, at its line --
has 25 fixtures in `crates/zeo/tests/fixtures/ze0_refused/`, each one form
outside the subset, each asserting the message ze0 prints. Neither test
can do the other's work: a refusal fixture cannot catch a program that
compiles and answers wrongly, which is why every form that joins the
subset gets a golden the same day.

Neither can see the third thing, which is whether ze0 still compiles
ITSELF to the same bytes. `cargo xtask stage2` asks that, and then puts
every `test/ze0/` program through both self-compiled binaries. It is run
on demand: two self-compiles of 45,000 lines cost more than the rest of
the suite together, so it is the verb to reach for after a change a
golden would not notice -- a new lowering, a change to how files are
spliced, anything touching the order of a table.

## Measurements

Release `zeo`, 2026-09-03, Apple Silicon. Best of three; the "cold" JIT
column is one run with the program cache off (`ZEO_CACHE=0`), which is what
the first `zeo ze0/ze0.rb` on a machine pays to compile ze0 and prism's
Ruby half. The Rust front end column is `parse_lower + analyze` from
`ZEO_TIMINGS=1`, which the boot prelude dominates. Text sizes compare
ze0's output with `--emit-clif` under `ZEO_DEBUG=outline-frames`; the
emitter's text also carries `main` and `zeo_unit_init`, which the backend
materialises for ze0.

`ruby ze0/measure.rb` takes the whole table again. Rows are comparable
within a table and not across two of them: the timings move with the
machine and the build, so a column read against an older table says
nothing.

| program | lines | rust front end ms | ze0 jit cold ms | ze0 jit warm ms | ze0 stage1 ms | backend ms | emitter text bytes | ze0 text bytes |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| ackermann | 11 | 32 | 1340 | 30 | 21 | 186 | 25869 | 18359 |
| arithmetic_and_compare | 19 | 31 | 1289 | 43 | 35 | 203 | 51687 | 41384 |
| autoload | 18 | 32 | 1240 | 28 | 17 | 174 | 541629 | 7527 |
| blocks_and_closures | 94 | 33 | 1356 | 119 | 119 | 204 | 291613 | 243722 |
| classes_and_modules | 330 | 34 | 1459 | 236 | 264 | 230 | 534025 | 474395 |
| collatz | 15 | 34 | 1284 | 32 | 22 | 177 | 30202 | 19763 |
| control_flow | 200 | 32 | 1325 | 122 | 125 | 224 | 246410 | 221702 |
| def_reflection | 7 | 31 | 1304 | 30 | 21 | 227 | 19552 | 13644 |
| defined | 58 | 32 | 1336 | 58 | 48 | 193 | 82311 | 76981 |
| destructuring_parameters | 30 | 31 | 1401 | 68 | 60 | 210 | 143280 | 113880 |
| division_by_zero | 2 | 32 | 1303 | 22 | 14 | 164 | 8694 | 4432 |
| ensure | 87 | 25 | 1197 | 51 | 48 | 189 | 103637 | 84284 |
| fib | 8 | 36 | 1263 | 26 | 17 | 166 | 19282 | 12561 |
| float_mix | 9 | 32 | 1294 | 29 | 19 | 179 | 35236 | 17353 |
| generic_sends | 13 | 32 | 1351 | 29 | 21 | 173 | 25677 | 19623 |
| hello | 1 | 34 | 1255 | 21 | 12 | 168 | 4073 | 2194 |
| locals_and_assignment | 19 | 39 | 1289 | 30 | 21 | 168 | 25588 | 20154 |
| loop_control | 96 | 31 | 1306 | 78 | 77 | 233 | 183345 | 157145 |
| mixins | 68 | 32 | 1340 | 63 | 55 | 194 | 99041 | 93980 |
| names_and_case | 74 | 31 | 1345 | 66 | 57 | 192 | 129620 | 102477 |
| nesting_and_assignment | 130 | 32 | 1331 | 117 | 168 | 293 | 248282 | 187358 |
| overflow_to_bignum | 5 | 32 | 1476 | 34 | 21 | 217 | 19605 | 13070 |
| p_of_immediates | 12 | 34 | 1330 | 31 | 19 | 186 | 15521 | 13001 |
| parameters | 112 | 34 | 1531 | 161 | 158 | 271 | 325445 | 277432 |
| reopened_builtin | 40 | 44 | 1367 | 47 | 36 | 180 | 512146 | 54281 |
| require_relative | 44 | 37 | 1368 | 63 | 55 | 236 | 1118352 | 81193 |
| return_inside_while | 21 | 33 | 1326 | 31 | 24 | 177 | 34042 | 25668 |
| runtime_defs | 119 | 38 | 1480 | 125 | 131 | 244 | 207723 | 166922 |
| singleton_class | 72 | 33 | 1344 | 60 | 52 | 181 | 111567 | 108549 |
| splat_arguments | 36 | 35 | 1353 | 50 | 41 | 195 | 79170 | 59660 |
| static_guards | 46 | 31 | 1247 | 41 | 31 | 201 | 36153 | 30029 |
| string_methods | 11 | 30 | 1288 | 32 | 21 | 182 | 26430 | 18306 |
| strings_and_collections | 82 | 32 | 1300 | 87 | 89 | 229 | 164909 | 126351 |
| super_channels | 86 | 31 | 1353 | 82 | 78 | 236 | 134333 | 139613 |
| superclasses | 46 | 34 | 1328 | 52 | 42 | 196 | 63190 | 64572 |
| tak | 8 | 30 | 1284 | 32 | 21 | 186 | 22965 | 15157 |
| wrong_arity | 5 | 31 | 1267 | 25 | 15 | 173 | 14302 | 9219 |
| generated_50 | 52 | 37 | 1338 | 55 | 44 | 186 | 96293 | 73877 |
| generated_200 | 208 | 32 | 1374 | 141 | 157 | 228 | 375132 | 293779 |
| generated_500 | 507 | 34 | 1606 | 406 | 380 | 251 | 913965 | 719559 |

What the numbers say:

- **A native ze0 beats the Rust front end on a small program** -- 12 to 25
  ms against 25 to 44 -- because the Rust path analyses the boot prelude on
  every compile and ze0 analyses only the program. That advantage is a
  fixed cost, not a rate: the Rust column stays flat at about 32 ms from 1
  line to 507, and ze0's grows at roughly 0.75 ms per line, so the two
  cross at about 40 lines and the 500-line program costs ze0 380 ms.
- **The cold JIT costs about 1.3 seconds**, all of it compiling ze0 and
  prism's Ruby half. The program cache makes every later run warm, and the
  differential harness warms it once before the corpus.
- **`zeo backend` takes about 190 ms flat**, most of it the compile of the
  empty program that gives `@boot` and `@seed` their meaning, then
  Cranelift and the link.
- **ze0's text is usually smaller** than the emitter's outlined text for
  the same program -- 15 to 50 percent -- with `main` and `zeo_unit_init`
  left to the backend, no `TOPLEVEL_BINDING` install, and one address and
  one constant per function rather than per use. It is LARGER on
  `super_channels` and `superclasses`, where the emitter resolves a super
  target statically and ze0 asks the runtime.
- **Where a program requires something, the two diverge enormously**:
  `require_relative` is 1.1 MB of emitter text against 81 KB of ze0's, and
  `autoload` 542 KB against 7.5 KB. zeo compiles the required feature's
  Ruby half into the program; ze0 opens the runtime's gate for it, which
  is the same answer for far fewer instructions and only works because the
  runtime already carries that feature.
- **A ze0 binary is twice the size.** `puts 1` links to 14.4 MB from ze0
  and 7.3 MB from `zeo build`, because ze0 keeps every builtin class
  table (`@all`): with no reachability analysis and a dynamic send that
  can reach any class, that is the honest choice. The emitter's analysis
  keeps 33 tables for that program.
- **Lines.** ze0 is 4,616 lines of Ruby, of which `lower.rb` is 3,580.
  The emitter's `clif/` is 28,483 lines of Rust and lowers more than the
  subset, so the two are not a like-for-like pair; what the pair does say
  is that a front end reaching the same fixed point costs a sixth of the
  lines when the backend is doing the register allocation. The backend
  verb and the sidecar are 1,300 lines of Rust.

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
- **A refusal fixture cannot see a wrong answer.** ze0 lowered a `break`
  inside a `while` inside a block as the BLOCK's break, refused the same
  `break` written in a method, and dropped the body of a reopened builtin
  -- silent miscompiles that every test then passing was structurally
  unable to catch, because the suite only asked whether refusals were
  right. Every form in the subset now has a golden.
- **Almost none of what was left needed Rust.** `ensure`, `defined?`,
  `super` in every channel, `class << obj`, a `def` inside a block, splat
  call arguments and `...` forwarding are all Ruby in ze0: the runtime
  entry points behind them take plain pointers and scalars and key off no
  site table. The two hardest-looking forms, `class C < <expr>` and
  `class << obj`, the Rust emitter does not implement either -- it
  desugars them before lowering, and ze0 writes the same desugar.
- **Where the sidecar cannot name a thing, desugar to the runtime.** A
  class built from a runtime value has no row; nor does a singleton. Both
  become ordinary sends, which is what the Rust front end already does.
  The one place that rule did not reach is a gated builtin's REOPEN --
  `prism.rb` writing the Ruby half of a module `prism.so` created -- and
  that took a backend change: such a row resolves to the builtin's id
  instead of minting a class beside it.
- **An eager `autoload` has no single right position.** Splicing prism's
  autoloads at the statement put `desugar_compiler.rb` ahead of the
  `node.rb` its classes inherit from; splicing them after the file put
  `visitor.rb` after the `class Newlines < Visitor` that needs it. The
  splice follows the constant instead: a statement that can reach a
  pending autoload while it RUNS takes that file first, which is where
  CRuby's own first access would have loaded it.
- **Prism's Ruby half runs under zeo unchanged**, and ze0 runs identically
  under ruby, under zeo's JIT, as stage 1 and as stage 2.

## Stage 2

Stage 2 is ze0 compiling `ze0.rb`, and it is reached.

```console
$ P=crates/zeo-rt/ext/prism/lib
$ ruby ze0/ze0.rb -I $P ze0/ze0.rb -o a.clif    # ze0 under ruby, 7.5 s
$ zeo backend a.clif -o ze0_1
$ ./ze0_1 -I $P ze0/ze0.rb -o b.clif             # ze0 by ze0, 37 s
$ cmp a.clif b.clif && cmp a.zeodata b.zeodata
$ cargo xtask stage2                             # all of the above, checked
```

Both files are 62,362,747 bytes and identical, and every program in
`test/ze0/` compiled by `ze0_1` gives the bytes ze0-under-ruby gives. The
work set is ze0's own 4,616 lines plus prism's 40,261: classes and
modules, blocks and closures, `Hash`, `Array` and `String` with their
iterators, string interpolation and mutation, constants, `case`,
`rescue`, `ensure`, `defined?`, `require`, `autoload`, `attr_reader`,
`Struct`, `super`, `class << self`, `format` and `each_with_index`.

This README once priced that at "about 25,000 lines of Rust" and "three
to six engineer-months", read off the emitter's line count. The measured
answer was twelve forms, all of them Ruby, and one backend change.

Three things ze0 does not do, and states rather than hides:

- **There are no lazy units.** An `autoload` nothing reaches at load time
  still splices its file in at the end of the file that wrote it, so that
  file runs even though the constant is never referenced. This is zeo's
  own stated divergence (`parse/loader/mod.rs`), and matching the
  reference compiler is what the differential is for.
- **`RUBY_PLATFORM` is not folded.** A host ruby and zeo name different
  builds of the same machine, so deciding a guard on it would make the
  answer depend on which of them ran the compiler. `RUBY_ENGINE` and
  `RUBY_VERSION` are folded, because ze0 compiled by zeo runs on zeo.
- **An explicit receiver does not check visibility.** `b.secret` on a
  private method answers instead of raising, where ruby and `zeo build`
  both raise `NoMethodError`. This one is a HOLE, not a decision: a call
  site carries the class it was written in, and ze0 writes "ask nothing"
  into every one of them because the sidecar names call sites by a
  link-time id it has no way to spell. It is the open item at the top of
  `ze0/PLAN.md`.

What is left is Ruby parity beyond the fixed point -- `class Foo::Bar`,
the `rescue` modifier, `def obj.method`, class variables, `for`, `$~`,
pattern matching -- ordered by how many real files each blocks. That
order is `ze0/PLAN.md`.
