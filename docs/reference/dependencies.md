# Dependencies

This page lists everything that zr uses and does not own. None of it
is C, Rust or assembler source in the repository.

## To use the gem

| Dependency | Why | Needed for |
|---|---|---|
| ruby 4.0.6 exactly | runs the compiler; zr checks its output against this version | everything |
| libSystem | the only dynamic library that a macOS binary links | macOS binaries |
| OpenSSL 3 (libssl and libcrypto) | a macOS binary opens them when it runs `require "openssl"`: from `OPENSSL_DIR`, else from the Homebrew or MacPorts prefix. Without them, that `require` raises `LoadError`. Nothing else needs them | programs that require `openssl` |
| `cc` (Xcode Command Line Tools) | links a macOS binary only under `ZR_LINKER=cc`, or when zr's own linker refuses one | optional |
| musl's `cc`, or `aarch64-linux-musl-gcc` | links a static binary | `aarch64-linux-musl` binaries |
| wasmtime | runs a module; `zr run --emit wasm` uses it | running WASI modules |

The gem depends on the default and bundled gems of ruby 4.0.6. Each is
pinned to the version that ruby 4.0.6 includes (`Zr::Libraries::PINS`).
A program's `require` of a pure-Ruby library reads that gem. The
install compiles nothing.

zr links a macOS binary itself (`Obj::MachO::Executable`). When it
runs `cc`, it sets `DEVELOPER_DIR` and `SDKROOT` to the install that
the SDK comes from. Thus an Xcode that is older than the Command Line
Tools does not use its `ld` with an SDK that it cannot read. zr keeps a
`DEVELOPER_DIR` or `SDKROOT` that you set.

## To work in a checkout

`bin/setup` installs the gems.

| Dependency | Why | Used by |
|---|---|---|
| ruby 4.0.6 (`.ruby-version`) | the host, and the only reference for the tests | everything |
| `rake` gem ~> 13.0 | the tasks | `Rakefile`, `rakelib/` |
| `minitest` gem ~> 6.0 | runs every test | `bin/test` |
| `minitest-reporters` gem ~> 1.8 | the report of the slowest tests (`SLOW=1`), and the JUnit file for CI | `test/test_helper.rb` |
| `aarch64` gem ~> 3.0 | pure Ruby, generated from the ARM specification; the tests check zr's encoder against it | `test/unit/aarch64_test.rb` |
| `fiddle` gem ~> 1.1 | loads code into the test process | `lib/zr/obj/jit/fiddle.rb`, `Harness::KernelJIT` |
| `benchmark` gem ~> 0.5 | the clock of `rake bench` and `rake compile` | `rakelib/bench.rake` |
| `rubocop` gem ~> 1.89 | `rake lint` | `.rubocop.yml` |
| `vernier` gem ~> 1.0 | profiles the compiler; never part of a build or a test | by hand |
| wasmtime | runs the wasm tests; a test skips without it | `wasm_test`, `programs_test`, the tiers under `TARGET=wasm32-wasi` |
| `nm`, `otool` | read an object and a binary back | `macho_test`, `exe_test`, `native_test` |
