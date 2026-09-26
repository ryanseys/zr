# How to use a library or a gem

This guide shows you which files a program's `require` can reach in a
zr build, and how to use a library that ruby does not ship.

zr compiles each file that a program requires into the binary, when it
builds. So a `require` works only for a file that zr can find at build
time, or for a file that the binary can compile when it runs (see
[A require that zr cannot read at build time](#a-require-that-zr-cannot-read-at-build-time)).
zr never uses the host's rubygems to find a gem: the same source gives
the same binary on any machine.

## Ruby's own library: nothing to do

A `require` of a library that ruby 4.0.7 ships works as in ruby:

```ruby
require "json"
require "set"
require "net/http"
require "csv"        # a bundled gem
```

zr reads these files from the default and bundled gems of ruby 4.0.7,
at the versions that ruby ships, and from `vendor/lib`. A small number
of names have no file in zr, for example `mkmf`. A `require` of one of
them raises `LoadError` when it runs.
[What zr supports](../reference/support.md) lists them.

A library with a C extension, such as `json`, `psych` or `zlib`, works
because zr has a Ruby port of its C. See
[How to port a C extension](port-a-c-extension.md).

## Your own files

Use `require_relative`, as in ruby:

```ruby
require_relative "lib/greeter"
```

A `require` of a path that starts with `./`, `../` or `/` also works.
zr looks in the working directory first, then in the directory of the
file that requires it.

## A pure-Ruby gem that ruby does not ship

Add the gem's `lib` directory to `$LOAD_PATH` with a literal path, then
require it. zr reads the literal when it builds, and compiles the gem's
files into the binary. The binary does not need the gem when it runs:

```ruby
$LOAD_PATH.unshift(File.expand_path("vendor/rainbow-3.1.1/lib", __dir__))
require "rainbow"
```

zr reads these literal forms: a String, `File.expand_path(string,
__dir__)` and `File.join(__dir__, string, ...)`, with `unshift`, `push`
or `<<`. You can copy the gem into your project (for example with
`gem unpack rainbow --target vendor`), so that the build does not
depend on where the gem is installed. `gem unpack` writes the gem to
`vendor/<name>-<version>`.

A gem that needs a C extension does not work this way: zr compiles no
C, and a binary cannot load a C extension.

## A require that zr cannot read at build time

A `require` of a name that zr cannot read or find at build time runs
when the program runs. For example, `require name` with a variable,
or a directory that the program adds to `$LOAD_PATH` with a computed
path. The binary then includes eval support (the compiler, about
90 MB), and compiles the file that it finds at run time. This is how
`require "bundler/setup"` with a Gemfile can reach installed gems.
It has these limits:

- The binary needs the file on the machine where it runs, at the same
  path, and the same versions of the pinned gems.
- A `wasm32-wasi` module refuses it: the tree-walking interpreter
  cannot run a file that zr did not compile into the module.
- zr does not test a Gemfile of third-party gems. A pure-Ruby gem that
  zr supports can work; a gem with a C extension does not.

See [Eval in a compiled program](../explanation/eval-in-a-compiled-program.md).

## zr in a Gemfile

Install zr with `gem install zr`, not with a Gemfile. zr's gemspec
pins each default and bundled gem of ruby 4.0.7 to one version, so
most bundles cannot resolve beside it.
