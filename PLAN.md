# Widening ze0's subset

## Context

ze0 lowers a deliberately small Ruby to CLIF text: literals, locals, Integer
arithmetic and comparison, `if`/`unless`/`while`/`until`, top-level `def` with
required parameters, `return`, `puts`, and everything else as the runtime's
cached dynamic send. Anything outside that is refused by name at its line.

This plan widens it to ordinary Ruby — classes, modules, blocks, closures,
constants, instance variables, globals, string interpolation, visibility —
and stops deliberately short of `require`, `eval` and the metaprogramming
surface. Self-hosting (stage 2, which the README prices at three to six
engineer-months) is not the target, but it is the direction: where a choice
here makes stage 2 cheaper at no cost now, this plan takes it.

The contract does not change. Identical to CRuby, or refused by name.

## Two facts that shape everything

**1. Classes are a two-sided change.** `crates/zeo/src/backend/sidecar.rs`
has no `classes`, `obj` or `cm` section and its `Def` has no `class` field;
`backend/clif_text.rs:109-140` hard-wires all three to empty. The Rust
emitter's own `draft_sidecar` (`clif/emit.rs:1123-1156`) refuses "a class"
by name for exactly this reason. Classes, ivar slots and `Foo.new` therefore
need the Rust schema extended alongside the Ruby.

Everything else does not. **Globals, constants, string interpolation,
name-keyed instance variables, `send`/`respond_to?`/`method`, and the Array,
Hash and Range literals are all runtime calls with rodata name bytes and need
no new sidecar field at all.** That asymmetry is what the phases below are
built around: two phases of pure Ruby ship before any Rust risk is taken.

**2. A captured local cannot live in a stack slot.** ze0 keeps every local in
a 24-byte slot. A block that reads or writes an enclosing local needs that
local to outlive the frame and be shared, so the Rust emitter promotes it to
a heap cell (`Arc<Mutex<RubyValue>>`) and the frame's slot becomes an 8-byte
pointer (`clif/ctx.rs:16-25`). `Local` has to become a two-variant type, and
every read and write in ze0 has to dispatch on it. This is the single largest
structural change and it is why phase 1 comes first: it lands the refactor
before there is much code to refactor.

## The rule for what to emit

`zeo backend` defines `zeo_cm_sites`, `zeo_const_sites`, `zeo_new_sites`,
`zeo_dyn_sites`, `zeo_ffi_sites`, `zeo_proc_shapes` and `zeo_reopen_flags`
with **zero rows** (`clif_text.rs:102-108`), because the sidecar cannot
describe their counts. So:

> Never emit a `*_cached` entry point that keys off a site table ze0 cannot
> size. `zeo_rt_send_value_cached` and its `_kw_`/`_args_`/`_vcall_` siblings
> are fine — they key off `callsites`, which the sidecar does carry. Every
> constant read, class-method send and construction takes the **uncached**
> entry.

The full menu is `crates/zeo/src/clif/capi_names.rs` — 252 rows, alphabetical,
`CapiSig { name, params, ret }`. `CTy` maps `Ptr`/`Usize` to `i64`, `I32`/`U32`
to `i32`, `U8` to `i8 uext`, `I8` to `i8`, `F64` to `f64`, which is the
spelling `lib/ze0/capi.rb` already uses. `zeo backend` checks every call
against that table by name and signature, so a transcription error fails the
build rather than the program.

## Phase 0 — the shape the rest needs

No new Ruby features. This is the refactor that makes the following phases
small, and it is the part that matters for stage 2.

**A scope object instead of ivar soup.** `Lower` currently threads `@f`,
`@locals`, `@self`, `@out`, `@kind`, `@rodata`, `@syms`, `@raise`, `@done`,
`@exit` as instance variables mutated across `lower_def` / `lower_toplevel` /
`lower_trampoline`. Four more kinds of scope are coming (a class body, a
method body on a class, a block body, a singleton body), and nested scopes
arrive with blocks. Extract a `Ze0::Scope` holding that state, with `Lower`
holding a stack of them. Every `@f.` becomes `scope.f.`.

**`Local` becomes a type, not a slot string.** Today `@locals[name]` is an
`ssN` string. Make it `Local::Slot(ss)` / `Local::Cell(ss)` — a `Data.define`
pair or a small class — and route every read and write through it. Cells stay
unused until phase 2, but every later change is then additive.

**A declaration pass before lowering.** `Lower#lower` currently greps the
statement list for `DefNode` twice and rejects once. Replace with one walk
that collects declarations (defs now; classes, modules and constants later)
and, in phase 2, captures. Blocks and classes both need to know things about
a body before lowering it.

**Names learns owners.** `Names.method_symbol` hardcodes `Object`. The Rust
emitter's `clif/names.rs:81-116` takes an owner and has four prefixes —
`zeo_m_` (instance body), `zeo_t_` (instance trampoline), `zeo_cm_` (class
method), `zeo_ct_` (class trampoline) — with `::` in an owner written `__`.
Mirror all four now.

