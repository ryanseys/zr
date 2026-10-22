# What zr supports

zr compiles a Ruby program only when the binary gives exactly
what ruby gives ([the contract](../explanation/the-contract.md)).
Where it cannot promise that, it refuses the program with exit
status 3 and names the form and its line. This page lists what
zr refuses, as the compiler itself lists it. Other differences
from ruby, all on purpose, are in
[Differences from ruby](differences-from-ruby.md), and what each
target can do is in [Targets](targets.md).

## Syntax that zr refuses

The compiler refuses these forms by name. Any other syntax node
that it does not know is refused with the node's name, for
example `interpolated xstring (InterpolatedXString)`.

- A block in an index target
- A dynamic constant path
- Redo outside a block or loop
- Retry outside a rescue clause
- `BEGIN { }` outside the toplevel
- `break` or `next` outside a block or loop

## Libraries that a program cannot require

A `require` of one of these names compiles, and raises
`LoadError` with the reason when it runs, so a guarded
require that never runs costs nothing. Every other library of
the ruby that zr pins is there: the default and bundled gems, and ruby's
own `lib/`. A gem that ruby does not ship comes from the gems that rubygems has
installed, or from the Gemfile.lock that `BUNDLE_GEMFILE` names. A gem with a C extension needs a port, or
`--native-ext` on macOS and on Linux (see
[How to use a library or a gem](../how-to/use-a-library-or-gem.md)
and [How to use a C extension](../how-to/use-a-c-extension.md)).

### `aarch64-apple-darwin`, `aarch64-linux-musl`, `x86_64-linux-musl`, `x86_64-linux-gnu`, `aarch64-linux-gnu`, `wasm32-wasi`

- `mkmf`, which writes a C extension's Makefile: zr runs it in the host ruby when it builds a gem's extension
- `mkmf/depend`, a part of mkmf: zr runs mkmf in the host ruby when it builds a gem's extension
- `ruby/prism/ffi`, the FFI half of Ruby::Prism: this runtime's Ruby::Prism is a Ruby port of the C
- 59 encoding libraries under `enc/`: ruby loads them itself, and zr's runtime has every encoding built in

## Tests that a target may fail

Each target can have a baseline: the program tests (below
test/programs) that it may fail, each with the reason, in
`test/baselines/<target>.txt` (for example
[wasm32-wasi.txt](../../test/baselines/wasm32-wasi.txt)). A test in a
baseline that passes fails the run, so those files are current.
After a new ruby, `upgrade.txt` there lists the tests that it changed
and zr does not match yet, on every target.

## Keep this page current

A person keeps this page, not a generator. A change that makes the
compiler refuse a new form, or that adds a library that a program
cannot require, adds its line here.
