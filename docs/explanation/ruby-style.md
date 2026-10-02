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

- `Hir::Build::Patterns::Match` (`lib/zr/hir/build/patterns.rb`) holds its
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

- `Zr::Bytes` (`lib/zr/bytes.rb`) is the one `align`, `pad`, LEB128
  and `zigzag` encoder. Before it, nine copies of `align` were in the
  backends, the object writers and the IR interpreter.
- `Dev.parallel_map` (`tool/lib/zr/dev/parallel.rb`) is the one worker
  pool of the tools. It gives the results in the order of the items.
  Before it, five tools had a pool of their own.
- A `case` arm that writes out the members of a constant, so that the
  compiled `case` makes no array on each step, names the constant in a
  comment. `test/unit/case_lists_test.rb` fails when the arm and the
  constant do not agree.
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

- When some methods pass the same group of values, make the group a
  record: `Lower::Function::CallSite` (`lib/zr/lower/function/call_site.rb`)
  holds the values of one send site, and `Lower::Function::Loop`
  (`lib/zr/lower/function/loop.rb`) holds the labels of one loop.
- A boolean argument is a keyword: `f(x, wide: true)`, not `f(x, true)`.
  `true` alone does not say what it means.

## Read the environment once

Read a `ZR_*` variable through `Zr::Config.current`
(`lib/zr/config.rb`), not with `ENV[...]` in the middle of the code, and
never into a constant when a file loads. A constant that holds an
environment value sees the value of the first process that loaded the
file, and a test cannot change it. `Config.with(...)` sets values for a
test, and a forked child that changes the environment calls
`Config.reset!`. `test/unit/config_test.rb` fails when another file in
`lib/` reads a `ZR_*` variable. `Config.flag?` reads a variable that is
on or off: unset or empty gives the default, `0` is off, and every
other value is on.

## State of the process is in Zr::Session

