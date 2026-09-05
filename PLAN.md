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

`ze0/census.rb` answers it over any corpus, and it is the method the
remaining work is ordered by -- see "The census against real Ruby"
below. The older one-file walk still serves for a quick look:

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

## The census against real Ruby

`ze0/census.rb` runs ze0 over a corpus in ONE ruby process and prints two
things: each file's FIRST refusal, ranked by how many files it blocks,
and every Prism node kind `lower.rb` never names -- which catches the
forms hidden behind someone else's first refusal.

```console
$ ruby ze0/census.rb 'test/lang/**/*.rb' 'test/core/**/*.rb'
$ ruby ze0/census.rb 'test/stdlib/**/*.rb' 'crates/zeo-rt/gems/**/*.rb'
$ ruby ze0/census.rb 'vendor/gems/gems/*/lib/**/*.rb'
```

Run 2026-09-03, against ze0 as of S9:

| corpus | files | compile | refused | crash |
|---|---:|---:|---:|---:|
| `test/lang` + `test/core` | 5,008 | **3,562** (71%) | 1,413 | 33 |
| `test/stdlib` + the pure-tier gems | 477 | **305** (64%) | 170 | 2 |
| 30 vendored gems' `lib/` | 1,476 | **247** (17%) | 1,223 | 6 |

The corpus is written to test one thing per program, so 71% is a fair
measure of the LANGUAGE ze0 covers. Real gem code is 17%, and the gap is
almost entirely one form: `class Foo::Bar`, which the corpus rarely
writes and every gem does.

### The crashes, which are bugs and not gaps

Three shapes make ze0 raise a Ruby error instead of refusing by name.
Each is one missing `is_a?`, and each is the class of defect S0 exists to
prevent.

| count | shape |
|---:|---|
| 27 | `_1` / `_2` -- `NumberedParametersNode` has no `locals` |
| 5 | `&blk` as a block's whole parameter list -- `BlockArgumentNode` has no `parameters` |
| 1 | `it` -- `ItParametersNode` has no `locals` |

### Refusals that are wrong, not missing

Ordinary Ruby that ze0 turns away. These cost nothing to allow and each
one is a divergence from the contract, since a refusal is only honest
when the form is genuinely outside the subset.

- **`next` and `break` inside a `while`** (33 files). ze0 says "outside a
  block". Both are ordinary loop control; `lower_while` already has the
  head and exit labels they need.
- **A method defined twice in one class** (30 files). Ruby redefines it,
  with a warning. ze0 refuses.
- **`a class this program does not declare`** (25 files) -- a class body
  reached through a path the declaration pass did not walk.

### The ranked list

Merged over all three corpora, by the number of files each blocks. The
grouping is by what the work IS, since one piece of machinery usually
clears several rows.

**The class and module surface -- 800+ files, the largest single win**

| files | form |
|---:|---|
| 401 | `class Foo::Bar` (a scoped class name) |
| 207 | `include` in a class body |
| 161 | a superclass that is not a plain name (`< Struct.new(...)`, `< klass`) |
| 113 | `class << self` |
| 120 | `def obj.method` (a def with a receiver) |
| 71 | `extend` in a class body |
| 40 | `module_function` |
| 17 | `define_method` |
| 10+ | `refine` / `using`, `private_class_method`, `undef_method`, `remove_method`, `class_eval` |

`include`, `extend` and `prepend` need the ancestry the sidecar computes
from `superclass` alone today -- a `Class.includes` field in the same
shape as `ivars`, plus `REG_EXTENDS` and `REG_SET_ANCESTORS`. The rest
are compile-time.

**Exceptions -- 320+ files**

| files | form |
|---:|---|
| 210 | `x = foo rescue nil` (the rescue MODIFIER) |
| 107 | an `ensure` clause |
| 2 | `retry` |

The modifier is `begin; x; rescue StandardError; y; end` and needs
nothing new. `ensure` is the invasive half S4 deliberately stopped short
of: every exit path has to learn the save/run/restore bracket, and a jump
across one travels as a signal that the construct settles back.

**Blocks and procs -- 290+ files**

| files | form |
|---:|---|
| 102 | a `def` nested inside another statement (W1) |
| 51 | a destructuring block parameter (`\|(k, v), i\|`) |
| 33 | `_1` / `it` (and the crash above) |
| 7 | a block-local variable (`\|x; y\|`) |
| 6 | an anonymous block forward (`&`) |
| 4 | `redo` |

**Pattern matching -- 90 files, and none of it exists yet**