## Phase 1 — everything that needs no Rust

Each of these is a runtime call with rodata name bytes. Ordered by how much
ordinary Ruby they unlock per line of work.

| feature | how | entry points |
|---|---|---|
| string interpolation | fresh string, pooled at creation because a piece can raise, then append | `zeo_rt_str_new`, `zeo_rt_str_append_lit`, `zeo_rt_str_append_value` |
| `Array`/`Hash` literals | build then fill | `zeo_rt_array_new`, `zeo_rt_array_push`, `zeo_rt_hash_new`, `zeo_rt_hash_set` |
| ranges | `a..b`, `a...b` | `zeo_rt_range_new` |
| `$globals` | read infallible, write fallible (read-only globals raise) | `zeo_rt_gvar_get`, `zeo_rt_gvar_assign` |
| constants | bare name walks the cref chain; `A::B` splits on the last `::` | `zeo_rt_const_get_cref`, `zeo_rt_const_get_scoped`, `zeo_rt_const_set_at` |
| `@ivars` | name-keyed until classes bring slots | `zeo_rt_ivar_get_dyn`, `zeo_rt_ivar_set_dyn` |
| `&&`, `\|\|`, `!`, ternary, `unless`/`while` modifiers | control flow ze0 already has the machinery for | — |
| `case`/`when` | `===` per branch | `zeo_rt_case_eq`, `zeo_rt_case_eq_any` |
| `send`, `public_send`, `respond_to?`, `method(:x)` | nothing special — the ordinary dynamic send already reaches them | — |

The string builder's ordering rule is load-bearing and worth copying exactly
(`clif/expr.rs:208-255`): pool the destination **before** appending anything,
because an interpolated piece runs `to_s` and can raise.

Four sidecar fields ze0 already could write and does not: `Def.aliased_from`,
`load_path` with `n_load_path_search`, `warnings`, `eval_install`. Add the
first when `alias` lands; the rest stay unwritten and are noted here so the
next reader does not think they were missed.

## Phase 2 — blocks, procs, lambdas, closures

**Start with a spike, before writing any of the rest.**
`zeo_rt_proc_new_shaped` reads a `zeo_proc_shapes` rodata table that
`zeo backend` defines with zero rows, so it is unreachable. The older wide
entry `zeo_rt_proc_new` takes all sixteen arguments inline and needs no table.
Emit one hand-written block through it and confirm `zeo backend` links and
runs it. If it works the whole tier is Ruby-only; if it does not,
`proc_shapes` joins the phase 3 schema change and we learn that before
writing four hundred lines against the wrong entry point.

**The block is a separate CLIF function** with a six-pointer signature —
`(env, self, argv, argc, blk, out) -> i32`, the runtime's `BlockFn`
(`zeo-rt/src/capi/procs.rs:18-25`). Note this is **not** ze0's existing
five-pointer trampoline shape: a block fn prepends `env` and takes `self`
separately.

**Captured locals become heap cells.** `zeo_rt_cell_new` / `_load` / `_store`
/ `_release`. The creation site stores each captured local's cell pointer into
an `n * 8` slot and hands it to the proc; the callee loads `ProcEnv.cells` and
registers each as an unowned cell, because the proc owns them.

**Box only what is captured.** The escape analysis is the point: a name is a
cell if it is referenced inside a block *and* either assigned outside it or a
parameter of the enclosing method. Everything else stays in a stack slot and
the Integer fast path keeps working. Start with the crude rule — any local
named inside any block in a scope that contains a block — which is about fifty
lines and correct but over-boxes, then tighten. The Rust version is
`analyze/captures.rs`, 1,270 lines, and essentially all of it exists to *avoid*
boxing rather than to decide correctness.

One subtlety worth taking early: a captured loop variable gets a **fresh cell
each iteration** (`clif/iter.rs:871-893`), so closures made in a loop each
capture their own binding. Getting this wrong is a bug nobody finds for months.

**The block argument to a send stops being `0`.** It becomes a pointer to a
24-byte slot holding a `Proc`, and it is **moved** — so the proc is built
*last*, after receiver and arguments, because nothing between construction and
the call may raise.

**`yield` and `block_given?`** are nearly free once the block pointer is a body
parameter: `zeo_rt_yield`, and `block_given?` is just `icmp ne blk, 0` with no
call at all. Note the method signature grows a `blk` parameter **only when the
method uses a block**, so ze0's fixed signature becomes conditional.

**Non-local control flow is a status code plus a thread-local signal**, never a
longjmp. `next` is not a signal at all — it moves its value to `out` and
returns 0. `break` sets `Signal::Break` and returns 1, and the sending site
catches it and takes the value. `return` from a proc resolves against the
captured home. `redo` is a local jump. Skipping `ensure` interaction entirely
saves the 180 lines of `clif/control.rs` and costs nothing until `rescue`
lands.

