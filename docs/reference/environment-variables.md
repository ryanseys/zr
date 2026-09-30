# Environment variables

This page lists every environment variable that zr reads. There are
three groups:

- [For users](#for-users): the `zr` command, and the programs it builds.
- [For the tests](#for-the-tests): `bin/test`, the rake test tasks and
  the test harness.
- [For tools](#for-tools): the `zr-dev` commands.

A *flag* is a variable that is on or off. Unset or empty gives the
default. `0` is off. Any other value is on (`Zr.flag?`).

A `ZR_*` value that zr cannot use stops the command with one line and
exit status 2. The line names the variable and a value that works:

```
zr: ZR_JOBS is "abc". Set it to a whole number of 1 or more, for example ZR_JOBS=4.
```

## For users

### The compiler

`zr`, and every rake task and `zr-dev` command that compiles, read these.

| Variable | Values | Default | Effect |
|---|---|---|---|
| `ZR_CACHE` | a directory | `tmp/cache` in a checkout; `$XDG_CACHE_HOME/zr` if `XDG_CACHE_HOME` is set; else `~/Library/Caches/zr` on macOS and `~/.cache/zr` on other hosts | Where zr keeps the built runtime, eval support, the prelinked images and the other cache files. It does not move the compiled compiler of an installed gem (`self-<version>-<id>/`) and the check of a shipped binary: they stay in the user cache, which `XDG_CACHE_HOME` and `HOME` give. |
| `XDG_CACHE_HOME` | a directory | unset | The base of the user cache for an installed gem (see `ZR_CACHE`). |
| `HOME` | a directory | the user's | The user cache is below it when `XDG_CACHE_HOME` is not set. With no `HOME` (some containers and CI jobs), zr stops and says to set `HOME` or `ZR_CACHE`. |
| `ZR_CACHE_MAX_GB` | a number of GB, 0 or more | 5 | After a build, an installed zr deletes the cache entries that were used longest ago and that no root names, and then the compiled compilers of other versions, when the cache is larger than this. It measures at most once a day. `0` turns this off. A checkout never does it; use `zr-dev cache prune`. |
| `ZR_LINK_ARGS` | words | none | Arguments for the system linker, split as a shell splits them, before the `--link` arguments of the command. They make zr link a native binary with `cc` (see `--link` in [The `zr` command](cli.md)). A WASI module or an object ignores them. |
| `ZR_LINKER` | `auto`, `ruby`, `cc` | `auto` | The macOS linker. `auto`: zr's own Mach-O linker, and `cc` for a link that zr's linker refuses. `ruby`: zr's linker only; a link it cannot do stops with a message. `cc`: the system linker always. Another value is an error. |
| `ZR_DEBUG` | `0`, `1` | `0` | `1`: an error that stops zr shows its backtrace. Otherwise zr prints one line: the message, or for a defect in zr, `zr: internal error: ...` and where to report it. |
| `ZR_JOBS` | a whole number, 1 or more | one for each core, at most 6 | How many worker processes assemble a large compilation unit. When it is not set, zr also uses fewer workers if the machine does not have the memory for them. |
| `ZR_TIMING` | flag | off | Prints to stderr the seconds that each phase of a build takes. |
| `ZR_CODE_CACHE` | `0`, `1`, `verify` | `1` | A build keeps the machine code of each function of the runtime object and of eval support in `<cache>/store/code/`, by a fingerprint of the function's IR, and assembles only the functions whose IR changed. `0` assembles every function. `verify` assembles every function, and stops when the kept code differs. |
| `ZR_LEDGER` | `0`, `1` | `1` in a checkout, else `0` | With the ledger, the runtime's symbol table starts from the table of the last build (`<cache>/ledger-<target>.json`): each name keeps its id, and a new name takes a free id, so most functions keep their code (`ZR_CODE_CACHE`) and eval support keeps its ids. A name that a build no longer uses frees its id at the next build, and until then `Symbol.all_symbols` still lists it. `0` numbers the names from the sources only, as an install, a release and the compiled compiler's build do. |
| `ZR_HANDED` | set by zr | unset | Set when `exe/zr` starts itself again with the collector's limits: this process already decided not to give the command to the compiled compiler, so the new one does not check every source again. zr deletes it at once; a program never sees it. |
| `ZR_GC_ADDED` | set by zr | unset | Set with the collector's limits when zr starts itself again, so that zr removes the limits from the environment of a program that `zr run` runs. zr deletes it at once. |
| `ZR_RUN_CACHE` | `0`, `1` | `1` | `zr run` keeps each binary it builds, with the digest of every file it was built from, in `<cache>/store/run/`, at most 2 GB. A second run whose files are all the same runs the kept binary with no build. A program with a require that stays for the run time is not kept. `0` builds each run. |
| `ZR_ISEQ_CACHE` | `0`, `1` | `1` | Under CRuby, zr keeps the compiled instructions of its own Ruby files in `<cache>/store/iseq/`, by the path and bytes of each file, so a start of `zr` does not compile them again (73 ms). `0` compiles them at each start. It is off while Coverage runs. |
| `ZR_SERVER` | `0`, a path | unset | Unset: `zr run` and `zr build` send the build to the server that `zr-dev serve` runs, when one listens at `<cache>/server.sock`. `0`: they always build alone. A path: they use the server that listens at that socket. See [Tools](tools.md#build-server). |
| `ZR_VERIFY` | flag | off | Checks dominance and types in every IR function before it is assembled, and checks that each pass reported the changes it made (`IR::Analysis`). |
| `ZR_BINARY` | a path | unset | The compiled compiler that `exe/zr` checks and runs, in place of `bin/zr` or the cache's. Its manifest is `<path>.manifest`. |
| `ZR_COMPILED` | `0`, `1` | unset | Whether `exe/zr` gives `run`, `build` and `machine` to the compiled compiler (`bin/zr` in a checkout, `self-<version>-<id>/zr` in the user cache for a gem, or `ZR_BINARY`). Unset: an installed gem builds the compiled compiler at its first build (some minutes) and uses it after that; a checkout never uses it, because almost every edit makes `bin/zr` out of date. `1`: a checkout uses `bin/zr`, and builds it first when it is out of date (a file under `exe/zr`, `lib`, `runtime` or `vendor/ruby` changed). A `ZR_BINARY` also selects it. `0`: ruby runs every command. `bin/test` and the rake tasks set `0` if it is not set. |
| `ZR_HOST_RUBY` | a command | `ruby` | The ruby that a `zr-dev` tool starts its children with when zr compiled the tool into a binary (`Dev.ruby`), and that the compiled compiler starts to read `--gem` and a Gemfile.lock when `exe/zr` did not read them first. |
| `ZR_TUNE` | flag | on | `0` runs the compiler with ruby's own collector settings and without YJIT. When it is on, a build that lowers the kernel, the core or eval support starts `zr` again with larger collector limits (`RUBY_GC_MALLOC_LIMIT`, `RUBY_GC_OLDMALLOC_LIMIT`), and heavy work turns on YJIT. zr does not change limits that you set. |
| `ZR_EVAL` | `walk` | unset | `walk` makes a native program use the tree-walking interpreter for eval, in place of the eval compiler. A wasm program always uses the tree-walking interpreter. See [Eval in a compiled program](../explanation/eval-in-a-compiled-program.md). |
| `ZR_WASM_NAMES` | flag | off | A WASI module gets a `name` section, so that wasmtime's traps and profiles show zr's function names. It changes the module's bytes. |
| `ZR_WASM_WIDTH` | a number | 256 | In a WASI module, a function with more blocks than this dispatches to its blocks in two steps, in groups of this size. |
| `GEM_HOME`, `GEM_PATH` | directories | ruby's | Where rubygems finds the zr gem itself, and the gems that `--gem NAME=VERSION` and a Gemfile.lock name. A build reads no other gem from here: a program's library is zr's `vendor/ruby`. |
| `BUNDLE_GEMFILE` | a Gemfile | unset | `bundle exec` sets it. A build then reads the gems of its lock before zr's standard library, as `bundle exec ruby` does; `--gemfile` wins over it. zr never needs `bundle exec`, and never starts bundler inside itself. See [How to use a library or a gem](../how-to/use-a-library-or-gem.md#another-version-of-a-gem). zr's own development Gemfile never applies. |
| `TMPDIR` | a directory | `/tmp` | Where a build writes its temporary files. When neither `TMPDIR` nor `/tmp` is a directory that zr can write to, zr stops and says to set `TMPDIR`. |
| `CC` | a command | unset | On a glibc aarch64 Linux, the C compiler that links an `aarch64-linux-musl` binary, before `aarch64-linux-musl-gcc` and `musl-gcc`. It must link against musl. |
| `OPENSSL_DIR` | a prefix | unset | `zr doctor` looks for OpenSSL 3 in `$OPENSSL_DIR/lib`, as a compiled program does (see [Compiled programs](#compiled-programs)). |
| `RUBY_GC_MALLOC_LIMIT`, `RUBY_GC_OLDMALLOC_LIMIT` | numbers | set by zr | ruby's collector limits. zr sets them for its own heavy work (`ZR_TUNE`), and removes them from the environment of a program that `zr run` runs. A value that you set wins. |
| `RUBYOPT`, `RUBYLIB`, `BUNDLER_SETUP`, `BUNDLE_BIN_PATH`, `BUNDLER_VERSION` | | | zr clears these for the child that reads a Gemfile.lock, so that the host's bundle does not load into it. The compiled compiler runs without `BUNDLER_SETUP`. A `-rbundler/setup` in `RUBYOPT` still loads into the `zr` command itself; zr needs no bundle. |
| `PATH` | directories | | zr looks here for the tools of a target (for example `aarch64-linux-musl-gcc`), and `zr run --emit wasm` looks here for `wasmtime`. |
| `DEVELOPER_DIR`, `SDKROOT` | directories | set by zr | When zr runs `cc` on macOS, it sets these to the install that the SDK comes from. zr keeps values that you set. |

### Compiled programs

A program that zr built reads these when it starts or when it needs
them.

| Variable | Values | Default | Effect |
|---|---|---|---|
| `ZR_GC_STRESS` | set (any value) | unset | Collects at every allocation, and poisons freed cells, so that a value the collector does not find fails at once. |
| `ZR_GC_VERIFY` | set (any value) | unset | Checks every minor collection against a full trace, and tells which store the write barrier missed. |
| `ZR_GC_TRACE` | set (any value) | unset | Prints one line to stderr for each collection. See [Memory and the collector](../explanation/memory-and-the-collector.md#read-the-collector-trace). |
| `ZR_MCACHE` | `0`, `verify` | unset | `0`: fills no inline cache, so every send looks up its method. `verify`: checks every cache hit against a fresh lookup, and stops at the first that is different. |
| `OPENSSL_DIR` | a prefix | unset | `require "openssl"` in a macOS program opens `libssl.3.dylib` in `$OPENSSL_DIR/lib` and nowhere else. When it is not set, the program looks in the Homebrew and MacPorts prefixes. |
| `ZR_PREFIX` | a directory | `~/.zr` | The install prefix that `RbConfig` gives. |
| `ZR_BINDIR` | a directory | `$ZR_PREFIX/bin` | `RbConfig::CONFIG["bindir"]`. |
| `ZR_RUBY_INSTALL_NAME` | a name | `zr` | `RbConfig::CONFIG["ruby_install_name"]`. |
| `ZR_CEXT_HDRDIR`, `ZR_CEXT_ARCHHDRDIR` | directories | below `$ZR_PREFIX/include` | The header directories that `RbConfig` gives. |
| `CC`, `CXX`, `LD` | commands | `cc`, `c++`, `ld` | The compilers that `RbConfig` gives. |

A program also reads the variables that ruby reads, for example
`HOME`, `TMPDIR`, `PATH` and `RUBY_BOX`, with the same meaning.

## For the tests

`bin/test`, the rake test tasks and the test harness read these.

| Variable | Values | Default | Effect |
|---|---|---|---|
| `TARGET` | a triple | this host | Builds and runs the programs for that target. It sets `ZR_TARGET`. See [How to test on another target](../how-to/test-on-another-target.md). |
| `ZR_TARGET` | a triple | this host | The target that the tests build for. Set `TARGET` in its place. |
| `GC` | `stress` | unset | Sets `ZR_GC_STRESS=1`. |
| `ZR_GC_STRESS` | `1` | unset | The spec tier runs each program with `ZR_GC_STRESS=1` and gives it four times the time limit. `programs_test` adds a stress run of each program. |
| `SLOW` | `1`, or a number | unset | Also reports the 25 slowest files and the 20 slowest examples. A number above 1 is the count of examples to report. |
| `N` | a pattern | unset | Runs only the examples whose name matches (minitest `-n`). |
| `X` | a pattern | unset | Leaves out the examples whose name matches (minitest `-e`). |
| `A` | minitest options | unset | Other options for minitest. |
| `MT_CPU` | a number | one for each 2 GB of memory after a quarter (at least 4 GB) is kept free, and at most two fewer than the cores; 4 for `test/e2e` | How many worker processes a tier forks. This is minitest's own name. |
| `ZR_COMPILED` | `0`, `1` | `0` | The tests run the compiler under ruby unless this is set. |
| `ZR_TEST_TIMEOUT` | seconds | 180, or the suite's own limit | How long one example can take before the tier stops its worker and reports a failure. `0` waits forever, for a debugger session. A value that you set applies to every suite. |
| `ZR_TEST_RECYCLE_MB` | megabytes | 600 | How much a worker can grow after its fork before the tier stops it and forks a new one. |
| `ZR_TEST_SECONDS` | seconds | 60 | The time limit for a program that a test runs. |
| `ZR_TEST_RESIDENT_MB` | megabytes | 2048 | The memory limit, in resident megabytes, for a program that a test runs through `Checks` (`test/test_helper.rb`). |
| `ZR_TEST_BUILD_MB` | megabytes | 2048 | The memory limit for a build, summed over its process group. A whole program can have a higher limit with `build_mb:` in `Zr::E2E::HOW`. |
| `ZR_TEST_RUN_MB` | megabytes | 1024 | The memory limit for a run. A whole program can have a higher limit with `run_mb:`. |
| `ZR_TEST_BUILT` | flag | on | `0`: the run does not build or load the runtime before it forks its workers. Use it for a unit file that builds no program. A file that does build then builds the runtime cold. |
| `ZR_TEST_BINARIES` | `0`, `1` | on for a native target | The spec tier keeps each example's binary in the cache, keyed by every input of its bytes. A later run of an unchanged example uses the kept binary and does not build. `1` also keeps WASI modules. `0` keeps nothing. `zr-dev cache prune` deletes old ones. |
| `ZR_TEST_BINARIES_GB` | gigabytes | 8 | The maximum size of the kept binaries (`<cache>/store/binary/`). Before a tier starts, it deletes the ones used least recently. |
| `ZR_TEST_WASM_COMPILER` | `winch`, `cranelift` | `winch` | The wasmtime compiler for the tests. Winch is wasmtime's baseline compiler. It compiles fast, and a test needs the output, not the speed. `zr-dev bench` uses Cranelift. |
| `ZR_TEST_WASM_MEMORY` | bytes | 1 GiB | wasmtime's `max-memory-size` in the tests. |
| `ZR_TEST_WASM_DEFECTS` | `0` | unset | `0` runs the wasm tests of `programs_test` that are known to fail, in place of a skip. |
| `WASMTIME` | a command | `wasmtime` | The wasmtime that the tests run. |
| `ZR_BLESS` | `1` | unset | A snapshot test writes its expected file again, in place of a comparison: the HIR dumps, the disassembly listing, the descriptions and the libSystem list. |
| `ZR_DIFFERENTIAL` | a number | 500 | How many random functions `regalloc_differential_test` generates. |
| `ZR_SEED` | a number | random | The seed of `regalloc_differential_test`. A failure prints the seed to use. |
| `OPENSSL_DIR` | a prefix | unset | Where ruby's reference run finds OpenSSL, as for a compiled program. |
| `CI` | any value | unset | Also writes a JUnit report to `tmp/junit`. |

## For tools

The `zr-dev` commands read these. See [Tools](tools.md#zr-dev).

| Variable | Command | Default | Effect |
|---|---|---|---|
| `RUBY_SRC` | `zr-dev gen`, `zr-dev vendor`, `zr-dev rubyspec` | `~/dev/github.com/ruby/ruby` when it exists, else `tmp/ruby` | A CRuby checkout that has the commit `Zr::RUBY_REVISION` (`lib/zr/version.rb`). The generators read the C sources at that commit, and `zr-dev vendor` ruby's own library. `zr-dev rubyspec` runs its `spec/` directory, and needs the checkout at that commit. |
| `PRISM_SRC` | `zr-dev gen prism_encoding_tables`, `zr-dev vendor` | `~/dev/prism`, else `tmp/prism-1.9.0` | A prism checkout that has the tag `v1.9.0`, or a release tree of prism 1.9.0. |
| `NKF_SRC` | `zr-dev gen nkf` | the installed nkf gem's `ext/nkf/nkf-utf8/utf8tbl.c` | The path of nkf's `utf8tbl.c`. The `--source` option has priority. |
| `CHECK` | `rake gen` | unset | Any value: compare each generated file, and write nothing (`zr-dev gen all --check`). |
| `MKCONSTANTS` | `zr-dev gen tables` | the file in `RUBY_SRC` | The path of a copy of `ext/socket/mkconstants.rb` from the ruby 4.0.7 source. |
| `ZR_CACHE_DAYS` | `zr-dev cache prune` | 1 | Keeps cache files used in this many days. The `--days` option (`zr-dev cache prune --days 3`) has priority. |
| `ZR_GEM_CORPUS` | `zr-dev gems` | unset | A directory of unpacked gems, `<dir>/<name>`, that `zr-dev gems` looks in first, by name. It never lists the directory. The `--corpus` option has priority. |
| `ZR_GEMS_ZR` | `zr-dev gems` | this checkout | A copy of zr that `zr-dev gems snapshot` made, to build with, so that a sweep runs while this checkout changes. The `--zr` option has priority. |
| `ZR_DISPATCH_TRACE` | `zr-dev spec dispatch` | off | A flag. Prints each call that the command tries. |
