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

## Phase 2 — blocks, procs, lambdas, closures — DONE

The spike this phase opened with answered its question: **the sidecar is
not in the way of blocks.** `zeo_rt_proc_new_shaped` reads a
`zeo_proc_shapes` row and `zeo backend` defines that table with no rows, so
it is unreachable; the older wide `zeo_rt_proc_new` takes all sixteen
arguments inline, and it links and runs.

The second answer is the one that generalises: **a C struct the runtime only
reads for the length of the call can be built in a STACK SLOT.** That is what
makes `zeo_rt_bind_block_params` reachable -- its `ParamDescC` holds
pointers, and a rodata blob carried as sidecar bytes has nowhere to put a
relocation, but a stack copy needs none. Without the real binder,
`{ "a" => 1 }.map { |k, v| k }` answered `[["a", 1]]`: ruby's auto-splat is
the binder's, not something to reimplement. The same trick gives
`Proc#parameters` its `ParamC` rows, though their NAME bytes still come from
rodata, because the proc keeps those and the stack copy would dangle.
`zeo_rt_proc_new_shaped` stays out for exactly that reason: the proc keeps
the shape pointer.

What landed: block literals as their own six-pointer `BlockFn` functions;
captured locals as heap cells, owned by the creating scope and borrowed
through `ProcEnv` by the block; `next` as the block's ordinary return;
`break` as the Break signal with a catch at every block-passing send; and
`yield`/`block_given?`, for which a method's signature grows a `blk`
parameter -- but only where the body uses one.

Two things the plan expected to be hard were not. A captured loop variable
needs no fresh cell per iteration, because `while` is ze0's only loop and
ruby shares one binding across its iterations too, while a block parameter
is already a local of the block's own frame. And the crude capture rule --
a name is boxed when any block in the scope mentions it -- is enough; the
Rust `analyze/captures.rs` is 1,270 lines almost entirely spent *avoiding*
the boxing rather than deciding it.

Still refused by name: a block parameter list beyond required positionals,
a block-local variable (`|x; y|`), `redo`, and `&block`.

## Phase 3 — the sidecar extension, then classes — DONE

**The Rust half.** `backend/sidecar.rs` gained a `classes` list and two
fields on `Def` (`class`, `singleton`); `backend/clif_text.rs` reads them,
assigns ids, linearizes each ancestry and routes every method to its
channel -- a top-level `def` and a module's method to the VALUE channel, a
class's instance method to the OBJECT channel, `def self.x` to the
class-method one. Which channel is not a choice the sidecar makes: it
follows from the class's kind and the singleton flag.

**Ids were the real design question, and the answer generalises.** A class
id is the compiler's own index into its class vector, which begins after
whatever the boot prelude registered -- a number that shifts with the zeo
build and that a front end must never guess. So the sidecar names a
superclass rather than numbering it, the backend assigns ids at LINK time,
and where ze0's code needs one -- a constant's cref, an assignment's owner
-- it reads `zeo_class_ids`, exactly the indirection `zeo_syms` already
gives an interned symbol. The sidecar also gained `first_user_class`,
which the empty program's own compile fills, so the backend learns the
base from a real compile rather than a constant that could drift.

The class's own-method marks (`instance_methods(false)` truth) are
DERIVED in the backend from which class each `def` names, rather than
asked for as rows whose `class` would have to be an id.

**Two things went wrong in ways worth keeping written down.**

A bare call inside `Animal#describe` was lowered as a direct call to
`Animal#speak`, so `Dog`'s override never ran. Direct calls are now off in
any program that declares a class: which method a bare name reaches is a
run-time fact, and settling it statically needs the override analysis ze0
does not have.

And a class body is full of calls that would answer differently rather
than not at all. `attr_reader :x` compiled fine and left `x` answering
nil; `private` left a method public; `K = 1` landed on `Object`. The
constant is now fixed properly -- it lands on the class the cref names --
and the rest are refused by name: `attr_*`, `include`/`extend`/`prepend`,
the visibility verbs, `define_method`, `alias_method` and the other
`Module` macros.

**A bare `yield` written inside a block** reaches the enclosing method's
block through `ProcEnv.lexical_blk`, which phase 2 had passed as null.
`Stack#each` calling `@items.each { |i| yield i }` is the shape that found
it.

Still refused: `super`, nested classes, `class << self`, class variables,
a scoped class name (`class A::B`), a builtin superclass, and every
class-body macro above.

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