**Skip the inline iterator fusion** (`clif/iter.rs`, 1,205 lines). `arr.each { }`
works through the generic runtime path; fusion is a pure optimization and
lowering the body twice is a complication to earn later.

## Phase 3 — the sidecar extension, then classes

**The Rust half first**, roughly 150 lines across two files:

- `backend/sidecar.rs`: new `classes`, `obj` and `cm` sections; `Def` gains
  `class`; the reflection row gains `singleton`.
- `backend/clif_text.rs:109-140`: read those sections instead of hard-wiring
  them empty; `def_rows` (`:267-334`) stops assuming `class: 0`.

The `reg` array needs no change — it already carries `kind/class/a/b/f/ids/flag`,
which is the shape `include`, `extend`, aliases, ancestries, `private_constant`
and singleton super targets all ride on.

**Then the Ruby half.** The thing to internalise is that **a class definition
emits almost no code**. Registration is a compile-time table applied before the
first statement; there is no `zeo_rt_define_class`. `module` versus `class` is
one byte in the class row. `class Foo < Bar` folds the superclass into a
linearized ancestors array. `include` and `prepend` emit no ancestry code at
all — analyze splices the module into the ancestors and copies its methods as
rows; only the `included`/`prepended` hook send remains at the statement site.
`extend` is the exception and *is* positional: `zeo_rt_class_extend_at`.

The class body becomes its own function (`zeo_cb_<n>` in the Rust emitter) with
the class as `self`. Instance methods differ from top-level `def`s only in
channel, symbol and row type — the body lowering is the same one phase 0
generalised.

Visibility is both compile-time and positional: a `def`'s own visibility is a
row (`0 private, 1 protected, 2 public`), and a later `private :name` is a call
(`zeo_rt_runtime_set_visibility`), because a reopen can change it.

`attr_reader` and `attr_accessor` produce **no body function at all** — the
trampoline is the method, doing an arity check and a direct slot access
(`clif/params.rs:566-698`). Instance variable slots are compile-time indices
into the class's declared ivar order, which is why they wait for the class
table; the name-keyed pair from phase 1 keeps working as the fallback for a
dynamic `self`.

## Phase 4 — the long tail

`super` and `super()`, `alias`, `undef`, `private_constant`, `defined?`,
`class << self`, singleton methods on an object, `Struct`, class variables.
Each is small once phase 3's tables exist. Order by what the test programs
below actually need.

## What stays refused, by name

`require`, `eval` and friends, `define_method` (it needs a block *and* a
`proc_shapes` row, so it is the one metaprogramming verb the sidecar cannot
reach even after phase 3), `method_missing`, refinements, `Ractor`, `Fiber`,
`ObjectSpace`, `binding`, `callcc`. A program using one is refused at its line,
as today. This list is the plan's edge and belongs in `README.md`'s subset
section when the phases land.

## Testing

**Fewer programs, each doing more.** The tier is 21 programs costing 230s of
CPU — 19% of the whole suite — because each takes nine processes and three real
links. Adding one program per feature would make ze0 the dominant cost of every
local test run.

So each phase adds **one or two dense programs**, not one per feature: a single
`closures.rb` that exercises capture, mutation, a loop variable, `yield`,
`block_given?`, `next`, `break` and a lambda's arity, checked against ruby's
recorded answer like every other golden. A program that covers eight features
costs the same nine processes as one that covers one.

The three-road differential is the property worth protecting: `zeo build`, ze0
under the JIT, and stage 1, agreeing byte for byte. Every phase re-runs it, and
a phase is not done until all three roads agree.

`ze0/measure.rb` regenerates the README's table; run it at the end of each
phase so the cost of the widening is recorded rather than guessed.

## Verification

```
ruby ze0/ze0.rb test/ze0/<program>.rb -o /tmp/p.clif   # ze0 under ruby
zeo backend /tmp/p.clif -o /tmp/p && /tmp/p            # link and run
cargo nextest run -p zeo -E 'test(ze0::) + test(ze0_clif)'
cargo xtask bless ze0::<program>.rb                    # record ruby's answer
ruby ze0/measure.rb                                    # the README's table
```

Per phase, in order:

1. Every new form has a program in `test/ze0/` whose answer was recorded from
   ruby, not written by hand.
2. All three roads agree byte for byte — the differential, not just "it ran".
3. `ZEO_RT_LEAKCHECK=1` stays clean, which is what says the ownership rules
   were followed rather than merely not crashing.
4. A form outside the subset is still refused **at its line, by name**. This is
   the property that makes ze0 trustworthy and it is the easiest to lose while
   widening: a half-supported form that compiles to something answering
   differently from ruby is worse than one that is refused.
