# Repository layout

## The gem

The gem contains `exe/`, `lib/`, `licenses/`, `vendor/ruby/`,
`vendor/LICENSES/` and `vendor/vendor.lock`, with `README.md`,
`CHANGELOG.md` and the license files. It has no gem dependencies: the
library that a program requires is `vendor/ruby`
(`lib/zr/library/roots.rb`) and zr's own `lib/zr/runtime/ext`.

The runtime is in `lib/zr/runtime/`. It is the source that zr compiles
into each program. It is not code of the compiler, although it is
under `lib/zr/` (`Zr::Paths::RUNTIME`).

Two kinds of code meet on a program's load path (`Zr::Library::Layout`):

- `vendor/`: code that other people wrote, byte for byte as they ship
  it. Nobody edits it; `zr-dev vendor` writes it (`lib/zr/library/vendor.rb`).
- `lib/zr/runtime/`: code that zr wrote. It comes first on the load
  path, so a file there replaces an upstream file of the same path (an
  overlay).

| Path | Contains |
|---|---|
| `exe/zr` | the `zr` command; `lib/zr/cli/commands/` has its commands |
| `lib/zr.rb` | the entry point: the version, the paths and the targets |
| `lib/zr/version.rb` | `Zr::VERSION`, and `Zr::RUBY`, the ruby that zr needs |
| `lib/zr/paths.rb` | where zr reads its sources and writes its cache |
| `lib/zr/host.rb` | `Zr::Host.compiled?`: whether zr runs in a binary that zr compiled, not in CRuby |
| `lib/zr/config.rb` | `Zr::Config`: the `ZR_*` variables that steer a build, read once, and `Config.flag?` for an on-or-off variable |
| `lib/zr/cli.rb` | the command line of `zr`: `CLI.start` runs the command that the first word names (`CLI::COMMANDS`) |
| `lib/zr/cli/` | the parts of the command line: `command.rb` (the base class), `options.rb` (the option table), `help.rb` (the help text), `errors.rb`, `refusals.rb` (status 3), `runner.rb` (runs the built binary), and `commands/`, one file for each command |
| `lib/zr/doctor.rb` | the checks of `zr doctor` |
| `lib/zr/cache/store.rb` | the one content store of every cache: layout, keys, reads, writes, roots and eviction |
| `lib/zr/cache/janitor.rb` | the build cache as `zr cache` sees it: size, clean, and the daily trim |
| `lib/zr/refused.rb` | `Zr::Refused`: a program uses a form that zr does not support |
| `lib/zr/session.rb` | `Zr::Session`: the memos of one process (the settings, the library roots, the runtimes, the parse memo, the digests), and `reset!`, which the warm server calls before each build |
| `lib/zr/bytes.rb` | byte helpers: alignment, padding, LEB128 and zigzag |
| `lib/zr/timing.rb` | `Zr::Timing.phase`: the phase times that `ZR_TIMING=1` prints |
| `lib/zr/source_guard.rb` | `Zr::SourceGuard.check!`: a cache write stops if a source changed during the build |
| `lib/zr/parse.rb` | `Zr.parse`: prism, through the parse cache where there is one |
| `lib/zr/backend.rb` | `Zr::Backend`: what the backends share, and `Backend::Refused` |
| `lib/zr/library.rb`, `lib/zr/library/` | `Zr::Library`: the library that a program requires, and where each part of it is |
| `lib/zr/library/layout.rb` | `Library::Layout`: where `vendor/ruby`, the gem home and zr's own `runtime/ext` and `runtime/lib` are |
| `lib/zr/library/roots.rb` | `Library::Roots`: the directories that a program's `require` searches, in order, and the names that the loader treats as the runtime's own (the kernel's description, the eval support file) |
| `lib/zr/library/vendor.rb` | what `vendor/` holds, and what it leaves out and why: the input of `zr-dev vendor` |
| `lib/zr/library/stdlib.rb` | the name and version of each gem in `vendor/ruby` (`zr-dev vendor` writes it) |
| `lib/zr/library/ports.rb` | the gems with a C part that zr ports, with their versions and compat ranges |
| `lib/zr/target.rb` | the targets, and what this host can build |
| `lib/zr/prism.rb` | loads prism on the host, and `Zr::HOSTED`: whether ruby runs the compiler |
| `lib/zr/cache/parse.rb` | the host's cache of parse results |
| `lib/zr/hir.rb`, `lib/zr/hir/` | prism's tree to the HIR: desugaring, requires, refusals |
| `lib/zr/hir/build.rb`, `lib/zr/hir/build/` | `Hir::Build`, the builder of the HIR, and its parts: `loader.rb` (`Hir::Build::Loader`: the files that a program reaches through `require` and `load`), `patterns.rb` (pattern matching), `literals.rb`, `requires.rb` and `coverage.rb` |
| `lib/zr/lower.rb`, `lib/zr/lower/` | `Zr::Lower`: the HIR to the IR, for the zr runtime |
| `lib/zr/lower/function/loop.rb`, `lib/zr/lower/function/call_site.rb` | the records `Lower::Function::Loop` (the labels of one loop) and `Lower::Function::CallSite` (the values of one send site) |
| `lib/zr/runtime.rb` | `Zr::Runtime`: the runtime's files and built forms, `Runtime.for(target)`, and how its core and gem prelude are lowered |
| `lib/zr/eval_support.rb` | `Zr::EvalSupport`: the compiler a program with eval links in, `EvalSupport.for(target)` |
| `lib/zr/program.rb` | `Zr::Program`: a program's functions and data, and `Program.build` |
| `lib/zr/runtime_sources.rb` | the source files of one target's runtime and of the compiler, and their digests |
| `lib/zr/load_tables.rb` | `Zr::LoadTables`: the tables a binary carries for its files, its computed requires, error_highlight, Coverage and its gems |
| `lib/zr/symbol_numbering.rb` | `Zr::SymbolNumbering`: the link's numbers for a program's symbols, and their names table |
| `lib/zr/digests.rb` | the digests of the cache's names that belong to no one target: the link, eval support's keys |
| `lib/zr/machine/` | the kernel's typed Ruby to the IR, and the kernel's description |
| `lib/zr/ir.rb`, `lib/zr/ir/` | the IR, its passes, its verifier, and `IR::Interp` |
| `lib/zr/backend/aarch64/` | the aarch64 backend: assembler, register allocator, code generator |
| `lib/zr/backend/wasm/` | the wasm emitter: `codegen.rb`, and `codegen/body.rb` (`Codegen::Body`, the code of one function) |
| `lib/zr/obj/` | the object model, relocations, and the JIT loader |
| `lib/zr/obj/macho/`, `lib/zr/obj/elf/` | the Mach-O object and executable writers, the prelinked image and the skeleton; the ELF object writer |
| `lib/zr/native/` | the build driver, parallel assembly, the linkers |
| `lib/zr/native/unit_program.rb` | `Native::UnitProgram`: a kernel file that `zr machine` compiled; it answers the messages of a `Zr::Program`, so `zr machine` and `zr build` write their output on one path |
| `lib/zr/cache/unit.rb` | the cache of each compilation unit's machine code |
| `lib/zr/cache/lowering.rb`, `lib/zr/cache/lowering/core.rb`, `lib/zr/cache/lowering/eval_support.rb` | the core files and eval support's files that a build takes from an earlier build's machine code, and the checks that keep that code the same as a full build's |
| `lib/zr/cache/run.rb` | the binaries that `zr run` keeps, and the files each was built from |
| `lib/zr/gc_tuning.rb` | the collector limits and YJIT of a compile |
| `lib/zr/server.rb`, `lib/zr/server/client.rb` | the build server of `zr-dev serve`, and its client that `exe/zr` uses |
| `lib/zr/eval.rb` | the eval compiler |
| `lib/zr/eval/walk.rb`, `lib/zr/eval/walk/` | the tree-walking interpreter |
| `lib/zr/runtime/` | the runtime: the source that zr compiles into each program, not code of the compiler |
| `lib/zr/runtime/kernel/` | the kernel, in typed Ruby: each file is one `module Zr::Kern` |
| `lib/zr/runtime/kernel/os/<os>/`, `lib/zr/runtime/kernel/arch/<arch>/` | the OS and machine layers of the kernel |
| `lib/zr/runtime/core/` | the core library, in ordinary Ruby, one file for each class |
| `lib/zr/runtime/core/regexp/onig/` | the pattern compiler of the Onigmo port (`Regexp::Onig`) |
| `lib/zr/runtime/core/os/<os>/` | each OS's numbers for the errno, IO, File and Process constants |
| `lib/zr/runtime/ext/` | the native halves of extensions, in ordinary Ruby |
| `lib/zr/runtime/ext/prism/` | the prism port: `prism.rb` and `ruby/` (`Prism::Ruby`) |
| `lib/zr/runtime/ext/os/<os>/` | extension tables |
| `lib/zr/runtime/lib/zr/` | zr's own libraries: the run-time half of eval support, and the files that load a library at its first call (`pp`, `irb`, `unicode_normalize`), as CRuby's prelude does |
| `vendor/ruby/lib/ruby/4.0.0/` | ruby 4.0.7's own library and default gems, from ruby's source, not edited |
| `vendor/ruby/lib/ruby/gems/4.0.0/` | the bundled gems and the gems whose C zr ports, each from its `.gem`, not edited |
| `vendor/ruby/gem_prelude.rb` | ruby's `gem_prelude.rb` |
| `vendor/LICENSES/` | the license texts that no gem directory holds |
| `vendor/vendor.lock` | each source of `vendor/`, and the SHA-256 of each file; see [How to update the vendored code](../how-to/update-vendored-code.md) |

### What the host loads

The gem's only require path is `lib/`. `lib/zr/runtime/` is below
`lib/zr/`, and `vendor/` is beside `lib/`:

- `lib/zr/runtime/` is never on the host's load path. Its files are
  below `lib/zr/`, so they never replace the host ruby's own libraries
  of the same name. zr compiles it into programs. The host loads only namespaced, pure parts of it, by path:
  `Regexp::Onig` and `Prism::Ruby`.
- `vendor/` is never on the host's load path. A file such as
  `vendor/ruby/lib/ruby/4.0.0/pathname.rb` must never replace the
  host ruby's own.

## The repository only

| Path | Contains |
|---|---|
| `bin/setup`, `bin/test`, `bin/console` | the scripts of a checkout; see [Tools](tools.md) |
| `Rakefile` | the rake tasks: build, test, gen, lint and release |
| `tool/zr-dev.rb` | the `zr-dev` command, which lists and starts the maintainer tools; see [Tools](tools.md#zr-dev) |
| `tool/*.rb` | the body of each `zr-dev` command, one file for each command (`tool/bench.rb` for `zr-dev bench`) |
| `tool/lib/zr/dev.rb`, `tool/lib/zr/dev/` | the code that the commands share: the command class, the paths, the host ruby and the C sources |
| `tool/lib/zr/dev/binary.rb` | `Zr::Dev::Binary`: a binary that zr builds from this checkout's own files (`bin/zr-dev`), and whether it is current |
| `tool/lib/zr/dev/parallel.rb` | `Dev.parallel_map`: the one worker pool of the tools, with the results in the order of the items |
| `tool/typecheck.rb` | `zr-dev typecheck`: Steep checks the files that the `Steepfile` names |
| `Steepfile` | the files of the type check pilot |
| `sig/pilot/` | the types of the pilot's `Struct` and `Data` records, and of the classes that the checked files use |
| `sig/zr_kern.rbs` | the type of each kernel def, from its sig (`zr-dev gen kern_rbs` writes it); not part of the type check |
| `.rubocop.yml`, `.rubocop_todo.yml` | the cops of `rake lint`, each with its reason; the files that a cop found when it came in, to fix |
| `tool/gen/` | the generators of `zr-dev gen`, one file for each generated file; `tool/gen/prism/templates/` has the templates of the pure-Ruby prism |
| `vendor/src/` | upstream sources that only the tools read: prism's templates (`zr-dev gen prism`) |
| `lib/zr/prism_shim/` | makes `require "prism/prism"` load the port on the host |
| `docs/` | this documentation |
| `.github/workflows/` | CI (`ci.yml`) and the release (`release.yml`) |
| `.github/actions/runtime-cache/` | the CI step that keeps the built runtime between runs |
| `test/test_helper.rb` | what every unit test file requires |
| `test/support/` | the test library: the program tests' format (`program_case.rb`), run directory (`program_run.rb`), build (`program_build.rb`), runner (`programs.rb`) and baselines (`baseline.rb`); the fork pool, the workers, the kept binaries, the `# zr-test:` needs, the progress file |
| `test/support/coverage_run.rb` | `COVERAGE=1`: starts SimpleCov, and merges the results of the forked workers |
| `test/support/harness/` | ruby's reference runs, the child process limits, wasmtime, the benchmark runner, `Harness::KernelJIT`, and the harnesses that compare a port with ruby's C |
| `test/support/harness/selected_target.rb` | `Harness.selected_target`: the target of this run (`ZR_TARGET`, or the host's), with no load of the command line |
| `test/unit/` | the unit tier: zr's own internals |
| `test/programs/` | the program tests: plain Ruby programs with ruby's output beside them, in areas (`lang/`, `core/`, `stdlib/`, `compiler/`, and `cli/`, which builds with `zr build`); those in `native/` run only on a native target. See [Program tests](program-tests.md) |
| `test/baselines/` | the baseline of each target, the host too (`<triple>.txt`), and of another project's program tests (`corpus/<project>-<triple>.txt`); see [How to test on another target](../how-to/test-on-another-target.md) |
| `test/fixtures/gems/` | the gems that `gem_compat_test` reads |

The next four directories are not tiers. They hold the programs and
the snapshots that tests in `test/unit/` read.

| Path | Contains |
|---|---|
| `test/machine/` | typed-Ruby programs (`module Zr::Kern`), with their outputs; `test/machine/refused/` has one program for each refusal |
| `test/runtime/` | programs that test the kernel through hand-written top levels |
| `test/native/` | hand-written IR, and the disassembly snapshot |
| `test/hir/` | programs and their HIR dumps |

| Path | Contains |
|---|---|
| `licenses/` | the license texts of the parts that have no other copy in the gem; see `THIRD_PARTY_NOTICES.md` |
| `benchmark/` | the benchmarks: whole programs with their recordings, and the rungs that `zr-dev compile` builds (`benchmark/compile/`); see `benchmark/README.md` |
| `tmp/` | not committed: the cache (`tmp/cache/`), the test reference (`tmp/reference/`), the `.gem` download cache (`tmp/vendor/`), the test progress file, the bootstrap stages |
