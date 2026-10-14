# Dependencies

This page lists everything that zr uses and does not own. zr's own
code has no C or assembler. The only C in the repository is ruby's
headers for a cross build of a C extension (`vendor/targets`) and the
small extensions that the tests build (`test/ext`).

## To use the gem

| Dependency | Why | Needed for |
|---|---|---|
| ruby 4.0 or later; the latest Ruby 4 release is best | runs the compiler; zr checks its output against the ruby that `.ruby-version` names, and warns on a ruby of another series | everything |
| libSystem | the only dynamic library that a macOS binary links | macOS binaries |
| OpenSSL 3 (libssl and libcrypto) | a macOS binary opens them when it runs `require "openssl"`: from `OPENSSL_DIR`, else from the Homebrew or MacPorts prefix. Without them, that `require` raises `LoadError`. An aarch64-linux-musl binary is static and cannot open them: its `require "openssl"` raises `LoadError`, and so does that of a gem that requires it (bcrypt, thrift). Nothing else needs them | programs that require `openssl` on macOS |
| `cc` (Xcode Command Line Tools) | links a macOS binary under `ZR_LINKER=cc`, or when zr's own linker refuses one; links a C library that `--link` names; compiles and links a gem's C extension for `--native-ext` | optional; `--native-ext` |
| `make` | runs the Makefile that a gem's `extconf.rb` writes, when zr builds the gem's C extension | `--native-ext` of a gem whose install kept no compiled code |
| musl's `cc`, or `aarch64-linux-musl-gcc` | links a static binary | `aarch64-linux-musl` binaries |
| wasmtime | runs a module; `zr run --emit wasm` uses it | running WASI modules |

The gem has no dependencies. It carries the pinned ruby's pure-Ruby
standard library in `vendor/ruby`, as a stock ruby installs it: the
default gems and the bundled gems, at the versions that the pinned ruby
includes (`Zr::Library::Stdlib`). A program's `require` reads those files, and
never the host's gems. The gems with a C part are zr's own ports
(`Zr::Library::Ports`); [Differences from ruby](differences-from-ruby.md#library-versions)
lists the versions. The install compiles nothing.

zr links a macOS binary itself (`Obj::MachO::Executable`). When it
runs `cc`, it sets `DEVELOPER_DIR` and `SDKROOT` to the install that
the SDK comes from. Thus an Xcode that is older than the Command Line
Tools does not use its `ld` with an SDK that it cannot read. zr keeps a
`DEVELOPER_DIR` or `SDKROOT` that you set.

## To work in a checkout

`bin/setup` installs the gems, and the test reference (`tool/install_reference_gems.rb`).

| Dependency | Why | Used by |
|---|---|---|
| the ruby that `.ruby-version` names | the host, and the only reference for the tests | everything |
| `rake` gem ~> 13.0 | the tasks | `Rakefile` |
| `minitest` gem ~> 6.0 | runs every test | `bin/minitest` |
| `fiddle` gem ~> 1.1 | loads code into the test process | `lib/zr/obj/jit/fiddle.rb`, `Harness::KernelJIT` |
| `benchmark` gem ~> 0.5 | the clock of `zr-dev bench` and `zr-dev compile` | `tool/lib/zr/dev/bench.rb`, `tool/compile.rb` |
| `rubocop` gem ~> 1.89, with `rubocop-performance`, `rubocop-minitest` and `rubocop-thread_safety` | `rake lint` | `.rubocop.yml` |
| `steep` gem ~> 2.1, `rbs` gem ~> 4.2 | the type check of the compiler | `bin/steep check`, `Steepfile`, `sig/` |
| `simplecov` gem ~> 1.3 | line and branch coverage with `COVERAGE=1` | `test/support/coverage_run.rb` |
| `debug_inspector` gem ~> 1.2 | the frames of the kernel when it runs on ruby | `lib/zr/machine/host.rb` |
| `irb` gem | `bin/console` | by hand |
| `vernier` gem ~> 1.0 | profiles the compiler; never part of a build or a test | by hand |
| wasmtime | runs the wasm tests; a test skips without it | `wasm_test`, the tiers under `ZR_TARGET=wasm32-wasi` |
| the test reference | the pinned ruby's bundled gems, and each port's gem at zr's version, in `tmp/reference/gems` (`tool/install_reference_gems.rb`). Every expected output comes from ruby with only these gems | `zr-dev expect`, `zr-dev record`, `zr-dev probe`, the program tests of a program that does not parse |
| `nm`, `otool` | read an object and a binary back | `macho_test`, `exe_test`, `native_test` |
