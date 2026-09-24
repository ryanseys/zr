# Repository layout

## The gem

The gem ships `exe/`, `lib/`, `runtime/` and `vendor/ext`, `vendor/lib`,
`vendor/prelude`, with the license files. Its only require path is
`lib/`. The pure-Ruby library a program requires is not in the gem: it
is the gems `zr.gemspec` depends on (`lib/zr/libraries.rb`).

| Path | Holds |
|---|---|
| `exe/zr` | the gem's command; `lib/zr/cli.rb` holds its commands |
| `lib/zr.rb` | the entry: version, paths and targets |
| `lib/zr/paths.rb` | where zr reads its sources and writes its cache |
| `lib/zr/libraries.rb` | the pinned gems a program requires from, and the tree that links them |
| `lib/zr/target.rb` | the targets, and what this host can build |
| `lib/zr/prism.rb` | loads prism on the host; `Zr.parse` |
| `lib/zr/parse_cache.rb` | the host's cache of parse results |
| `lib/zr/hir/` | prism's tree to the HIR: desugaring, requires, refusals |
| `lib/zr/lower/` | the HIR to IR against the `zr` runtime |
| `lib/zr/machine/` | the kernel dialect to IR, and the kernel's description |
| `lib/zr/ir/` | the IR, its passes, its verifier, and an interpreter |
| `lib/zr/backend/aarch64/` | the aarch64 backend: assembler, register allocator, code generator |
| `lib/zr/backend/wasm/` | the wasm emitter |
| `lib/zr/obj/` | the object model, relocations, and the JIT loader |
| `lib/zr/obj/macho/`, `lib/zr/obj/elf/` | the Mach-O object and executable writers; the ELF object writer |
| `lib/zr/native/` | the build driver, parallel assembly, the linkers |
| `lib/zr/eval.rb` | the compiler a program that evals carries |
| `runtime/kernel/` | the runtime's kernel, in the kernel dialect |
| `runtime/kernel/os/<os>/`, `runtime/kernel/arch/<arch>/` | the OS and machine layers |
| `runtime/core/` | the core library, in ordinary Ruby, one file per class |
| `runtime/core/regexp/onig/` | the Onigmo port's pattern compiler |
| `runtime/core/os/<os>/` | each OS's numbers for errno, IO, File and Process constants |
| `runtime/ext/` | the native halves of extensions, in ordinary Ruby |
| `runtime/ext/prism/` | the prism port: `prism.rb` and `ruby/` |
| `runtime/ext/os/<os>/` | extension tables and the eval description |
| `vendor/ext/<gem>/lib/` | the Ruby halves of extension gems, unedited |
| `vendor/lib/` | the files of ruby 4.0.6's library that no gem ships, unedited |
| `vendor/prelude/` | ruby's `gem_prelude.rb` |

`runtime/` and `vendor/` sit beside `lib/`, not in it. zr compiles them
into programs, and the host ruby never loads them. A file such as
`vendor/lib/pathname.rb` must never shadow ruby's own.

A build requires ruby's library from one directory, the library tree:
a link to each file of each pinned gem and of `vendor/lib`. It is
`tmp/lib/<key>/` in a checkout, and `zr/lib/<key>/` in the user's
cache for an installed gem. `lib/zr/libraries/resolve.rb` writes it,
in a ruby with rubygems, when the gems it read from change.

## The repository only

| Path | Holds |
|---|---|
| `lib/zr/prism_backend/` | makes `require "prism/prism"` load the port on the host |
| `rakelib/` | every task's body, one file a subject; see [Tasks](tools.md) |
| `docs/` | this documentation |
| `test/test_helper.rb` | what every test file requires |
| `test/spec_helper.rb` | what a spec file requires: the helper, plus `zr` |
| `test/support/` | the test library: the harness, the spec road, the fork pool |
| `test/support/harness/` | what ruby answered, the child bound, the benchmark runner, and the diff harnesses |
| `test/support/generators/` | the four generators a check runs on every `rake test:unit` |
| `test/unit/` | zr's own internals: minitest files `rake test:unit` runs |
| `test/spec/` | Ruby held to ruby, program by program: `rake test:spec` |
| `test/e2e/` | whole programs through a real link: `rake test:e2e`, filed by area as the specs are, each with what ruby answered beside it |
| `benchmark/` | the benchmarks, at the top of the repository as other gems keep them: whole programs with what ruby answered for each, and the rungs `rake compile` builds; see `benchmark/README.md` |
| `test/baselines/` | the rows a target other than macOS is allowed to fail |
| `test/programs/` | Ruby programs run against a live ruby by `programs_test`; those under `native/` skip the wasm road |
| `test/machine/` | kernel-dialect programs; `test/machine/refused/` names each refusal |
| `test/runtime/` | the kernel through hand-written toplevels |
| `test/native/` | hand-written IR and the disassembly snapshot |
| `test/hir/` | programs and their HIR dumps |
