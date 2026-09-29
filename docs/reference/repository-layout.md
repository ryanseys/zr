# Repository layout

## The gem

The gem contains `exe/`, `lib/`, `licenses/`, `runtime/`,
`vendor/ext/`, `vendor/lib/` and `vendor/prelude/`, with `README.md`,
`CHANGELOG.md` and the license files. The pure-Ruby library that a program requires
is not in the gem. It is the gems that `zr.gemspec` depends on
(`lib/zr/libraries.rb`).

| Path | Contains |
|---|---|
| `exe/zr` | the `zr` command; `lib/zr/cli.rb` has its commands |
| `lib/zr.rb` | the entry point: the version, the paths and the targets |
| `lib/zr/version.rb` | `Zr::VERSION`, and `Zr::RUBY`, the ruby that zr needs |
| `lib/zr/paths.rb` | where zr reads its sources and writes its cache |
| `lib/zr/flags.rb` | `Zr.flag?`, which reads an on-or-off environment variable |
| `lib/zr/config.rb` | `Zr::Config`: the `ZR_*` variables that steer a build, read once |
| `lib/zr/cli.rb` | the commands of `zr`, their options, and what they print |
| `lib/zr/doctor.rb` | the checks of `zr doctor` |
| `lib/zr/cache.rb` | the build cache: what it holds, and `zr cache clean` |
| `lib/zr/refused.rb` | `Zr::Refused`: a program uses a form that zr does not support |
| `lib/zr/bytes.rb` | byte helpers: alignment and padding |
| `lib/zr/clock.rb` | `Zr.clock`: the phase times that `ZR_TIMING=1` prints |
| `lib/zr/settled.rb` | `Zr.settled!`: a cache write stops if a source changed during the build |
| `lib/zr/parse.rb` | `Zr.parse`: prism, through the parse cache where there is one |
| `lib/zr/backend.rb` | `Zr::Backend`: what the backends share, and `Backend::Refused` |
| `lib/zr/self_built.rb` | a binary that zr builds from this checkout's own files: the compiled compiler, or the tools |
| `lib/zr/shipped.rb` | the compiled compiler that a platform gem ships |
| `lib/zr/libraries.rb`, `lib/zr/libraries/` | the pinned gems that a program requires from, and the library tree that links them |
| `lib/zr/library_digests.rb` | the digests of the pinned gems' files (`zr-dev gen libraries`) |
| `lib/zr/target.rb` | the targets, and what this host can build |
| `lib/zr/prism.rb` | loads prism on the host; `Zr.parse` |
| `lib/zr/parse_cache.rb` | the host's cache of parse results |
| `lib/zr/hir.rb`, `lib/zr/hir/` | prism's tree to the HIR: desugaring, requires, refusals |
| `lib/zr/lower.rb`, `lib/zr/lower/` | `Zr::Lower`: the HIR to the IR, for the zr runtime |
| `lib/zr/runtime.rb` | `Zr::Runtime`, `Zr::Program` and `Zr::EvalSupport`: the runtime's files and built forms |
| `lib/zr/sources.rb` | the source files of the runtime and the compiler, and the digests that name the cache's files |
| `lib/zr/machine/` | the machine dialect to the IR, and the kernel's description |
| `lib/zr/ir.rb`, `lib/zr/ir/` | the IR, its passes, its verifier, and `IR::Interp` |
| `lib/zr/backend/aarch64/` | the aarch64 backend: assembler, register allocator, code generator |
| `lib/zr/backend/wasm/` | the wasm emitter |
| `lib/zr/obj/` | the object model, relocations, and the JIT loader |
| `lib/zr/obj/macho/`, `lib/zr/obj/elf/` | the Mach-O object and executable writers, the prelinked image and the skeleton; the ELF object writer |
| `lib/zr/native/` | the build driver, parallel assembly, the linkers |
| `lib/zr/unit_cache.rb` | the cache of each compilation unit's machine code |
| `lib/zr/core_cache.rb` | the core files that a build takes from an earlier build's machine code, and the checks that keep that code the same as a full build's |
| `lib/zr/run_cache.rb` | the binaries that `zr run` keeps, and the files each was built from |
| `lib/zr/tune.rb` | the collector limits and YJIT of a compile |
| `lib/zr/compiled_compiler.rb` | the compiled compiler: when `exe/zr` gives it a build |
| `lib/zr/eval.rb` | the eval compiler |
| `lib/zr/eval/walk.rb`, `lib/zr/eval/walk/` | the tree-walking interpreter |
| `runtime/kernel/` | the kernel, in the machine dialect |
| `runtime/kernel/os/<os>/`, `runtime/kernel/arch/<arch>/` | the OS and machine layers of the kernel |
| `runtime/core/` | the core library, in ordinary Ruby, one file for each class |
| `runtime/core/regexp/onig/` | the pattern compiler of the Onigmo port (`Regexp::Onig`) |
| `runtime/core/os/<os>/` | each OS's numbers for the errno, IO, File and Process constants |
| `runtime/ext/` | the native halves of extensions, in ordinary Ruby |
| `runtime/ext/prism/` | the prism port: `prism.rb` and `ruby/` (`Prism::Ruby`) |
| `runtime/ext/os/<os>/` | extension tables, and the description (`zr_description.rb`) |
| `runtime/ext/zr/` | zr's own runtime files: the run-time half of eval support, and the files that load a library at its first call (`pp`, `irb`, `unicode_normalize`), as CRuby's prelude does |
| `vendor/ext/<gem>/lib/` | the Ruby halves of extension gems, not edited |
| `vendor/lib/` | the files of ruby 4.0.7's library that no gem contains, not edited; `vendor/lib/VERSIONS` lists them |
| `vendor/prelude/` | ruby's `gem_prelude.rb` |

