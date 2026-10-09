# How to use a library or a gem

This guide shows you which files a program's `require` can reach in a
zr build, and how to use a library that ruby does not ship.

zr compiles each file that a program requires into the binary, when it
builds. So a `require` works only for a file that zr can find at build
time, or for a file that the binary can compile when it runs (see
[A require that zr cannot read at build time](#a-require-that-zr-cannot-read-at-build-time)).
zr reads no installed gem unless you name it with `--gem` or a
Gemfile.lock ([Another version of a gem](#another-version-of-a-gem)):
the same source gives the same binary on any machine.

## Ruby's own library: nothing to do

A `require` of a library that ruby 4.0.7 ships works as in ruby:

```ruby
require "json"
require "set"
require "net/http"
require "csv"        # a bundled gem
```

zr reads these files from its own copy of ruby 4.0.7's standard
library (`vendor/ruby` in the gem): the default and bundled gems, at
the versions that ruby 4.0.7 ships. A gem that you install on the host
(for example a newer `csv`) does not change what the program gets. A
small number of names have no file in zr, for example `mkmf`. A
`require` of one of them raises `LoadError` when it runs.
[What zr supports](../reference/support.md) lists them.

A library with a C extension, such as `json`, `psych` or `zlib`, works
because zr has a Ruby port of its C. Some ports are at a later version
than ruby 4.0.7 ships, for example json 3.0.2; see
[Library versions](../reference/differences-from-ruby.md#library-versions).
To port another one, see
[How to port a C extension](port-a-c-extension.md). On macOS and on
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

## Another version of a gem

zr reads each gem from one of three places, in this order:

1. a `--gem` option of `zr run` or `zr build`;
2. the Gemfile.lock of `--gemfile PATH`, or of `BUNDLE_GEMFILE` (which
   `bundle exec` sets), as `bundle exec ruby` reads it;
3. zr's standard library, which is ruby 4.0.7's.

`--gem NAME=VERSION` uses a version that rubygems has installed, and
`--gem NAME=DIR` uses a directory with a gemspec or a `lib/`:

```console
$ zr run --gem csv=3.3.6 app.rb
$ zr build --gem rainbow=vendor/rainbow-3.1.1 app.rb -o app
```

With a Gemfile, run `bundle install`, then give the Gemfile to the
build. The build reads every gem in the lock, as installed on this
machine, and no other installed gem:

```console
$ zr build --gemfile Gemfile app.rb -o app
$ bundle exec zr build app.rb -o app          # the same, with zr in the Gemfile
```

zr needs no `bundle exec`, and does not use the host's bundler. It
reads the lock with its own copy of rubygems and bundler, which are
ruby 4.0.7's, as JRuby and TruffleRuby use their own. A Gemfile in the
program's directory does nothing until you name it, as for
`ruby app.rb`.

The binary contains the gems' files, so it does not need them when it
runs. A build with other gems is another build: `zr run` does not use
a binary that it kept for other gems.

Inside the binary, rubygems knows these gems and no others, as under
`bundle exec`. The binary carries each gem's name and version (its
gem manifest, which `zr inspect` prints), and `Gem::Specification` and
`Gem.loaded_specs` list them. `gem "rainbow", "~> 3.1"` succeeds when
the build had rainbow at a version that matches, and raises
`Gem::LoadError` otherwise. A `--gem` directory with no gemspec has no
version, so `gem` accepts it only with no requirement.

Unless you give it to `--native-ext`, these rules apply to a gem with
a C extension:

- A gem that zr ports (json, psych, bigdecimal and the others in
  [Library versions](../reference/differences-from-ruby.md#library-versions))
  works when its version is in the range whose C zr implements. zr
  then uses the gem's Ruby files with its own port of the C. Another
  version stops the build at the `require`:

  ```
  zr: app.rb:1: require of "json": json 2.18.0 (Gemfile.lock): zr implements the C part of json >= 2.20, < 3.1 only. Put a version in that range in the Gemfile, then run 'bundle install'.
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
  gem's files, and for a port, the version rule above: the default
  json of ruby 4.0.7 is 2.18.0, so a lock with it stops a build that
  requires json.

A program that uses eval carries zr's own copy of some libraries
(fileutils, pp, irb, reline, rubygems and others). A build of such a
program with another version of one of them stops, because ruby loads
only one copy of a library.

If zr cannot find a gem, it stops before the build and tells you what
to run, for example `rack 3.1.8 is in Gemfile.lock but not installed.
Run 'bundle install'`.

## A require that zr cannot find

A literal `require` in your own files that zr finds nowhere stops the
build, and the message tells you what to do: give the gem with
`--gem` or `--gemfile`, add the file, or guard the require:

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
path. The binary then includes eval support (the compiler: such a binary
is about 110 MB), and compiles the file that it finds at run time. This is how
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
Under `bundle exec` (or with `--gemfile`), a build reads the lock's gems
first; see
[Another version of a gem](#another-version-of-a-gem).
