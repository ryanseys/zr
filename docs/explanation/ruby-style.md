# How zr's Ruby is written

zr is a Ruby compiler written in Ruby, and it compiles itself. Thus its
code has two readers: people, and zr. The rules on this page keep the
code clear for people and fast when zr compiles it. Each rule has an
example from this repository.

The short form: write the Ruby that you would write for any program,
and when zr makes that Ruby slow, fix zr.

## Idiomatic Ruby first; fix zr when it is slow

The compiled compiler (stage 1, see [Bootstrapping](bootstrapping.md))
runs the same code as ruby does. A workaround that makes the source less
clear, so that the compiled compiler runs faster, is a defect in zr. The
correct fix is in the compiler or the runtime, where every program gets
it.

- `zr-dev compile --zr --check` compares the compile time with the
  committed baseline in `benchmark/results/compile/`. Run it before and
  after a refactor. The `compiled / ruby` row is the number that shows
  a slow idiom.
- When an idiom is slow under zr, add a benchmark for it in
  `benchmark/`, then make the compiler or the runtime fast, then use the
  idiom.

Two examples. A `case` with many `when` arms on classes, as in
`case node when Hir::Send ...`, once tested each arm in turn. zr now
keeps a table from the subject's class to its arm at each such site
(`CaseCache`, `lib/zr/runtime/kernel/cache.rb`), so the long `case` in the HIR
builder and in the lowering is fast. And zr once ran `Struct` through the
core's generic code, so the compiler used its own record class. Struct
and Data construction and member access are now kernel entries, and the
HIR nodes are Structs again.

## Composition over large mixins

A module that is included in a class shares all of that class's
instance variables. Eleven such modules on one class make one object
with hundreds of methods and no boundaries. Give a part with its own
state its own object, with a small interface back to the object that
uses it.

- `Hir::Build::Patterns::Match` (`lib/zr/hir/patterns.rb`) holds its
  own state and calls back into the builder through `@b`.
- The tools are small `Command` objects (`tool/lib/zr/dev/command.rb`),
  each with its own options and `run`, not one module of functions.

A module or a reopened class can still split one large object into files
by topic, when the parts share the object's state and call its helpers
freely: `Lower::Function`'s `Sends`, `Regions` and `Tracing`,
`Hir::Build`'s `build/literals.rb` and `build/requires.rb`, and the
aarch64 codegen's `codegen/layout.rb`. A separate object for such a
part would need a wide public interface to the object that it came
from. Keep the part's own state together instead: the inline copy's
state is one `Inline::Site` value, not four instance variables.

## One copy of each fact and helper

- `Zr::Bytes` (`lib/zr/bytes.rb`) is the one `align`, `pad` and LEB128
  encoder. Before it, nine copies of `align` were in the backends, the
  object writers and the IR interpreter.
- `Hir.each_child` (`lib/zr/hir/node.rb`) is the walk over a node's
  children that the escape, scope and builder passes share.
- `lib/zr/version.rb` is the one source of the ruby version and
  revision. `test/unit/layout_test.rb` fails when `.ruby-version`,
  `lib/zr/runtime/core/env.rb` or CI disagrees with it.
- A generated file has a generator in `tool/gen/`, and its header names
  the command that writes it (`zr-dev gen <name>`). Do not edit it by
  hand; change the generator.

## Values are Structs and Data

A record of named fields is a `Struct` when code changes its fields
after construction, and a `Data` when it does not. A keyword argument
or a named constructor replaces a long list of positional arguments:

```ruby
Send.of(recv, :each, [], line, block: block)                      # clear
Send.new(recv, :each, [], line, false, false, block, nil, false)  # not clear
```

`Hir::Send.of` (`lib/zr/hir/node.rb`) takes the fields that most calls
leave at their defaults as keywords.

## Read the environment once

Read a `ZR_*` variable through `Zr::Config.current`
(`lib/zr/config.rb`), not with `ENV[...]` in the middle of the code, and
never into a constant when a file loads. A constant that holds an
environment value sees the value of the first process that loaded the
file, and a test cannot change it. `Config.with(...)` sets values for a
test, and a forked child that changes the environment calls
`Config.reset!`. `test/unit/config_test.rb` fails when another file in
`lib/` reads a `ZR_*` variable.

## Layers depend downward

The front end (`hir`), the lowering (`lower`), the IR (`ir`), the
machine dialect (`machine`), the backends (`backend`) and the object
writers (`obj`) are layers. A layer uses the layers below it and the
leaf utilities in `lib/zr/*.rb`, and nothing above it.
`test/unit/layering_test.rb` reads every `require_relative` under
`lib/zr` and fails on an edge that goes up. It has no exceptions. For
example, the arm64 relocations are in `obj/relocs/aarch64.rb`, because
the object writers apply them, and the machine dialect knows only the
signatures of its raw functions (`Machine::RAW`); the native build gets
their code from the backend.

## Errors

- Rescue the error that you expect, not `StandardError`. When a broad
  rescue is necessary (a cache that must not stop a build), say why in a
  comment.
- A form that zr does not support is a refusal. Every refusal class
  includes `Zr::Refusal` (`lib/zr/refused.rb`). Each class keeps its own
  superclass, because the exit status depends on it: 3 for a program
  that zr refuses, 1 for a backend that cannot write it.
- Give the cause when you raise again: `raise Refused, e.message, cause: e`.

## Objects keep one shape

Set every instance variable in `initialize`, in a fixed order, also
when its first value is nil. zr's instance variable cache and YJIT's
object shapes then see one layout for each class.
`Lower::Function#initialize` (`lib/zr/lower/function.rb`) sets all of
the variables that its modules use.

## Tools

A maintainer tool is a `zr-dev` command in `tool/`, not a rake task. The
`Rakefile` keeps only the standard entry points. A tool takes options
with OptionParser, loads what it needs when it runs, and is compiled by
zr into `bin/zr-dev` (see [Tools](../reference/tools.md)).

## Lint

`rake lint` runs RuboCop's Lint cops, which find defects, and a short
list of other cops (`.rubocop.yml`), each with the reason that it is on:

- the Performance plugin (rubocop-performance), for the allocations and
  calls that the compiler's hot paths do not need;
- the Minitest plugin (rubocop-minitest), for one form of each
  assertion;
- Style and Naming cops that keep one form where the code had two:
  quotes, ternaries, semicolons, `lambda.call`, rescue modifiers,
  mutable constants, trivial readers, the core collection methods,
  anonymous block forwarding, and `?` on a method that answers true
  or false.

Add another cop only when it finds real problems in this code, one cop
at a time, with the reason in `.rubocop.yml`. Do not add a cop that
makes large edits for small gains, or a formatter: blame stays useful.
When a new cop fires on a lot of existing code, list that code in a
`.rubocop_todo.yml` and fix it in small changes.

## Comments and names

Comments and docs use plain technical English: short sentences, active
voice, and one term for one concept (see the
[glossary](../reference/glossary.md)). A comment says why, not what the
code already says.
