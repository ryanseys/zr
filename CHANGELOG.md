# Changelog

All notable changes to zr are in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and zr uses
[Semantic Versioning](https://semver.org). Before 1.0, a minor version
can change the command line or the environment variables.

## [Unreleased]

The first release as a RubyGem.

### Added

- `gem install zr` installs the `zr` command: `run`, `build`, `machine`,
  `targets` and `version`.
- The gem installs on any host. zr links an `aarch64-apple-darwin`
  binary itself, so it needs no `cc`; every host builds those binaries,
  WASI modules and objects. A native build this host cannot link exits
  with status 3 and says why.
- zr has no C. prism 1.9.0 parses through its Ruby half over a Ruby
  port of its C (`runtime/ext/prism/ruby`), on the host and in every binary;
  zlib is a port of zlib 1.3.1 in the kernel dialect, and `Regexp` a port
  of Onigmo, CRuby 4.0.6's engine, in Ruby. All of them work on wasm, and
  the install compiles nothing.
- `require "openssl"` works in a macOS binary. The binary opens the
  host's OpenSSL 3 (from `OPENSSL_DIR`, else Homebrew or MacPorts) when
  the `require` runs, and raises `LoadError` naming the places it looked
  when the library is absent. The gem's Ruby half is vendored unedited,
  and its C half is Ruby over library calls, so the cryptography is the
  library's own. ruby 4.0.6's `test/openssl` passes over the port.
- `Obj::MachO::Executable` links a program beside the runtime's objects
  and writes the signed binary. The runtime is linked once, at fixed
  addresses, and kept in the cache (`prelink-<digest>.bin`), so a link
  relocates only the program: 0.08 s for a small program. `ZR_LINKER=cc`
  links with the system linker instead, and `cc` links what zr's linker
  refuses.
- MIT License; `THIRD_PARTY_NOTICES.md` names every vendored part.
- Documentation in `docs/`: tutorials, how-to guides, reference and
  explanation.
- `bin/setup`, `bin/test` and `bin/console` for work in a checkout.
  `bin/test` builds the runtime when it is missing or out of date.
- `zr help <command>` and `zr <command> --help`.

### Changed

- The project is `zr`, formerly `ze0`: the gem, the `zr` command, the
  `Zr` module, the `ZR_*` environment variables and the cache directory
  (`~/Library/Caches/zr`) all take the new name. The old names do not
  work any more.
- The pure-Ruby library a program requires comes from gems, not from
  copies in the gem. `zr.gemspec` depends on ruby 4.0.6's default and
  bundled gems at the versions it ships, and on `rubygems-update` for
  rubygems and bundler, each pinned exactly; `vendor/lib` keeps only the
  19 files no gem ships. A build refuses by name a pinned gem that is
  not installed, or whose files are not the version's.
- The runtime cache goes to the user's cache directory
  (`~/Library/Caches/zr` on macOS), or to `ZR_CACHE`.
- `cc` runs with `DEVELOPER_DIR` and `SDKROOT` pinned to the
  install the SDK comes from, so zr links with the macOS 27.0 SDK when
  the selected Xcode is older than the Command Line Tools.
- `Obj::MachO::Executable` decides what libSystem defines from a
  committed list, so a link answers the same on every host.
- `zr run` gives every word after the program file to the program. A
  wrong command line prints one line that says what is wrong, and exits 2.
- The runtime sources are in `runtime/` (was `rt/`), and the cache in a
  checkout is `tmp/cache/` (was `tmp/rt/`).
- Environment variables: `ZR_LINKER` (was `ZR_LINK`), `ZR_COMPILED`
  (was `ZR_SELF`), `ZR_HOST_RUBY` (was `ZR_RUBY`), and `ZR_TUNE=0` (was
  `ZR_GC=0` and `ZR_YJIT=0`). The test harness variables start with
  `ZR_TEST_`.

### Removed

- The `zr zr run|build|machine` alias.

### Fixed

- A class method that the core library sends by name reaches a program
  subclass's own definition: `OpenSSL::Digest.hexdigest("SHA1", data)`
  called `Digest::Class.digest` and skipped the override.
- `IO.select` works on a stream whose class defines its own `send`, as
  `Socket` does: the core library's `send(:name)` is always Kernel#send.
- `IO.pipe` called on a subclass makes both ends of that subclass.
- A binary whose program data reaches 124 pages boots: the chained
  fixup starts cover only a segment's file bytes, as ld64 writes them.
- In a binary, `String#index` from an offset, `bytesplice`, `unpack` and
  `unpack1` at an offset, and `<<` of text in another encoding take time
  in proportion to the work, not to the String's length. `unpack`'s `@`
  and `X` count from the String's start, as ruby's do.
- `rake cache:prune` keeps the eval support files of the current runtime.
- `zr run app.rb --emit obj` exited 0 and did nothing; it is now a usage
  error.

[Unreleased]: https://github.com/ryanseys/zr/commits/main
