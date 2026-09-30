# Changelog

All notable changes to zr are in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and zr uses
[Semantic Versioning](https://semver.org). Before 1.0, a minor version
can change the command line or the environment variables.

## [Unreleased]

The first public release.

### Added

- `gem install zr` installs the `zr` command on ruby 4.0.7: `run`,
  `build`, `machine`, `targets`, `doctor`, `cache`, `version` and
  `help`. The gem has no dependencies: it carries ruby 4.0.7's
  standard library (`vendor/ruby`), so the install downloads only zr, and
  compiles nothing. zr runs on ruby 4.0.7 or a later 4.0 release.
- A compiled program gives ruby 4.0.7's output byte for byte, or zr
  refuses it at build time with exit status 3. A refusal gives the
  file, the line and the column, the form, the source line with a
  caret, and a link to `docs/reference/support.md`, which lists what
  zr refuses.
- Targets: `aarch64-apple-darwin` binaries and `wasm32-wasi` modules on
  any host, static `aarch64-linux-musl` binaries with a musl toolchain,
  and object files. zr links a macOS binary itself, so it needs no C
  compiler and no linker.
- zr has no C. prism 1.9.0 parses through a Ruby port of its C; zlib is
  a port of zlib 1.3.1; `Regexp` is a port of Onigmo, CRuby 4.0.7's
  engine; json, psych (with libyaml), openssl, socket, digest, date,
  stringio, strscan, bigdecimal, nkf, ffi and others have Ruby ports of
  their C halves. `require "openssl"` in a macOS binary opens the
  host's OpenSSL 3 when it runs.
- A program can require all of ruby 4.0.7's library, and a pure-Ruby
  gem through a literal `$LOAD_PATH`. A program that evals, or requires
  a computed name, carries the compiler (native targets) or a
  tree-walking interpreter (wasm32-wasi).
- An installed zr on an Apple Silicon Mac builds a compiled copy of
  itself at its first build, which makes later builds faster
  (`ZR_COMPILED=0` skips it). Other hosts run zr under ruby. A build
  keeps the runtime, the prelinked image and each file's machine code
  in one content store (`<cache>/store/`), which `zr cache` shows and
  cleans. Each build names in a root what the next build needs, so a
  clean keeps it, and an installed zr evicts the entries used longest
  ago to stay under `ZR_CACHE_MAX_GB`.
- `zr run` and `zr build` read another version of a gem from
  `--gem NAME=VERSION` or `--gem NAME=DIR`, and from the Gemfile.lock
  of `--gemfile` or `BUNDLE_GEMFILE`, before zr's standard library. zr
  reads the lock with its own copy of bundler and needs no `bundle exec`. A gem with a C
  extension that zr does not port, or a port's gem outside the
  versions whose C zr implements, stops the build at its `require`.
- `zr gems` lists the gems that a build reads and where each comes
  from. Each binary carries a manifest of its gems, which
  `zr inspect` and `zr build --print-gems` print. `zr diff` runs a
  program under ruby and as a zr binary, and names and shows the
  difference.
- A literal `require` in the program's own files that zr cannot find
  stops the build with the fix, unless `rescue LoadError` guards it
  or the build has `--allow-runtime-require`.
- `zr doctor` checks the ruby, the host's targets, wasmtime, OpenSSL,
  the standard library, the cache and the compiled compiler, and says
  what to do for each problem. [How to install zr](docs/how-to/install.md)
  shows how to get ruby 4.0.7, and lists each problem and its fix.
- An error prints one line and no backtrace (`ZR_DEBUG=1` shows it).
  A bad `ZR_*` value exits with status 2 and names a value that works.
  Ctrl-C exits with status 130. Every command takes `--help`, and a
  mistyped command gets a suggestion.
- The first build says that it builds the runtime and the compiled
  compiler, which take some minutes one time. Two builds at once build
  the runtime one time. A compiled compiler that did not build is tried
  again a day later, at most three times.
- A binary loads on macOS 14 or later, and its `RUBY_PLATFORM` is
  `arm64-darwin23`, the platform of macOS 14. A glibc aarch64 Linux
  runs the static `aarch64-linux-musl` binary, and links it with
  `musl-gcc` or `$CC`. On a host that runs no native target, `zr run`
  says to use `--emit wasm`.
- MIT License. `THIRD_PARTY_NOTICES.md` names every part from other
  work, and `licenses/` holds the license texts that have no other copy
  in the gem.
- Documentation in `docs/`: tutorials, how-to guides, reference and
  explanation, with a performance page and a support page that
  `zr-dev gen` writes from the benchmark reports and from the compiler.
- For contributors: `bin/setup`, `bin/test` (with `--changed`),
  `bin/console`, the `zr-dev` tools, and CI for all three targets.

### Planned for 0.2

- `--gems host`: build with the gems that the host's rubygems has
  installed.
- `zr gem install`: a gem home of zr's own, for gems that a build reads.

[Unreleased]: https://github.com/ryanseys/zr/commits/main
