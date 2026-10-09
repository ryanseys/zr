# Dependencies

This page lists everything that zr uses and does not own. None of it
is C or assembler source in the repository.

## To use the gem

| Dependency | Why | Needed for |
|---|---|---|
| ruby 4.0.7, or a later 4.0 release | runs the compiler; zr checks its output against ruby 4.0.7, and warns on a later release | everything |
| libSystem | the only dynamic library that a macOS binary links | macOS binaries |
| OpenSSL 3 (libssl and libcrypto) | a macOS binary opens them when it runs `require "openssl"`: from `OPENSSL_DIR`, else from the Homebrew or MacPorts prefix. Without them, that `require` raises `LoadError`. An aarch64-linux-musl binary is static and cannot open them: its `require "openssl"` raises `LoadError`, and so does that of a gem that requires it (bcrypt, thrift). Nothing else needs them | programs that require `openssl` on macOS |
| `cc` (Xcode Command Line Tools) | links a macOS binary only under `ZR_LINKER=cc`, or when zr's own linker refuses one | optional |
| musl's `cc`, or `aarch64-linux-musl-gcc` | links a static binary | `aarch64-linux-musl` binaries |
| wasmtime | runs a module; `zr run --emit wasm` uses it | running WASI modules |

The gem has no dependencies. It carries ruby 4.0.7's pure-Ruby
standard library in `vendor/ruby`, as a stock ruby 4.0.7 installs it: the
default gems and the bundled gems, at the versions that ruby 4.0.7
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
| ruby 4.0.7 (`.ruby-version`) | the host, and the only reference for the tests | everything |
| `rake` gem ~> 13.0 | the tasks | `Rakefile` |
| `minitest` gem ~> 6.0 | runs every test | `bin/minitest` |
| `minitest-reporters` gem ~> 1.8 | the report of the slowest tests (`SLOW=1`), and the JUnit file for CI | `test/test_helper.rb` |
| `aarch64` gem ~> 3.0 | pure Ruby, generated from the ARM specification; the tests check zr's encoder against it | `test/unit/aarch64_test.rb` |
| `fiddle` gem ~> 1.1 | loads code into the test process | `lib/zr/obj/jit/fiddle.rb`, `Harness::KernelJIT` |
| `benchmark` gem ~> 0.5 | the clock of `zr-dev bench` and `zr-dev compile` | `test/support/harness/bench.rb`, `tool/compile.rb` |
| `rubocop` gem ~> 1.89 | `rake lint` | `.rubocop.yml` |
| `irb` gem | `bin/console` | by hand |
| `vernier` gem ~> 1.0 | profiles the compiler; never part of a build or a test | by hand |
| wasmtime | runs the wasm tests; a test skips without it | `wasm_test`, the tiers under `ZR_TARGET=wasm32-wasi` |
| the test reference | ruby 4.0.7's bundled gems, and each port's gem at zr's version, in `tmp/reference/gems` (`tool/install_reference_gems.rb`). Every expected output comes from ruby with only these gems | `zr-dev expect`, `zr-dev record`, `zr-dev probe`, the program tests of a program that does not parse |
| `nm`, `otool` | read an object and a binary back | `macho_test`, `exe_test`, `native_test` |
