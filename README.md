# ze0: a Ruby compiler, written in Ruby

ze0 compiles Ruby programs to native binaries, and is itself written in
Ruby. The contract is CRuby's: a program answers exactly what ruby 4.0.6
answers, or ze0 refuses it by name at the line. ruby is the only oracle.

Nothing ze0 owns is written in C, Rust or assembler. prism parses,
`lib/ze0/hir/` builds a tree HIR, `lib/ze0/zr/` and `lib/ze0/machine/`
lower it to one SSA IR, and three emitters take it from there: the
aarch64 backend writes machine code, the Mach-O writer writes the object,
and the wasm emitter writes a WASI module. `docs/plan.md` is the road.

```console
$ bin/ze0 zr build test/zr/hello.rb -o hello   # a kernel-dialect file to a binary
$ bin/ze0 zr run test/programs/hello.rb        # a Ruby program, compiled and run
$ bin/ze0 zr build test/zr/gc.rb -o gc.wasm --emit wasm && wasmtime gc.wasm
$ bin/ze0 test ze0::                           # the ze0 corpus against ruby's recordings
$ bin/ze0 test lang/blocks/ --show 40          # any corpus directory
$ bin/ze0 check                                # the repo's own checks
$ bin/ze0 stage1                               # ze0 compiles itself twice to the same bytes
$ bin/ze0 deps build                           # build the vendored C dependencies
```

## Layout

```
bin/ze0                  the CLI
lib/ze0/hir/             the tree HIR: prism in, analyses and a dump out
lib/ze0/zr/              the lowering from HIR to IR
lib/ze0/machine/         the kernel dialect: typed Ruby that lowers straight to IR
lib/ze0/ir/              the IR, its verifier, and the two native emitters
lib/ze0/ir/arm64.rb      the aarch64 backend: spill-everything code over our own encoder
lib/ze0/ir/wasm.rb       the wasm32 emitter: one WASI module, a br_table dispatch loop
lib/ze0/obj/             the object model, the Mach-O writer, and the JIT loader
lib/ze0/native/          the build driver and the one link step
lib/ze0/harness/         the corpus runner: the test-file format and the sweep
rt/                      the runtime, in kernel Ruby and ordinary Ruby
vendor/c/                the two vendored C libraries; vendor/ext/<gem>/lib their Ruby halves
test/lang, core, ...     the corpus: one program per file, ruby's answer under __END__
test/ze0/                the programs ze0's own subset is held to
test/native/fixtures.rb  IR written by hand, the floor every runtime program stands on
test/zr/                 kernel-dialect programs; test/zr/refused/ names each refusal
test/programs/           Ruby programs on the runtime, against a live ruby
```

`vendor/ruby` and `vendor/gems` (rubygems, bundler, the gem store) are
fetched, not committed; a tier that is absent is skipped.

## The test format

One `.rb` file is one program, and ruby's recorded answer sits under
`__END__`: stdout, then `#@ stderr`, `#@ exit N` or `#@ signal N` markers.
`#@ key: value` lines above `__END__` are directives (`args`, `stdin`,
`env`, `only`, ...). `docs/test-format.md` is the reference. A program may
not read `DATA` or `__FILE__`: ruby would hand it its own trailer.

## Requirements

macOS on Apple Silicon. ze0 emits `aarch64-apple-darwin` and nothing else.

### To build and run ze0

| Dependency | Why | Where |
|---|---|---|
| ruby 4.0.6 (`.ruby-version`) | the stage-0 host, and the only oracle | everywhere |
| `prism` gem ~> 1.9 | parses Ruby | `lib/ze0/hir/build.rb` |
| `minitest` gem ~> 6.0 | runs `bin/ze0 check` | `test/checks/` |
| `aarch64` gem ~> 3.0 | pure Ruby, generated from the ARM specification: the authority our own encoder is held to. It never enters a compiled program. | `test/checks/aarch64_test.rb` |
| `cc` | **links** every binary, and **compiles** the vendored C | `lib/ze0/native/link.rb`, `lib/ze0/deps.rb` |
| `ld` | invoked by `cc`; it also writes the ad-hoc code signature Apple Silicon requires to execute a binary | through `cc` |
| `ar` | archives the vendored C into `vendor/build/*.a` | `lib/ze0/deps.rb` |
| libSystem | the only dylib a ze0 binary loads | every binary |

### Vendored C, built by `ze0 deps build`

| Library | Why it is C |
|---|---|
| prism (`vendor/c/prism`) | the parser ruby itself uses. Matching ruby's answers means matching ruby's parser, and prism has no Ruby implementation. |
| oniguruma (`vendor/c/oniguruma`) | the engine CRuby's `Regexp` semantics are defined by, down to its backtracking limits and its character tables. |

### Optional

| Dependency | Why |
|---|---|
| `wasmtime` | runs the wasm road; `ze0 check` skips what is absent |
| `nm`, `otool` | two checks read an object and a binary back |

Everything above is a Ruby gem, a system tool, or a vendored C library
whose behaviour the contract is written against. `ld` leaves the loop when
`Obj::Exe` lands (`docs/plan.md` B7); `cc` and `ar` stay as long as the two
C libraries do.
