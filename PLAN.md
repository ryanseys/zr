# Widening ze0's subset

## Context

ze0 lowers a deliberately small Ruby to CLIF text: literals, locals, Integer
arithmetic and comparison, `if`/`unless`/`while`/`until`, top-level `def` with
required parameters, `return`, `puts`, and everything else as the runtime's
cached dynamic send. Anything outside that is refused by name at its line.

This plan widens it to ordinary Ruby — classes, modules, blocks, closures,
constants, instance variables, globals, string interpolation, visibility.

**Stage 2 is now the target.** ze0 compiling `ze0/` is what the remaining
work aims at, which makes the subset a *measured* thing rather than a taste
question: the Ruby worth building is the Ruby ze0's own sources use, and
nothing else. Phases 0 through 5 are done and recorded below; what is left
is in "The remaining work", and it comes from the census rather than from
a wish list.

The contract does not change. Identical to CRuby, or refused by name.

## How to know what is left

One script answers it, and it is the method the remaining phases are
ordered by:

```ruby
# Which Ruby ze0 uses that ze0 cannot yet compile.
require "prism"
handled = File.read("ze0/lib/ze0/lower.rb").scan(/Prism::(\w+Node)/).flatten.uniq
Dir["ze0/**/*.rb"].each do |path|
  walk = lambda do |node|
    name = node.class.name.sub("Prism::", "")
    puts "#{name} #{path}:#{node.location.start_line}" unless handled.include?(name)
    node.compact_child_nodes.each { |c| walk.call(c) }
  end
  walk.call(Prism.parse_file(path).value)
end
```

It undercounts by design — a form ze0 lowers *conditionally* (a class-body
macro, a splat argument) is a `CallNode` and looks handled — so pair it
with the blunt instrument:

```console
$ for f in ze0/lib/ze0/*.rb ze0/*.rb; do ruby ze0/ze0.rb $f -o /tmp/c.clif; done
```

which names each file's FIRST refusal. Between them they have driven every
phase since the target changed, and they are how to tell when stage 2 is
actually close rather than nearly close.

## Three facts the work established

The first two shaped the phases and are now settled; the third was found
while doing them and is the one that still guides what is left.

**1. Classes were the only two-sided change.** The sidecar had no
`classes`, `obj` or `cm` section and its `Def` had no `class` field, so
classes, ivar slots and `Foo.new` needed the Rust schema extended
alongside the Ruby — which phase 3 did. **Everything else did not.**
Globals, constants, string interpolation, name-keyed instance variables,
`send`/`respond_to?`/`method`, the Array, Hash and Range literals, blocks,
closures, `yield`, and the whole parameter surface are runtime calls over
rodata name bytes and needed no new sidecar field at all. That asymmetry
held for five phases: only one of them touched Rust.

**2. A captured local cannot live in a stack slot.** ze0 keeps every local
in a 24-byte slot. A block that reads or writes an enclosing local needs
that local to outlive the frame and be shared, so it is promoted to a heap
cell (`Arc<Mutex<RubyValue>>`) and the frame's slot holds an 8-byte
pointer (`clif/ctx.rs:16-25`). `Local` is a three-state type for it:
a plain slot, a cell this scope owns, or a cell borrowed out of a
`ProcEnv`.

**3. A C struct the runtime reads only during the call can be built on the
STACK.** This is the one to remember. A front end that writes its rodata
as sidecar bytes has nowhere to put a relocation, so any runtime entry
taking a pointer-bearing struct looks unreachable — and most of them are
not. `zeo_rt_bind_params` and `zeo_rt_bind_block_params` take a
`ParamDescC` full of pointers and work perfectly from a stack copy, which
is what put ruby's real parameter binding and auto-splat within reach
instead of being reimplemented.

The limit is lifetime, not layout: `zeo_rt_proc_new_shaped` stays out
because the proc KEEPS its shape pointer, and `Proc#parameters`' name
bytes still come from rodata for the same reason. Before refusing a
runtime entry as unreachable, ask whether it merely reads the struct.

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

## Phase 0 — the shape the rest needs — DONE

No new Ruby features: the refactor that made every later phase small, and
the part that mattered for stage 2. It landed byte-identical output on all
21 programs of the day, which is the only way to know a refactor of a code
generator changed nothing.

**A scope object instead of ivar soup.** `Lower` threaded ten instance
variables across `lower_def` / `lower_toplevel` / `lower_trampoline`. They
became a `Ze0::Scope`, and `Lower` holds a stack of them — which is what a
class body, a method body on a class, and a nested block body all needed.
The readers that reach the top of that stack must not be named for a
`Kernel` method: a private method on `Lower` overrides one for every
instance, which is how `Lower#send` came to shadow `Object#send`. A check
test asks that rule on every run.

