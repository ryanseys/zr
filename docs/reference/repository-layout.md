# Repository layout

## The gem

The gem ships `exe/`, `lib/`, `rt/` and `vendor/ext`, `vendor/lib`,
with the license files. Its only require path is `lib/`.

| Path | Holds |
|---|---|
| `exe/ze0` | the gem's command; `lib/ze0/cli.rb` holds its commands |
| `lib/ze0.rb` | the entry: version, paths and targets |
| `lib/ze0/paths.rb` | where ze0 reads its sources and writes its cache |
| `lib/ze0/target.rb` | the targets, and what this host can build |
| `lib/ze0/prism.rb` | loads prism on the host; `Ze0.parse` |
| `lib/ze0/parse_cache.rb` | the host's cache of parse results |
| `lib/ze0/hir/` | prism's tree to the HIR: desugaring, requires, refusals |
| `lib/ze0/zr/` | the HIR to IR against the `zr` runtime |
| `lib/ze0/machine/` | the kernel dialect to IR, and the kernel's description |
| `lib/ze0/ir/` | the IR, its passes, its verifier, and an interpreter |
| `lib/ze0/backend/aarch64/` | the aarch64 backend: assembler, register allocator, code generator |
| `lib/ze0/backend/wasm/` | the wasm emitter |
| `lib/ze0/obj/` | the object model, relocations, and the JIT loader |
| `lib/ze0/obj/macho/`, `lib/ze0/obj/elf/` | the Mach-O object and executable writers; the ELF object writer |
| `lib/ze0/native/` | the build driver, parallel assembly, the linkers |
| `lib/ze0/eval.rb` | the compiler a program that evals carries |
| `rt/kernel/` | the runtime's kernel, in the kernel dialect |
| `rt/kernel/os/<os>/`, `rt/kernel/arch/<arch>/` | the OS and machine layers |
| `rt/core/` | the core library, in ordinary Ruby, one file per class |
| `rt/core/regexp/onig/` | the Onigmo port's pattern compiler |
| `rt/core/os/<os>/` | each OS's numbers for errno, IO, File and Process constants |
| `rt/ext/` | the native halves of extensions, in ordinary Ruby |
| `rt/ext/prism/` | the prism port: `prism.rb` and `ruby/` |
| `rt/ext/os/<os>/` | extension tables and the eval description |
| `vendor/ext/<gem>/lib/` | the Ruby halves of extension gems, unedited |
| `vendor/lib/` | ruby 4.0.6's pure-Ruby standard library and bundled gems, unedited |
| `vendor/gems/`, `vendor/prelude/` | a bundled gem kept apart; ruby's `gem_prelude.rb` |

`rt/` and `vendor/` sit beside `lib/`, not in it. ze0 compiles them
into programs, and the host ruby never loads them. A file such as
`vendor/lib/set.rb` must never shadow ruby's own.

## The repository only

| Path | Holds |
|---|---|
| `lib/ze0/prism_backend/` | makes `require "prism/prism"` load the port on the host |
| `tools/` | the recording, test and table tools; see [Tools](tools.md) |
| `docs/` | this documentation |
| `test/test_helper.rb` | what every test file requires |
| `test/spec_helper.rb` | what a spec file requires: the helper, plus `ze0` |
| `test/support/` | the test library: the harness, the spec road, the fork pool |
| `test/support/harness/` | the case format, the child bound, the benchmark runner, and the diff harnesses |
| `test/unit/` | ze0's own internals: minitest files `rake test:unit` runs |
| `test/spec/` | Ruby held to ruby, program by program: `rake test:spec` |
| `test/e2e/` | whole programs through a real link: `rake test:e2e`, filed by area as the specs are |
| `test/bench/` | the benchmarks and their results |
| `test/baselines/` | the rows a target other than macOS is allowed to fail |
| `test/programs/` | Ruby programs run against a live ruby by `programs_test` |
| `test/zr/` | kernel-dialect programs; `test/zr/refused/` names each refusal |
| `test/rt/` | the kernel through hand-written toplevels |
| `test/native/` | hand-written IR and the disassembly snapshot |
| `test/hir/` | programs and their HIR dumps |