`case/in` (81 files) with `ArrayPattern`, `HashPattern`, `FindPattern`,
`AlternationPattern`, `CapturePattern`, `PinnedVariable`,
`PinnedExpression`, plus the one-line `in` (`MatchPredicate`, 7) and `=>`
(`MatchRequired`, 8). This is the biggest single feature ze0 does not
have at all, and the runtime does the work: `deconstruct` and
`deconstruct_keys` are ordinary sends.

**Arguments -- 180 files**

| files | form |
|---:|---|
| 134 | a splat at a call site |
| 28 | `...` forwarding (`ForwardingParameter`, `ForwardingArguments`) |
| 8 | a bare `KeywordHash` argument |
| 5 each | an implicit rest, a splat in a `when`, in a `rescue`, in a `yield` |

**Non-local control -- 110 files**

| files | form |
|---:|---|
| 56 | `return` from inside a block |
| 33 | `next`/`break` in a `while` (the bug above) |
| 21 | `for` |
| 9 | `return`/`break` of several values |

`return` from a block needs the home-push and the Return catch at the
method boundary (`clif/body.rs:585-606`), which is the one piece of the
signal protocol S4 did not build.

**Constants and variables -- 130 files**

| files | form |
|---:|---|
| 59 | `::Foo` (a constant path with no scope) |
| 40 | class variables, and their operator writes |
| 37 | `$1` (`NumberedReferenceRead`) |
| 12 | the constant operator writes (`A::B ||= x`, `A += 1`) |
| 5 | `$~` (`BackReferenceRead`), `MatchWrite` |

**Loading -- 140 files**

| files | form |
|---:|---|
| 78 | a required file with top-level locals (rename them per unit, as `parse::rename` does) |
| 21 | `autoload` |
| 19 | a `require_relative` outside statement position |
| 15 | a computed `require` |
| 7 | `load` |

**`super` -- 110 files**

| files | form |
|---:|---|
| 63 | `super` in a module method (the VALUE channel walk) |
| 17 | `super` in a class method (the singleton chain) |
| 17 | a bare `super` forwarding a rest or keywords |
| 8 | `super` inside a block |

**Literals and the small tail -- 90 files**

`defined?` (122 files, and it is its own thing), an interpolated regexp
(20), `Rational` and `Imaginary` (16), an interpolated symbol (9),
`__FILE__` / `__LINE__` / `__ENCODING__` (24), an Integer literal past 64
bits (12), the hash shorthand `{x:}` (6), backticks and `%x{}` (7),
`alias $new $old` (2), `BEGIN`/`END` (4), a flip-flop (3),
`# shareable_constant_value` (1).

### What the list says about order

Four items clear more than half of everything: **the scoped class name**,
**the rescue modifier**, **`include`**, and **a superclass that is not a
plain name**. None of them is deep -- the first three are compile-time or
a desugaring, and the fourth is a runtime class value where ze0 assumes a
name.

The three crashes and the three wrong refusals come before any of it,
because they are the contract rather than the subset.

## Where the frontier actually is -- measured 2026-09-04

Every earlier reading of "what is left" came from `ze0/scan.rb` at its
default limit, which was 40 and silently truncated. The numbers below
are the whole corpus.

**What ze0 COMPILES**, one ze0 compile per file over 5,392 programs:

```
test/lang        2013 of 2065
test/core        2822 of 2844
test/stdlib       457 of  466
                 ----------------
                 98.5%
```

**What ze0 gets RIGHT**, `cargo xtask ze0-sweep --all` over 5,934:

```
matched   5400
refused     69
backend    106
diverged   358
```

The last line is the one that matters, and nothing could see it before
the sweep existed: every diverged program COMPILES, so a compile probe
calls it a success. A refusal is honest; a wrong answer is not.

The named divergence classes:

| n | class |
|--:|---|
| 104 | the ambient rbconfig shim, which ze0 has no mechanism for |
| 24 | `Ruby::Box` -- the whole of `test/lang/boxes` |
| 19 | a dynamic `Ractor.new` (an honest runtime message, not silent) |
| 17 | a `require` the units road cannot find |
| 3 | a scope intrinsic reached through `send` |
| 196 | not yet classed |

The 106 `backend` failures are one shape: the sidecar names a feature
the runtime does not carry as a builtin (`csv`, `fileutils`,
`tempfile`), and the link reports it instead of ze0 refusing the
`require` at its own line.

The refusals, by shape:

```
  14  a class reopened under a guard
  13  a `using`
  13  a statement in a `class << obj` body
   7  a def on self at the top level
   6  a class named in a scope of that shape
   6  a splat in a `when`
   5  a class nested inside another statement
   5  a module reopened under a guard
   5  a super outside a method body
   4  a constant assigned into a scope this program does not define
   3  FlipFlop
   3  a class variable in a class this program cannot name
   2  Splat
   2  a super at the top level
   1  each: KeywordHash, ShareableConstant, a `module_function` of a
       method this body does not define, a `require` of a file the
       splice already took, the local <name> has no slot
```

## W6 -- the contract, and the tool that measures it -- DONE

A crash is not a refusal, and a refusal of a program ruby merely RAISES
on is not one either.

- **A runtime superclass crashed the compile.** `class Three < Two`,
  where `Two` itself has a run-time superclass, asked `zeo_class_ids`
  for a row `Two` never got. A class whose parent is made at run time is
  made at run time too. Seven files.
- **A definition ruby raises on now runs and raises.** The declare pass
  records the `TypeError` the statement owes and files no body; the
  statement lowers to the raise in its place, and the class stays as it
  was. Both message lines are ruby's. A builtin's kind and parent are
  the runtime's, so those two guards are written out rather than settled
  at compile time. Seven files.
- **`Names::EXCEPTIONS`** transcribes `zeo_abi::EXCEPTION_CLASSES`, so a
  reopen of the native exception tree routes to the runtime like any
  other builtin rather than minting a shadow row the backend refuses.
- **`cargo xtask ze0-sweep`** is the tool this plan was missing. One
  program costs one ze0 compile and one real link; the four buckets are
  `refused` / `backend` / `matched` / `diverged`, and the refusals print
  as a histogram by shape.
- **A reopened builtin wins the call it was reopened for.** An operator
  defined anywhere on Integer's fast-path MRO stands the inline fast
  path down; any `puts` the program defines stands the fold down.

## W7 -- the singleton class body -- DONE

`test/lang/singleton` is 91 of 91: no refusals, no divergences.

The body was lowered as a run of `define_singleton_method` calls with no
cref, so a constant written there had nowhere to land and the whole
statement was refused -- and a constant is what the idiom is for.

It now gets a row of its own, named `#<Class:Owner>`, carrying
`singleton_of` in the sidecar so `backend/clif_text.rs` writes the
`REG_SINGLETON_SURROGATE` row: the front end names, the backend
resolves. The row is the body's cref AND its default definee, so a
constant lands on the singleton, a `def` beside it reads the constant, a
`def` in a block there installs on the singleton, and a nested `class`
belongs to the singleton too. A `class << self` beside them opens the
surrogate's own singleton, and `def self.x` defines one level further up
-- on a per-object body as much as on a surrogate one. The body has the
frame ruby gives it, labelled `singleton class`, and its own locals.

`Module.nesting` folds to that chain: the runtime's own row answers an
empty Array because a frame carries no cref.

A `class << obj` on any other receiver keeps the per-object desugar --
no row can name a singleton minted per object -- and a constant there
is still refused.

## W7 -- how it was done

13 files, the largest refusal bucket. `lower_singleton_class` refuses a
constant write, a constant-path write and a nested `class << ...`; a
nested `class X` falls through and dies as W8's refusal instead. The
idiom is URI's `class << self; RESERVED = ...; def escape`.

The Rust emitter's answer is a **named class row**, not a desugar:
`compiler/names.rs:16` `SINGLETON_SURROGATE = "#<Class:self>"`. Every
`class << self` body mints one, even a constant-free one, because the
surrogate IS the body's cref. A `REG_SINGLETON_SURROGATE` row (kind 12)
ties owner to surrogate so `Owner.singleton_class` answers the
compile-time id.

ze0's version: `declare_class` mints a row named `#<Class:Owner>`, the
sidecar class row grows one by-name field `singleton_of`, and
`backend/clif_text.rs` synthesizes the reg row from it -- the same trade
`conceal`, `Class.superclass` and `CallerClass::Named` already make.
With a cref the body's statements stop being special.

`class << obj` where `obj` is not the enclosing class keeps today's
desugar: zeo mints no surrogate there either.

## W8 -- a class the compile cannot name -- DONE