**`Local` became a type, not a slot string.** A plain stack slot, a heap
cell this scope owns, or a cell borrowed out of a `ProcEnv` — the last two
arrived in phase 2, and every read, write and release dispatches on it.

**A declaration pass before lowering.** One walk collects what lowering has
to know first: the `def`s, then classes and modules, then captures. Blocks
and classes both need facts about a body before lowering it.

**Names learned owners.** All four of the Rust emitter's prefixes —
`zeo_m_` (instance body), `zeo_t_` (instance trampoline), `zeo_cm_` (class
method), `zeo_ct_` (class trampoline) — with `::` in an owner written `__`.

## Phase 1 — everything that needs no Rust — DONE

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

## Phase 4 — the whole parameter surface — DONE

The one hard wall in front of every other feature, and the slice that
needed no Rust at all: the sidecar already described all seven parameter
kinds. Optional parameters with defaults, `*rest`, post parameters,
required and optional keywords, `**kwrest` and `&block`, on methods and
blocks alike, plus `->() {}` and keyword arguments and `&expr` at a call
site.

`zeo_rt_bind_params` routes argv into a slot array and answers a presence
bitmap; the trampoline passes one pointer per slot and a NULL where an
optional was left out, which is how the body tells "left out" from "given
nil". **The default runs in the BODY**, which is what lets one read the
parameter before it (`def f(a, b = a + 1)`).

A plain shape keeps the trampoline it had — an inline count check, no
binder — so every program without such a parameter emits byte-identical
text.

**`Kernel#lambda` cannot make a proc a lambda after the fact.** Arity and
the strict binding are baked in at creation, so `lambda { |a, b = 1| }`
answered 1 where ruby says -2 until the creation site knew. Arity mirrors
`clif/params.rs`'s `proc_arity` exactly.

## Phase 5 — nesting, multiple assignment, regexps, the write family — DONE

The first phase ordered by the census rather than by taste.

**Nesting was the wall**: every ze0 file is `module Ze0` around a class, so
none got past line 6. A class carries the path it is written at, which is
what `Module#name` answers and what its symbols and frame labels spell; a
bare constant's cref is every enclosing scope, innermost first, then
`Object`. A body's symbol is settled when it is DECLARED, not when it is
lowered, because an enclosing body calls it and the two lower in either
order.

**Multiple assignment** was 53 uses. `zeo_rt_multi_split` does the whole
destructure — an Array directly, anything else through ruby's `to_ary`
rule — into owned slots, so ze0 only routes each slot to its target:
locals, ivars, globals, constants, `a[i] =`, `x.y =`, and a nested
`(a, b)` that splits again. A trailing comma (`x, = list`) is the shape
with no rest slot at all.

`h[k] ||= v` and `x.y ||= v` joined the operator writes, with the receiver
and the index evaluated ONCE — both halves close over operands the pool is
already holding.

**A regexp's encoding byte is its own scale**, not a string literal's:
passing UTF-8's 1 means "no encoding" and printed `/\A[a-z]+\z/n` where
ruby prints no suffix. One frozen object per site, named by a per-program
counter, which is sound only because ze0's emitted code is the program's
only caller of `zeo_rt_regexp_lit`.

`capi.rb`, `json.rb` and `names.rb` compile end to end after this phase.

## Where stage 2 stands

`ruby ze0/ze0.rb -I <prism> ze0/ze0.rb` walks all nine of ze0's own files,
into prism, and stops in prism's polyfills. **All nine of ze0's files
compile**; eleven of prism's twenty-eight do.

Scale is not what is left. Measured on prism's biggest file: `node.rb`'s
19,966 lines cost ze0 1.37 s and 262 MB to write 20 MB of CLIF, and
`zeo backend` turns that into a 19 MB binary in 0.95 s.

S0 through S8 are done and are recorded in the commits. What follows is
what stands between here and the fixed point, with the census that names
each item.

## W1 -- `Module.new { def ... }`, and the rest of prism's syntax

prism's four polyfills are all one shape:

```ruby
if !("".respond_to?(:byteindex))
  String.include(Module.new { def byteindex(needle, offset = 0) ... end })
end
```

Every guard is false on ruby 4.0.6, which is zeo's floor, so the bodies
are dead -- and ze0 still has to compile them.

**This is reachable with the machinery ze0 already has, and the plan was
wrong to call it structurally out.** `zeo_rt_define_in_default_definee`
takes a **Proc** as the method body and installs it on whatever definee
the runtime resolves, which is the new module inside a `Module.new`
block. ze0 builds Procs already: the wide `zeo_rt_proc_new` takes all
sixteen arguments inline, which is what phase 2 found for blocks. The
`zeo_proc_shapes` row the Rust emitter uses is what ze0 cannot reach --
and it does not need it.

