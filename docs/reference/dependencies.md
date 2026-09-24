# Dependencies

Everything zr uses that it does not own. None of it is C, Rust or
assembler source in the repository.

## To use the gem

| Dependency | Why | Needed for |
|---|---|---|
| ruby 4.0.6 exactly | runs the compiler; zr checks its output against this version | everything |
| libSystem | the only dynamic library a macOS binary links | macOS binaries |
| OpenSSL 3 (libssl and libcrypto) | a macOS binary opens them when it runs `require "openssl"`: from `OPENSSL_DIR`, else Homebrew's or MacPorts' prefix. Without them that `require` raises `LoadError`; nothing else needs them | programs that require `openssl` |
| `cc` (Xcode Command Line Tools) | links a macOS binary only under `ZR_LINK=cc`, or when zr's own linker refuses one | optional |
| musl's `cc`, or `aarch64-linux-musl-gcc` | links a static binary | `aarch64-linux-musl` binaries |
| wasmtime | runs a module; `zr run --emit wasm` calls it | running WASI modules |

The gem depends on the default and bundled gems of ruby 4.0.6, each
pinned to the version that ruby ships (`Zr::Libraries::PINS`). A
program's `require` of a pure-Ruby library reads that gem. The install
compiles nothing.

zr links a macOS binary itself (`Obj::MachO::Executable`). When it
runs `cc`, it sets `DEVELOPER_DIR` and `SDKROOT` to the install
that the SDK comes from, so that an Xcode older than the Command Line
Tools does not pair its `ld` with an SDK it cannot read. A
`DEVELOPER_DIR` or `SDKROOT` that you set yourself is kept.

## To work in a checkout

| Dependency | Why | Used by |
|---|---|---|
| ruby 4.0.6 (`.ruby-version`) | the host, and the only oracle for the tests | everything |
| `minitest` gem ~> 6.0 | runs every test | `test/unit/` |
| `aarch64` gem ~> 3.0 | pure Ruby, generated from the ARM specification; the checks hold zr's encoder to it | `test/unit/aarch64_test.rb` |
| `fiddle` gem ~> 1.1 | loads code into the checks' own process | `lib/zr/obj/jit/fiddle.rb` |
| `rake` gem ~> 13.0 | the Rakefile's tasks | `Rakefile` |
| `vernier` gem ~> 1.0 | profiles the compiler; never part of a build or a check | by hand |
| wasmtime | runs the wasm checks; a check skips without it | `wasm_test`, `programs_test` |
| `nm`, `otool` | read an object and a binary back | `macho_test`, `exe_test`, `native_test` |