Three refusals, one cause: `declare_runtime_class` filed a row and
returned without walking the body. Everything such a body writes now
goes through the class VALUE -- `self` inside the body, where the
constant that holds the class is not bound yet, and that constant in a
`def`, where it is. A reopened builtin takes the same road: neither has
a class id.

  - a nested `class` or `module` is made at run time too, its constant
    set on the class the enclosing body is building
  - a constant the body writes lands on the class; a read of one, from
    the body or from a `def` beside it, resolves through it
  - a class variable takes the reflective `class_variable_get`/`_set`
    family, which starts from a receiver and walks the ancestors itself
  - `class self::Task` names no scope this compile can write into, so
    the row takes a name of its own
  - `class ::Module` names the top level, not an empty namespace

Eleven corpus programs stopped being refused.

## W8 -- how it was done

10 files, three refusals, one cause: `declare_runtime_class` files a row
and returns without walking the body, so nothing inside is declared.

- a class nested inside another statement (5)
- a class named in a scope of that shape (6) -- `class Foo::Bar` with a
  runtime `Foo`
- a class variable in a class this program cannot name (3) --
  `crates/zeo-rt/src/cvars.rs` is keyed on a compile-time class id and
  there is no value-keyed entry, so route it through the reflective
  `class_variable_get` / `_set` sends the runtime already answers

## W9 -- how it was done

13 files. `refine` was already the ordinary runtime send that mints a
real holder; only `using` was refused.

The whole-program road nominates a call site from compile-time
`ClassId`s, which a front end never learns. **The snippet road is
value-keyed and slot-keyed and is exactly the shape ze0 needs**:
`zeo_rt_eval_using(module, slot)`, `zeo_rt_eval_refined_send`,
`zeo_rt_eval_refined_send_args`, `zeo_rt_eval_reflect_dispatch`, over
`crates/zeo-rt/src/eval.rs`'s `USING_SLOTS`. A slot is an integer ze0
assigns itself, so refinements need no class id at all.

- a `using` written directly in a FILE's or a CLASS BODY's statements
  takes a slot and a byte range: from the statement to the end of the
  file, or to the end of the body. Every call the range covers hands its
  slots to the runtime, ahead of every fold -- a refinement may well
  override the name a fold answers itself
- a `refine` block sees its own module's whole set, so one slot per body
  serves every `refine` written in it and the body fills it as it ends,
  by which point each of them has minted its holder
- `send`, `public_send`, `respond_to?` and `method` at a covered site go
  to `zeo_rt_eval_reflect_dispatch`: which name is being asked about is
  a run-time fact
- a `using` under a guard covers the same range either way, and one
  whose guard does not run leaves its slot empty -- the same nothing
  ruby activates there
- a `using` anywhere else stays an ordinary send, and the runtime
  answers it -- `RuntimeError: main.using is permitted only at toplevel`
  from a method body

Three Rust changes, all small.

- `zeo_rt_using_slots_ensure(n)`, which reserves a program's slots at
  boot. Nothing else has reserved by then, so the sites number
  themselves from zero and a snippet compiled later takes the ids above
- `using_activate` read a `refine C.singleton_class` holder as refining
  the INSTANCE side. It reads the target back through
  `singleton_owner_value` now, so the pair is marked singleton and
  `refine_singleton_class.rb` answers
- `send_as_defined_in` probed the overlay only for an Object receiver,
  so `Method#call` on a body a RUNTIME `refine` defined for an Array or
  a String raised NoMethodError. Both roads carried it; ze0 reaches it
  first because it runs every `refine` at run time

Filed while doing it: **#66**, `zeo build` cannot lower a `using`
written in a method body -- the node reaches codegen with no activation
to emit and the compile fails by name where ruby raises at run time.

## W10 -- how it was done

The whole tail, and the guarded reopen that led it. The corpus went from
69 refusals to 7, and from 5400 matched to 5466.

**A class body written under a guard** (20 files) was one line. A `def`
under a guard is REGISTERED BUT NOT PROMISED -- it claims no static row
and installs where it stands -- and `declare_class` computed the guard
and never passed it down into the body. A guarded body is that same
guard around every `def` it holds, which is also what made the refusal's
own reason go away: a reopen the branch never took can no longer add its
methods anyway.

Two branches of one guard that name DIFFERENT superclasses are refused
by name. Only one runs and which is not a fact this compile has, so the
row's parent used to come from whichever body was declared first and the
other raised `superclass mismatch` on a program ruby runs. The four
guard shapes behind it are #68.

The rest, each small:

- `when *list` spreads its value the way a call site's splat does and
  tests the elements one at a time -- a run-time count, so the arm is a
  loop where a written-out `when` is a chain
