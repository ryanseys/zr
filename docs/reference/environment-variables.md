# Environment variables

This page lists every environment variable that zr reads. There are
three groups:

- [For users](#for-users): the `zr` command, and the programs it builds.
- [For the tests](#for-the-tests): `bin/minitest`, the rake test tasks and
  the test harness.
- [For tools](#for-tools): the `zr-dev` commands.

A *flag* is a variable that is on or off. Unset or empty gives the
default. `0` is off. Any other value is on (`Zr::Config.flag?`).

A `ZR_*` value, or a setting's flag, that zr cannot use stops the command with one line and
exit status 2. The line names the variable and a value that works:

```
zr: ZR_JOBS is "abc". Set it to a whole number of 1 or more, for example ZR_JOBS=4.
```

## For users

### The compiler

`zr`, and every rake task and `zr-dev` command that compiles, read these.
Each `ZR_*` setting also has a flag, which `zr` takes before the command
or right after its name, as in `zr --jobs 2 build app.rb -o app` or
`zr --no-tune -e 'p 1'`. The flag wins over the variable. `zr help`
lists the flags (`Zr::Config::SETTINGS`).

| Variable | Flag | Values | Default | Effect |
|---|---|---|---|---|
| `ZR_CACHE` | `--cache-dir DIR` | a directory | `tmp/cache` in a checkout; `$XDG_CACHE_HOME/zr` if `XDG_CACHE_HOME` is set; else `~/Library/Caches/zr` on macOS and `~/.cache/zr` on other hosts | Where zr keeps the built runtime, eval support, the prelinked images and the other cache files. `zr cache size` and `zr cache clean` also look in the user cache, which `XDG_CACHE_HOME` and `HOME` give, for the compiled compilers that older zr versions kept there (`self-*/`, `shipped-*/`). |
| `XDG_CACHE_HOME` | | a directory | unset | The base of the user cache for an installed gem (see `ZR_CACHE`). |
| `HOME` | | a directory | the user's | The user cache is below it when `XDG_CACHE_HOME` is not set. With no `HOME` (some containers and CI jobs), zr stops and says to set `HOME` or `ZR_CACHE`. |
| `ZR_CACHE_MAX_GB` | `--cache-max-gb GB` | a number of GB, 0 or more | 5 | After a build, an installed zr deletes the cache entries that were used longest ago and that no root names, and then the compiled compilers that older zr versions kept, when the cache is larger than this. It measures at most once a day. `0` turns this off. A checkout never does it; use `zr cache clean`. |
| `ZR_LINK_ARGS` | `--link-args WORDS` | words | none | Arguments for the system linker, split as a shell splits them, before the `--link` arguments of the command. They make zr link a native binary with `cc` (see `--link` in [The `zr` command](cli.md)). A WASI module or an object ignores them. |
| `ZR_EXT_OBJECTS` | `--ext-objects PATH=OBJ,...` | words | none | C extensions that the build links in. Each word is the path of a bundle, where ruby would load it from (a `require` that finds that path loads the extension), then `=` and the object files that hold its code, `,`-separated. zr links the objects into the binary with `cc`, and runs the extension's `Init_` function where the require runs. A bundle alone, with no `=`, is a precompiled bundle that the build runs as `ZR_EXT` says. Paths become absolute. |
| `ZR_EXT` | `--ext static\|embed\|dynamic` | choice | `static` | How a build runs a C extension. `static` links the extension's objects into the binary, and embeds a gem that has only a precompiled bundle. `embed` relinks the bundle into the binary at build time with zr's own linker: its segments go in as segments of the executable, its fixups become the executable's, its calls of ruby's C API bind to zr's, and nothing is loaded at run time. `dynamic` exports zr's C API from the binary and loads the bundle with `dlopen` where the require runs, so the bundle must stay at its path. |
| `ZR_NATIVE_EXT` | `--native-ext GEM[=VERSION],...` | words | none | Gems whose C extension the build uses in place of a port: each gem as this ruby installed it, the newest version or the one given. When the install left the extension's objects in the gem's `ext/` directory, zr reads mkmf's Makefile there for the objects and libraries and links them in, as `ZR_EXT_OBJECTS` does. A precompiled gem has only a bundle for each ruby (`lib/nokogiri/4.0/nokogiri.bundle`): then the binary exports zr's C API and loads that bundle with `dlopen` where the require runs, so the bundle must stay at its path. A gem with neither stops the build. |
| `ZR_LINKER` | `--linker auto|ruby|cc` | `auto`, `ruby`, `cc` | `auto` | The macOS linker. `auto`: zr's own Mach-O linker, and `cc` for a link that zr's linker refuses. `ruby`: zr's linker only; a link it cannot do stops with a message. `cc`: the system linker always. Another value is an error. |
| `ZR_DEBUG` | `--backtrace`, `--no-backtrace` | `0`, `1` | `0` | `1`: an error that stops zr shows its backtrace. Otherwise zr prints one line: the message, or for a defect in zr, `zr: internal error: ...` and where to report it. |
| `ZR_JOBS` | `--jobs N`, `-j N` | a whole number, 1 or more | one for each core, at most 6 | How many worker processes assemble a large compilation unit. When it is not set, zr also uses fewer workers if the machine does not have the memory for them. |
| `ZR_TIMING` | `--timing`, `--no-timing` | flag | off | Prints to stderr each phase of a build as it starts, and the seconds it took as it ends. |
| `ZR_CODE_CACHE` | `--code-cache 1|0|verify` | `0`, `1`, `verify` | `1` | A build keeps the machine code of each function of the runtime object and of eval support in `<cache>/store/code/`, by a fingerprint of the function's IR, and assembles only the functions whose IR changed. `0` assembles every function. `verify` assembles every function, and stops when the kept code differs. |
| `ZR_GC_ADDED` | | set by zr | unset | Set with the collector's limits when zr starts itself again, so that zr removes the limits from the environment of a program that `zr run` runs. zr deletes it at once. |
| `ZR_RUN_CACHE` | `--run-cache`, `--no-run-cache` | `0`, `1` | `1` | `zr run` keeps each binary it builds, with the digest of every file it was built from, in `<cache>/store/run/`, at most 2 GB. A second run whose files are all the same runs the kept binary with no build. A program with a require that stays for the run time is not kept. `0` builds each run. |
| `ZR_TRACE` | `--trace`, `--no-trace` | flag | off | Builds the program with its trace events armed, as `--trace` does. The flag wins when both are given. |
| `ZR_SERVER` | `--server 0|SOCKET` | `0`, a path | unset | Unset: `zr run` and `zr build` send the build to the server that `zr-dev serve` runs, when one listens at `<cache>/server.sock`. `0`: they always build alone. A path: they use the server that listens at that socket. See [Tools](tools.md#build-server). |
| `ZR_VERIFY` | `--verify`, `--no-verify` | flag | off | Checks dominance and types in every IR function before it is assembled, and checks that each pass reported the changes it made (`IR::Analysis`). |
| `ZR_KERNEL_CHECKED` | `--kernel-checked`, `--no-kernel-checked` | flag | off | Lowers the kernel with a check at each operator whose meaning differs from Ruby's: a plain `+ - * <<` that wraps (a signed type) or leaves `[0, 2**64)` (a `Ptr`), a `/ %` with a negative operand or a zero divisor, and a `>>` by the width or more. A failed check prints the kernel file and line, then aborts. It finds the places that need `Machine.add_wrap`, `Machine.sdiv` or a fix, so that the kernel means the same on CRuby. It is part of the runtime digest. |
| `ZR_HOST_RUBY` | `--host-ruby RUBY` | a command | `ruby` | The ruby that a `zr-dev` tool starts its children with (`Dev.ruby`), and that zr starts when it needs ruby itself: to resolve gems (`lib/zr/gem_set.rb`), and for ruby's report of a syntax error (`lib/zr/config.rb`). |
| `ZR_TUNE` | `--tune`, `--no-tune` | flag | on | `0` runs the compiler with ruby's own collector settings and without YJIT. When it is on, a build that lowers the kernel, the core or eval support starts `zr` again with larger collector limits (`RUBY_GC_MALLOC_LIMIT`, `RUBY_GC_OLDMALLOC_LIMIT`), and heavy work turns on YJIT. zr does not change limits that you set. |
| `ZR_EVAL` | `--eval-mode walk` | `walk` | unset | `walk` makes a native program use the tree-walking interpreter for eval, in place of the eval compiler. A wasm program always uses the tree-walking interpreter. See [Eval in a compiled program](../explanation/eval-in-a-compiled-program.md). |
| `ZR_WASM_NAMES` | `--wasm-names`, `--no-wasm-names` | flag | off | A WASI module gets a `name` section, so that wasmtime's traps and profiles show zr's function names. It changes the module's bytes. |
| `ZR_WASM_WIDTH` | `--wasm-width N` | a number | 256 | In a WASI module, a function with more blocks than this dispatches to its blocks in two steps, in groups of this size. |
| `GEM_HOME`, `GEM_PATH` | | directories | ruby's | Where rubygems finds the zr gem itself, and the gems that `--gem NAME=VERSION` and a Gemfile.lock name. A build reads no other gem from here: a program's library is zr's `vendor/ruby`. |
| `BUNDLE_GEMFILE` | | a Gemfile | unset | `bundle exec` sets it. A build then reads the gems of its lock before zr's standard library, as `bundle exec ruby` does; `--gemfile` wins over it. zr never needs `bundle exec`, and never starts bundler inside itself. See [How to use a library or a gem](../how-to/use-a-library-or-gem.md#another-version-of-a-gem). zr's own development Gemfile never applies. |
| `TMPDIR` | | a directory | `/tmp` | Where a build writes its temporary files. When neither `TMPDIR` nor `/tmp` is a directory that zr can write to, zr stops and says to set `TMPDIR`. |
| `CC` | | a command | unset | On a glibc aarch64 Linux, the C compiler that links an `aarch64-linux-musl` binary, before `aarch64-linux-musl-gcc` and `musl-gcc`. It must link against musl. |
| `OPENSSL_DIR` | | a prefix | unset | `zr doctor` looks for OpenSSL 3 in `$OPENSSL_DIR/lib`, as a compiled program does (see [Compiled programs](#compiled-programs)). |
| `RUBY_GC_MALLOC_LIMIT`, `RUBY_GC_OLDMALLOC_LIMIT` | | numbers | set by zr | ruby's collector limits. zr sets them for its own heavy work (`ZR_TUNE`), and removes them from the environment of a program that `zr run` runs. A value that you set wins. |
| `RUBYOPT`, `RUBYLIB`, `BUNDLER_SETUP`, `BUNDLE_BIN_PATH`, `BUNDLER_VERSION` | | | | zr clears these for the child that reads a Gemfile.lock, so that the host's bundle does not load into it. A `-rbundler/setup` in `RUBYOPT` still loads into the `zr` command itself; zr needs no bundle. |
| `PATH` | | directories | | zr looks here for the tools of a target (for example `aarch64-linux-musl-gcc`), and `zr run --emit wasm` looks here for `wasmtime`. |
| `DEVELOPER_DIR`, `SDKROOT` | | directories | set by zr | When zr runs `cc` on macOS, it sets these to the install that the SDK comes from. zr keeps values that you set. |

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
| `ZR_RUBY` | a path | set by `zr` | The `zr` that ran the program: `zr run` and `zr app.rb` set it to the path of the `zr` command. `RbConfig.ruby` gives it, so `system(RbConfig.ruby, "-e", ...)` runs zr. Without it, `RbConfig.ruby` is `$ZR_BINDIR/zr` when `ZR_BINDIR` or `ZR_PREFIX` is set, else the first `zr` on `PATH`, else `~/.zr/bin/zr`. |
| `ZR_HOME` | a directory | set by `zr` | The ruby tree of the `zr` that ran the program (`vendor/ruby` in zr's gem), which has an installed ruby's layout. `zr run` and `zr app.rb` set it, as they set `ZR_RUBY`. It is the install prefix of `RbConfig` and `$LOAD_PATH` unless `ZR_PREFIX` is set, as JRuby and TruffleRuby give their home. A program that no zr ran has no home, and its `RbConfig::TOPDIR` is nil, as for a ruby that is not installed. The program's `ENV` does not show it. |
| `ZR_PREFIX` | a directory | `$ZR_HOME`, else `~/.zr` | The install prefix that `RbConfig` and `$LOAD_PATH` give. `RbConfig::TOPDIR` is the prefix when its `lib/ruby/4.0.0` exists. |
| `ZR_BINDIR` | a directory | the `exe` directory of zr's gem under `ZR_HOME`, else `$ZR_PREFIX/bin` | `RbConfig::CONFIG["bindir"]`. |
| `ZR_RUBY_INSTALL_NAME` | a name | `zr` | `RbConfig::CONFIG["ruby_install_name"]`. |
| `ZR_CEXT_HDRDIR`, `ZR_CEXT_ARCHHDRDIR` | directories | below `$ZR_PREFIX/include` | The header directories that `RbConfig` gives. |
| `CC`, `CXX`, `LD` | commands | `cc`, `c++`, `ld` | The compilers that `RbConfig` gives. |

A program also reads the variables that ruby reads, for example
`HOME`, `TMPDIR`, `PATH` and `RUBY_BOX`, with the same meaning.

## For the tests

`bin/minitest`, the rake test tasks and the test harness read these.
To select tests by name, give minitest's own options (`-i`, `-e`) to
`bin/minitest`.

| Variable | Values | Default | Effect |
|---|---|---|---|
| `ZR_PROGRAMS` | paths below `test/programs`, separated by commas | every program | The program tests that `test/programs_test.rb` defines: the programs below each path. A path is a directory or one program, such as `core/gc,lang/blocks`. |
| `ZR_TARGET` | a triple | this host | Builds and runs the programs for that target. See [How to test on another target](../how-to/test-on-another-target.md). |
| `ZR_GC_STRESS` | `1` | unset | Each program that a test runs gets `ZR_GC_STRESS=1` in its environment, and collects at every allocation. |
| `ZR_TEST_FAIL_FAST` | `1` | unset | The run starts no more tests after one fails. |
| `SLOW` | `1`, or a number | unset | Also reports the 25 slowest files and the 20 slowest tests. A number above 1 is the count of tests to report. |
| `COVERAGE` | flag | off | Measures the line and branch coverage of `lib/` (not `lib/zr/runtime`) with SimpleCov, and writes `tmp/coverage/index.html`. The workers of the run merge their results. It is a switch of the test harness (`test/support/coverage_run.rb`), not a `ZR_*` setting, so `Zr::Config` does not read it. |
| `MT_CPU` | a number | one for each 2 GB of memory after a quarter (at least 4 GB) is kept free, and at most two fewer than the cores | How many worker processes a run forks (`test/support/workers.rb`). This is minitest's own name. |
| `ZR_TEST_TIMEOUT` | seconds | 180, or the suite's own limit | How long one test can take before the tier stops its worker and reports a failure. `0` waits forever, for a debugger session. A value that you set applies to every suite. |
| `ZR_TEST_RECYCLE_MB` | megabytes | 600 | How much a worker can grow after its fork before the tier stops it and forks a new one. |
| `ZR_TEST_SECONDS` | seconds | 60 | The time limit for a program that a test runs. A ruby run of a program test gets two times this limit, and a `zr build` of a test below `test/programs/cli/` five times. |
| `ZR_TEST_RESIDENT_MB` | megabytes | 2048 | The memory limit, in resident megabytes, for a program that a test runs through `Checks` (`test/test_helper.rb`). |
| `ZR_TEST_BUILD_MB` | megabytes | 2048 | The memory limit for a build, summed over its process group. A program test below `test/programs/cli/` can have a higher limit with `build_mb=` in its `.rb.limits` file. |
| `ZR_TEST_RUN_MB` | megabytes | 1024 | The memory limit for a run. A program test can have a higher limit with `run_mb=` in its `.rb.limits` file. |
| `ZR_TEST_HOST` | `1` | unset | The program tests run on CRuby over zr's kernel (`test/support/host_program.rb`), not as binaries. `test/programs_test.rb` then starts ruby again with large stacks and `--yjit`. The baseline is `test/baselines/host.txt`. A test that passed before with the same inputs passes at once from the result cache (`test/support/result_cache.rb`). |
| `ZR_TEST_FRESH` | `1` | unset | A host run (`ZR_TEST_HOST=1`) runs each test, also the ones that the result cache says passed. |
| `ZR_TEST_BUILT` | flag | on | `0`: the run does not build or load the runtime before it forks its workers. A file that builds then builds the runtime cold. A unit file without `# zr-test: runtime` or `# zr-test: eval` in its first lines builds nothing, so the run does not build the runtime for it (`test/support/needs.rb`). |
| `ZR_TEST_BINARIES` | `0`, `1` | on for a native target | The program tests keep each program's binary in the cache, keyed by every input of its bytes. A later run of an unchanged program uses the kept binary and does not build. A test below `test/programs/cli/` always builds. `1` also keeps WASI modules. `0` keeps nothing. `zr cache clean` deletes old ones. |
| `ZR_TEST_BINARIES_GB` | gigabytes | 8 | The maximum size of the kept binaries (`<cache>/store/binary/`). Before a tier starts, it deletes the ones used least recently. |
| `ZR_TEST_WASM_COMPILER` | `winch`, `cranelift` | `winch` | The wasmtime compiler for the tests. Winch is wasmtime's baseline compiler. It compiles fast, and a test needs the output, not the speed. `zr-dev bench` uses Cranelift. |
| `ZR_TEST_WASM_MEMORY` | bytes | 1 GiB | wasmtime's `max-memory-size` in the tests. |
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
| `RUBY_SRC` | `zr-dev gen`, `zr-dev vendor`, `zr-dev rubyspec`, `zr-dev cruby-test` | `~/dev/github.com/ruby/ruby` when it exists, else `tmp/ruby` | A CRuby checkout that has the commit `Zr::RUBY_REVISION` (`lib/zr/version.rb`). The generators read the C sources at that commit, and `zr-dev vendor` ruby's own library. `zr-dev rubyspec` runs its `spec/` directory and `zr-dev cruby-test` its `test/` directory; both need the checkout at that commit. |
| `PRISM_SRC` | `zr-dev gen prism_encoding_tables`, `zr-dev vendor` | `~/dev/prism`, else `tmp/prism-1.9.0` | A prism checkout that has the tag `v1.9.0`, or a release tree of prism 1.9.0. |
| `NKF_SRC` | `zr-dev gen nkf` | the installed nkf gem's `ext/nkf/nkf-utf8/utf8tbl.c` | The path of nkf's `utf8tbl.c`. The `--source` option has priority. |
| `CHECK` | `rake gen` | unset | Any value: compare each generated file, and write nothing (`zr-dev gen all --check`). |
| `MKCONSTANTS` | `zr-dev gen tables` | the file in `RUBY_SRC` | The path of a copy of `ext/socket/mkconstants.rb` from the ruby 4.0.7 source. |
| `ZR_GEM_CORPUS` | `zr-dev gems` | unset | A directory of unpacked gems, `<dir>/<name>`, that `zr-dev gems` looks in first, by name. It never lists the directory. The `--corpus` option has priority. |