### What the host loads

The gem's only require path is `lib/`. `runtime/` and `vendor/` are
beside `lib/`, not in it:

- `runtime/` is never on the host's load path. zr compiles it into
  programs. The host loads only namespaced, pure parts of it, by path:
  `Regexp::Onig`, `Prism::Ruby` and `zr_description`.
- `vendor/` is never on the host's load path. A file such as
  `vendor/lib/pathname.rb` must never replace ruby's own.

### The library tree

A build requires ruby's library from one directory, the library tree.
It has a link to each file of each pinned gem and of `vendor/lib`. It
is `tmp/lib/` in a checkout, and `lib/` in the user cache directory
(for example `~/Library/Caches/zr/lib/`) for an installed gem. `lib/zr/libraries/resolve.rb` writes it, in
a ruby with rubygems, when the gems change.

## The repository only

| Path | Contains |
|---|---|
| `bin/setup`, `bin/test`, `bin/console` | the scripts of a checkout; see [Tools](tools.md) |
| `Rakefile` | the rake tasks: build, test, gen, lint and release |
| `tool/zr-dev.rb` | the `zr-dev` command, which lists and starts the maintainer tools; see [Tools](tools.md#zr-dev) |
| `tool/*.rb` | the body of each `zr-dev` command, one file for each command (`tool/bench.rb` for `zr-dev bench`) |
| `tool/lib/zr/dev.rb`, `tool/lib/zr/dev/` | the code that the commands share: the command class, the paths, the host ruby and the C sources |
| `tool/gen/` | the generators of `zr-dev gen`, one file for each generated file; `tool/gen/prism/templates/` has the templates of the pure-Ruby prism |
| `tool/spec/` | the commands of `zr-dev spec` |
| `lib/zr/prism_shim/` | makes `require "prism/prism"` load the port on the host |
| `docs/` | this documentation |
| `.github/workflows/` | CI (`ci.yml`) and the release (`release.yml`) |
| `.github/actions/runtime-cache/` | the CI step that keeps the built runtime between runs |
| `test/test_helper.rb` | what every unit and e2e test file requires |
| `test/spec_helper.rb` | what a spec file requires: the test helper, and the spec DSL |
| `test/support/` | the test library: the spec DSL, the fork pool, the kept binaries, the progress file |
| `test/support/harness/` | ruby's reference runs, the child process limits, wasmtime, the benchmark runner, `Harness::KernelJIT`, and the harnesses that compare a port with ruby's C |
| `test/unit/` | the unit tier: zr's own internals |
| `test/spec/` | the spec tier: Ruby behavior, example by example |
| `test/e2e/` | the e2e tier: whole programs through a real link, in areas as the specs are, each with its recording |
| `test/baselines/` | the baselines of the targets other than macOS; see [How to test on another target](../how-to/test-on-another-target.md) |
| `test/fixtures/` | the files that spec examples read with `fixture` |

The next five directories are not tiers. They hold the programs and
the snapshots that tests in `test/unit/` read.

| Path | Contains |
|---|---|
| `test/programs/` | Ruby programs that `programs_test` runs against ruby; those in `native/` do not run as WASI modules |
| `test/machine/` | machine-dialect programs, with their outputs; `test/machine/refused/` has one program for each refusal |
| `test/runtime/` | programs that test the kernel through hand-written top levels |
| `test/native/` | hand-written IR, and the disassembly snapshot |
| `test/hir/` | programs and their HIR dumps |

| Path | Contains |
|---|---|
| `licenses/` | the license texts of the parts that have no other copy in the gem; see `THIRD_PARTY_NOTICES.md` |
| `benchmark/` | the benchmarks: whole programs with their recordings, and the rungs that `zr-dev compile` builds (`benchmark/compile/`); see `benchmark/README.md` |
| `tmp/` | not committed: the cache (`tmp/cache/`), the library tree, the test progress file, the bootstrap stages |