What the work is: a block body compiled as a METHOD body rather than a
block one. The frame is a method frame, not `block in ...`; the binding
is strict; and a bare `super` forwards the method's own parameters, which
is the `MethodBody::Def` / `MethodBody::DefineMethod` distinction at
`clif/blocks.rs:303`.

The rest of the census, each with its file:

| form | where |
|---|---|
| a `def` inside a block | the four polyfills |
| `include` / `extend` / `prepend` | `desugar_compiler.rb`, `node_ext.rb`, `dsl.rb` |
| `autoload` | `prism.rb`, `parse_result.rb` |
| a required file with top-level locals | `prism.rb:86`, `serialize.rb:13` |
| `defined?` | `dot_visitor.rb` |
| `class << self` | `zeo.rb` |
| `next` in a loop | `parse_result/comments.rb` |
| an `ensure` clause | `parse_result/newlines.rb` |
| a destructuring parameter | `pattern.rb` |
| a superclass of that shape (`< Struct.new(...)`) | `lex_compat.rb` |

Two of these are ze0 bugs rather than missing features. `next` inside a
`while` is ordinary ruby and ze0 refuses it as "outside a block". And a
required file's top-level locals are its own in ruby; ze0 has one
top-level scope, so it refuses them -- the Rust loader renames them per
file (`parse::rename`) and ze0 should key them by unit.

## W2 -- prism's vendored tree as an overlay

`crates/zeo-rt/ext/prism/` is 26 files and 40,160 lines, of which
**25 files are byte-identical to the stock gem**. Only `prism.rb`
differs -- three hunks, 33 lines, each commented -- plus one new file,
`prism/zeo.rb`, the native-backend seam adapted from upstream's own
`ffi.rb`. `prism/ffi.rb` and the thirteen `prism/translation/**` files
are deliberately absent.

So the tier should carry only what it changes: `prism.rb` and
`prism/zeo.rb`, about 360 lines, with the other twenty-five resolved from
the ordinary vendored gem. `EXT_TIER` already takes precedence
(`gems/bundled.rs:50`), so the search order is right; what has to be read
first is `xtask payload`, which flattens the tier into
`share/zeo/lib/ruby/`, and the loader's tier walk, to be sure a PARTIAL
tier falls through rather than shadowing.

A prism version bump then touches two files instead of twenty-six.

**Stock prism is not an alternative to W1.** The polyfills are upstream's
own files, byte-identical in both trees, and the stock gem also carries
`ffi.rb` (which uses `MatchWrite`, another refused form) and the thirteen
translation files. Using it unchanged would grow the surface, not shrink
it -- and a ze0-emitted program cannot `dlopen` a C extension, because
the sidecar has no row for one.

## W3 -- the fixed point, and how it is gated

`cargo xtask stage2`, run on demand, nothing automated -- the same trade
the gem tests took. It builds ze0 with ze0-under-ruby, builds ze0 again
with that binary, and demands the two `.clif` and the two `.zeodata` be
byte-identical. Then it runs every `test/ze0/` program through the second
and demands the bytes the first writes: a compiler that reproduces itself
but miscompiles is not done.

Register it in all three places -- `commands/mod.rs`, the dispatch match,
and the `USAGE` block -- because `checks::docs` parses the last one.

## What stays refused, by name

`eval` and friends, `method_missing`, refinements, `Ractor`, `Fiber`,
`ObjectSpace`, `binding`, `callcc`, and a run-time `require` against a
load path. A program using one is refused at its line. This list is the
plan's edge and it is in `README.md`'s subset section.

## Testing

The tier costs nine processes and three real links per program, so each
step adds one or two DENSE programs rather than one per feature. A
program covering eight features costs the same as one covering one.

`crates/zeo/tests/fixtures/ze0_refused/` holds one program per form
outside the subset, each naming the refusal it must draw on its first
line; one ruby process compiles them all in 0.6 s. A fixture that starts
compiling is the signal to delete it. That guard is what caught the four
silent drops S0 fixed, and every step since has added to it.

## Verification

```
ruby ze0/ze0.rb test/ze0/<program>.rb -o /tmp/p.clif   # ze0 under ruby
zeo backend /tmp/p.clif -o /tmp/p && /tmp/p            # link and run
cargo nextest run -p zeo -E 'test(ze0::) + test(ze0_clif) + test(ze0_refused)'
cargo xtask bless ze0::<program>.rb                    # record ruby's answer
ruby ze0/measure.rb                                    # the README's table
```

Per step, in order:

1. Every new form has a program in `test/ze0/` whose answer was recorded
   from ruby, and every new refusal has a fixture.
2. All three roads agree byte for byte -- the differential, not "it ran".
3. `ZEO_RT_LEAKCHECK=1` stays clean.
4. A form outside the subset is still refused **at its line, by name**.
