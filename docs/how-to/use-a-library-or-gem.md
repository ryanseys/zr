# How to use a library or a gem

This guide shows you which files a program's `require` can reach in a
zr build, and how to use a library that ruby does not ship.

zr compiles each file that a program requires into the binary, when it
builds. So a `require` works only for a file that zr can find at build
time, or for a file that the binary can compile when it runs (see
[A require that zr cannot read at build time](#a-require-that-zr-cannot-read-at-build-time)).
zr finds gems as ruby does: from the gems that rubygems has installed,
or from a Gemfile.lock when `BUNDLE_GEMFILE` names one
([Installed gems and Gemfiles](#installed-gems-and-gemfiles)).

## Ruby's own library: nothing to do

A `require` of a library that ruby ships works as in ruby:

```ruby
require "json"
require "set"
require "net/http"
require "csv"        # a bundled gem
```

zr reads these files from its own copy of the pinned ruby's standard
library (`vendor/ruby` in the gem): the default and bundled gems, at
the versions that the pinned ruby ships. An installed gem that is newer
than zr's copy (for example a newer `csv`) comes first, as in ruby; see
[Installed gems and Gemfiles](#installed-gems-and-gemfiles). A
small number of names have no file in zr, for example `mkmf`. A
`require` of one of them raises `LoadError` when it runs.
[What zr supports](../reference/support.md) lists them.

A library with a C extension, such as `json`, `psych` or `zlib`, works
because zr has a Ruby port of its C. For json, stringio, strscan,
date, digest, etc, fcntl, bigdecimal, nkf, syslog, rbs, racc, ffi, prism and zlib,
a build for the machine it runs on
links the gem's own C extension instead, the one that the pinned ruby
installed (`ZR_NATIVE_EXT=-json` keeps json's port). The port serves a
build for another target and a ruby without the gem. psych and openssl
keep their ports, because their own C loads a library (libyaml,
libssl) that a binary cannot carry. io-console
keeps its port until zr's IO objects carry the T_FILE tag that its C
tests. Some ports are at a later version
than the pinned ruby ships, for example json 3.0.2; see
[Library versions](../reference/differences-from-ruby.md#library-versions).
On macOS and on
aarch64 Linux, a binary can also run a gem's real C extension; see
[How to use a C extension](use-a-c-extension.md).

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

A gem that needs a C extension does not work this way unless you give
it to `--native-ext` ([How to use a C extension](use-a-c-extension.md)).
The rules below tell what zr does with one.

## Installed gems and Gemfiles

zr finds gems from the environment, as ruby, rubygems and bundler do.
zr has no options for this.

With `BUNDLE_GEMFILE` set (`bundle exec` sets it), the build reads
every gem of that Gemfile's lock (`Gemfile.lock`, or `gems.locked` for
`gems.rb`). These gems come before zr's standard library, as
`bundle exec ruby` puts them first on the load path. Run
`bundle install`, then build:

```console
$ BUNDLE_GEMFILE=Gemfile zr build app.rb -o app
$ bundle exec zr build app.rb -o app          # the same, with zr in the Gemfile
```

zr's own development Gemfile never counts.

Without `BUNDLE_GEMFILE`, the build reads the gems that rubygems has
installed on its path, at the newest version of each. The path is
`GEM_PATH` (else `~/.gem/ruby/<ruby_version>` and the default gem
directory of the ruby on `PATH`), then `GEM_HOME` (else that default
directory). These gems come after zr's standard library, as ruby
searches `$LOAD_PATH` first and its gems only then. There are two
exceptions, as in rubygems' `Kernel#require`:

- An installed gem that is newer than zr's copy of a default gem, a
  bundled gem or a port comes first. ruby's `require` of a default
  gem's file activates the newest installed version.
- A literal `gem` line in the program's main file selects a version.
  The build takes the newest installed version that meets the
  requirement, and that gem comes first:

  ```ruby
  gem "json", "2.19.1"
  require "json"
  ```

To use a gem from a source directory that is not installed, do one of
these:

- Give its `lib` directory with `-I DIR/lib`, or add it to
  `$LOAD_PATH` as in
  [A pure-Ruby gem that ruby does not ship](#a-pure-ruby-gem-that-ruby-does-not-ship).
- Put `gem "rainbow", path: "vendor/rainbow-3.1.1"` in a Gemfile, then
  build with `BUNDLE_GEMFILE` or `bundle exec`.
- Install the gem (`gem install`, or a directory in `GEM_HOME` or
  `GEM_PATH`).

`zr gems` lists the gems that a build reads, with the version and the
source of each ([`zr gems`](../reference/cli.md#zr-gems-options-filerb)).

zr needs no `bundle exec`, and does not use the host's bundler. It
reads the lock with its own copy of rubygems and bundler, which are
the pinned ruby's, as JRuby and TruffleRuby use their own. A Gemfile in the
program's directory does nothing until `BUNDLE_GEMFILE` names it, as for
`ruby app.rb`.

The binary contains the gems' files, so it does not need them when it
runs. A build with other gems is another build: `zr run` does not use
a binary that it kept for other gems. The build cache key includes the
gem path variables and the time of each gem directory's
`specifications`, so the next build after a `gem install` or a
`gem uninstall` finds the gems again. The same source can build a
different binary on a machine with other installed gems. `zr inspect`
lists the gems that a binary carries.

The binary carries each gem's name and version (its gem manifest,
which `zr inspect` prints). Inside the binary, the gems of a Gemfile's
lock are active from the start, as under bundler's setup, and
`Gem.loaded_specs` has them before the first line. An installed gem
is active from the first `require` of one of its files, as rubygems
does it. A default or bundled gem is also active from the first
`require` of one of its files, as in ruby. `Gem::Specification` lists
the gems with the default and bundled gems of the ruby install that
runs the binary. `gem "rainbow", "~> 3.1"` succeeds when the build had
rainbow at a version that matches, and raises `Gem::LoadError`
otherwise.

Unless you give it to `--native-ext`, these rules apply to a gem with
a C extension:

- A gem that zr ports (json, psych, bigdecimal and the others in
  [Library versions](../reference/differences-from-ruby.md#library-versions))
  works when its version is in the range whose C zr implements. zr
  then uses the gem's Ruby files with its own port of the C. Another
  version builds without its C part, as below, and says so; give it
  to `--native-ext` to link its own C:

  ```
  zr: warning: json 2.18.0 (Gemfile.lock): zr implements the C part of json >= 2.20, < 3.1 only. Put a version in that range in the Gemfile, then run 'bundle install', or link the gem's own C with --native-ext json=2.18.0: its Ruby files compile, and a require of its C part raises LoadError if it runs
  ```

- Any other gem with a C extension builds without its C part: zr
  compiles its Ruby files, and a `require` of the C part raises
  `LoadError` if it runs, as in a ruby where the extension did not
  build. A gem whose Ruby has a fallback for that `LoadError` (cgi's
  escape functions) works. The build says which gem lost its C part:

  ```
  zr: warning: cgi 0.5.2 (Gemfile.lock) has a C extension, and zr has no port of it. zr compiles only Ruby: its Ruby files compile, and a require of its C part raises LoadError if it runs
  ```

- A lock can name a default gem (a gem that ruby itself installs) at
  ruby's own version. zr then uses its standard library's copy of the
  gem's files, and for a port, the version rule above: when the default
  json of the pinned ruby is older than the range that the json port
  implements, a lock with it builds json without its C part unless
  `--native-ext` links that C.

A program that uses eval carries zr's own copy of some libraries
(fileutils, pp, irb, reline, rubygems and others). A build of such a
program with another version of one of them stops, because ruby loads
only one copy of a library.

If zr cannot find a gem, it stops before the build and tells you what
to run, for example `rack 3.1.8 is in Gemfile.lock but not installed.
Run 'bundle install'`.

## A require that zr cannot find

A literal `require` in your own files that zr finds nowhere makes the
build warn. The require raises `LoadError` if it runs. The message
tells you what to do: install the gem (`GEM_HOME`, `GEM_PATH`), name a
Gemfile that has it (`BUNDLE_GEMFILE`), add the file, or build with
`--allow-runtime-require`. A guarded require gives no warning:

```ruby
begin
  require "rainbow"
rescue LoadError
  # run without colors
end
```

A guarded require waits for the run time, as below. So does every
such require when you build with `--allow-runtime-require`. See
[the require gate](../reference/cli.md#the-require-gate).

## A require that zr cannot read at build time

A `require` of a name that zr cannot read or find at build time runs
when the program runs. For example, `require name` with a variable,
or a directory that the program adds to `$LOAD_PATH` with a computed
path. The binary then includes eval support (the compiler, which makes the
binary some times larger), and compiles the file that it finds at run time. This is how
`require "bundler/setup"` with a Gemfile can reach installed gems.
It has these limits:

- The binary needs the file on the machine where it runs, at the same
  path.
- A `wasm32-wasi` module refuses it: the tree-walking interpreter
  cannot run a file that zr did not compile into the module.
- zr does not test a Gemfile of third-party gems. A pure-Ruby gem that
  zr supports can work; a gem with a C extension works only with
  `--native-ext`.
  [Gem compatibility](../reference/gem-compat.md) lists how far each
  popular gem gets.

See [Eval in a compiled program](../explanation/eval-in-a-compiled-program.md).

## zr in a Gemfile

zr has no gem dependencies, so you can add it to a Gemfile
(`gem "zr", group: :development`) or install it with `gem install zr`.
Under `bundle exec` (or with `BUNDLE_GEMFILE`), a build reads the lock's
gems first; see
[Installed gems and Gemfiles](#installed-gems-and-gemfiles).