- `def self.x` at the top level names `main`, one object and not a
  class, so the method lands on its singleton as `def obj.x` does
- a `super` in a scope with no `def` of its own may still BE a method at
  run time; explicit arguments take the dynamic walk and a bare one gets
  the runtime's own refusal. `defined?(super)` asks the same stack
- the flip-flop, a latch per site in the runtime's own table. An omitted
  end never fires
- a bare `k: v` tail is one Hash element inside an array literal
- `# shareable_constant_value:` leaves the write, which is the reference
  compiler's answer and a divergence from CRuby
- a constant assigned into a scope only the run time can name, read as a
  value -- and read FIRST, so `Missing::X = boom` raises before `boom`
- `module_function` and `private`/`public`/`protected` of names this
  body does not write are the runtime's own verbs
- `h[*keys] = v` and `eval(src, nil, *rest)`, both one Array

Three reference-compiler gaps came out of it: **#66** a `using` in a
method body, **#70** a subjectless `case` with a splat `when`, and
**#69**, ze0's own pre-existing leak of an owned temporary built before
a raising operand.

### What still refuses

Seven programs of 5,940. Four are guards this compile cannot decide
whose branches give a class different superclasses (#68); the other
three are a `require` of a file the splice already took, a private
constant read through a scope this program cannot name, and a statement
in a `class << obj` body.

## W11 -- what the sweep found

357 programs compiled and answered wrong when the wave began. Three
landed; the sweep reads matched 5523, diverged 300.

**The rbconfig shim** (105, and 100 of them ffi). zeo rendered it from a
template at build time, so a front end had nothing to splice. The
PLATFORM facts are the running program's own -- `RUBY_PLATFORM` is
`<cpu>-<os>` and every road bakes it from the same build target -- so
the shim derives arch, host_os, host_cpu, the vendor, the triple, the
two object extensions and the two link flags from it in Ruby. What is
left is the five INSTALL paths, which zeo still fills and which only
mkmf and rubygems read. One static file, spliced by both roads.

It exposed a second bug: `# frozen_string_literal:` is a PER-FILE
pragma and ze0 read the main file's for the whole program. The shim
declares `false` on purpose (`RbConfig.expand` writes through its values
with `String#replace`), so ze0 compiling itself raised FrozenError.

**The install timeline.** ruby installs a `def` where it STANDS, so a
call written above a redefinition answers the body above it, and an
`alias` binds the body the definee carries when the alias runs. ze0
installed a class body's `def`s at boot. Two narrowings, both on the
road a `def` in a block already took:

- the FIRST `def` for a name keeps the boot row; a later one installs
  itself where it runs, carrying the visibility cursor it was written
  under, and the name stops folding at call sites
- a `def` whose name an `alias` in the same body reads FROM installs
  where it stands too

Two runtime bugs came with them, both carried by BOTH roads:
`Module#module_function :x` re-copied the compiled body rather than the
one the module carries now, and `main.singleton_methods` answered a
fixed pair (that one rode with W10).

### What is left, largest first

- **62** ffi. `layout` is a COMPILE-TIME form -- `lower/ffi/synth.rs`
  walks the declaration, computes each field's C offset and synthesizes
  the accessors -- and ze0 has none of it (#73)
- **28** `Ruby::Box`. A box's `eval` defines a method the next `eval`
  cannot find; zeo emits box-surrogate rows ze0 does not
- **18** a dynamic `Ractor.new`
- the rest is a `lang/methods` tail, several of which want the general
  form of the install timeline: EVERY class-body `def` at its own line,
  which is what `analyze::redefs` does on zeo's side

## What stays refused, by name

`method_missing`, `Ractor`, `Fiber`, `callcc`, and a run-time `require`
against a load path. `eval`, `binding`, `ObjectSpace` and refinements
have all since joined the subset. A program
using one is refused at its line. This list is the plan's edge and it is
in `README.md`'s subset section.

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
cargo xtask ze0-sweep --all                            # does it AGREE?
ruby ze0/measure.rb                                    # the README's table
```

Per step, in order:

1. Every new form has a program in `test/ze0/` whose answer was recorded
   from ruby, and every new refusal has a fixture.
2. **`cargo xtask ze0-sweep` over the directories the change touches.** A
   golden proves the form; the sweep proves the corpus. Every fix since
   W6 was found by the sweep and by nothing else.
3. All three roads agree byte for byte -- the differential, not "it ran".
4. `ZEO_RT_LEAKCHECK=1` stays clean.
5. A form outside the subset is still refused **at its line, by name**.