A value that zr reads or builds one time for each process (the
settings, the library roots, the runtimes, the parse memo, the digests
of zr's own files) is a memo of `Zr::Session` (`lib/zr/session.rb`),
not an instance variable of a module:

```ruby
def self.loaded = Session.current.memo(:runtimes) { {} }  # lib/zr/runtime.rb
```

`Session#reset!` drops the memos that the environment decides and the
built runtimes, so the next build makes them again as a new process
would. The warm server (`Server#fresh!`, `lib/zr/server.rb`) calls it
before each build. It keeps the runtimes (`reset!(keep_runtimes: true)`)
when the settings and the runtime digest stay the same and the build
has no `--path-root`. A test that needs a value of its own calls
`Session#set` and `Session#forget`. The ThreadSafety cops (see
[Lint](#lint)) find state on a class or a module, because the server,
the test workers and the host machine run threads.

## Layers depend downward

The front end (`hir`), the lowering (`lower`), the IR (`ir`), the
kernel's typed lowering (`machine`), the backends (`backend`) and the object
writers (`obj`) are layers. So are the library roots (`library`), which
the front end reads, and the caches between builds (`cache`). A layer
uses the layers below it and the leaf utilities in `lib/zr/*.rb`, and
nothing above it.
`test/unit/layering_test.rb` reads every `require_relative` under
`lib/zr` and fails on an edge that goes up. It has no exceptions. For
example, the arm64 relocations are in `obj/relocs/aarch64.rb`, because
the object writers apply them, and the typed lowering knows only the
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
with OptionParser, and loads what it needs when it runs; `bin/zr-dev`
runs it (see [Tools](../reference/tools.md)).

- A command sets the starting value of each option in its `defaults`
  method, which `Command#initialize` calls
  (`tool/lib/zr/dev/command.rb`). Thus each command has one shape.
- A command that must stop calls `fail!(message)`. It prints the
  message and exits with status 1.
- A command whose first word names a command of its own (`zr-dev gen`,
  `zr-dev cache`, `zr-dev gems`, `zr-dev vendor`) is a `Group`.
- The tools share `Dev.parallel_map`, `Dev.git`, `Dev.revision`,
  `Dev.tree_files` and `Dev.timed`. Do not write another copy in a
  tool.

The `zr` command has the same form, without OptionParser (optparse is
not in `lib/`): `CLI.start` (`lib/zr/cli.rb`) finds the command class
in the frozen table `CLI::COMMANDS`, and each command is a
`CLI::Command` in `lib/zr/cli/commands/`.

## Where a constant lives

The path of a file names the constant that it holds, as Zeitwerk would
name it: `lib/zr/cache/store.rb` holds `Zr::Cache::Store`, and
`lib/zr/cli/commands/compile.rb` holds `Zr::CLI::Commands::Compile`.
zr does not use Zeitwerk; every `require_relative` stays literal, so
that zr finds each file when it compiles itself.
`test/unit/constant_layout_test.rb` parses each file of `lib/zr` (not
the runtime) and fails when a file does not define or reopen the
constant of its path. A path word that is not a plain capitalized word
is in its `INFLECT` table (`cli` is `CLI`, `ir` is `IR`, `macho` is
`MachO`). A topic file that adds one part to a parent constant (for
example `hir/build/literals.rb`, a part of `Hir::Build`) is in its
`REOPENS` table, and a file that cannot follow the rule is in its
`EXCEPTIONS` table, each with its reason.

A group of files that belong together is a namespace, not a set of
functions on `module Zr`:

| Namespace | Files | Holds |
|---|---|---|
| `Zr::Session` | `session.rb` | the memos of one process |
| `Zr::Library::Layout`, `Roots`, `Ports`, `Vendor`, `Stdlib` | `library/` | the library that a program requires, and where each part of it is |
| `Zr::Cache::Store`, `Janitor`, `Parse`, `Unit`, `Run`, `Lowering`, `Lowering::Core`, `Lowering::EvalSupport` | `cache/` | the caches between builds, all in one content store |
| `Zr::CLI::Commands::*` | `cli/commands/` | one class for each `zr` command |
| `Zr::Server`, `Zr::Server::Client` | `server.rb`, `server/client.rb` | the warm compiler of `zr-dev serve`, and the client in `exe/zr` |
| `Zr::GcTuning` | `gc_tuning.rb` | the collector limits and YJIT of a compile (`GcTuning.current`) |
| `Zr::Runtime.for`, `Zr::EvalSupport.for`, `Zr::Program.build` | `runtime.rb`, `eval_support.rb`, `program.rb` | the runtime of a target, the eval support of a target, and a program's build |
| `Zr::LoadTables`, `Zr::SymbolNumbering` | `load_tables.rb`, `symbol_numbering.rb` | the load tables that a binary carries, and the link's numbers for symbols |
| `Zr::Host`, `Zr::Timing`, `Zr::SourceGuard` | `host.rb`, `timing.rb`, `source_guard.rb` | `Host.compiled?`, the phase times, and the check that no source changed during a build |

## Types

A pilot checks the types of a few files with Steep (`zr-dev typecheck`,
the `Steepfile`). A file with methods has inline RBS annotations:

```ruby
#: (Integer n, Integer a) -> Integer
def align(n, a) = (n + a - 1) & ~(a - 1)
```

A file that assigns a `Struct` or a `Data` record to a constant has its
types in `sig/pilot/`, because the inline form cannot give a type to the
fields of such a record. Put the methods of such a record in a reopened
class, not in the block of `Data.define`, so that Steep sees them in
their class (`lib/zr/load_tables.rb`). To add a file to the
check, annotate it and add it to the `Steepfile`. The rest of `lib/` is
not checked yet.

## Lint

`rake lint` runs RuboCop with the cops that `.rubocop.yml` turns on.
Each cop has the reason that it is on beside it. All other cops are
off (`DisabledByDefault`).

- The Lint cops, which find defects. A few that report deliberate
  choices in this code are off, each with its reason.
- Layout: only `LineLength` (150), `TrailingWhitespace` and
  `EmptyLines`, so that a diff stays readable. No formatter, so blame
  stays useful. `Style/FrozenStringLiteralComment` is on too.
- The Minitest plugin (rubocop-minitest), for one form of each
  assertion, with the better failure message.
- The Performance plugin (rubocop-performance), for the allocations and
  calls that the compiler's hot paths do not need.
- Style cops that keep one form where the code had two: `StringLiterals`
  and `StringLiteralsInInterpolation` (double quotes),
  `NestedTernaryOperator`, `TrivialAccessors`, `Semicolon`,
  `LambdaCall`, `MutableConstant` and `RescueModifier`; and the core
  collection methods: `ArrayIntersect`, `CollectionCompact`,
  `HashExcept`, `HashSlice`, `InverseMethods`, `MapToSet`,
  `SelectByRange` and `SymbolProc`.
- Forwarding: `Naming/BlockForwarding` (`def f(&) = g(&)`) and
  `Style/ArgumentsForwarding` (`def f(*, **) = g(*, **)`). zr compiles
  the anonymous forms.
- `Naming/PredicateMethod`: a method that answers true or false ends
  in `?`. `call`, and `run` of a `zr-dev` command, are allowed.
- Parameters: `Style/OptionalBooleanParameter` (a boolean is a keyword)
  and `Metrics/ParameterLists` (at most 5 positional parameters and 3
  optional ones; keywords do not count).
- The ThreadSafety plugin (rubocop-thread_safety): state on a class or a
  module, and `Dir.chdir`. `ThreadSafety/NewThread` is off, because zr
  starts threads on purpose.

The runtime's core, extensions and libraries are not linted yet: much of
that code follows upstream code. The kernel gets the Lint cops only.

Add another cop only when it finds real problems in this code, one cop
at a time, with the reason in `.rubocop.yml`. Do not add a cop that
makes large edits for small gains, or a formatter. When a new cop fires
on a lot of existing code, list those files in `.rubocop_todo.yml`, and
fix them in small changes. The todo file now lists the files that the
ThreadSafety cops, `Metrics/ParameterLists` and `Layout/LineLength`
found when they came in. When a file is fixed, delete it from the list.

## Comments and names

Comments and docs use plain technical English: short sentences, active
voice, and one term for one concept (see the
[glossary](../reference/glossary.md)). A comment says why, not what the
code already says.
