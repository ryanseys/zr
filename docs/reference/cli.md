# Command line

`zr` is the gem's command. In a checkout it is `exe/zr`. The
repository's own tools (tests, bootstrap, benchmarks, generated tables)
are rake tasks and `bin/` scripts.

## `zr`

```
Usage: zr <command> [options]

Commands:
  run <file.rb> [args...]     compile a program, run it, then delete the build
  build <file.rb> -o <out>    compile a program to a binary, a WASI module or an object
  machine <file.rb> -o <out>  compile one machine-dialect file (for runtime work)
  targets                     list the targets, and what this host can build
  version                     print the version
  help [<command>]            print help for zr or for one command
```

`zr help <command>` and `zr <command> --help` print the options of a
command. An option takes its value as the next word or after `=`
(`--emit wasm`, `--emit=wasm`). A wrong command line prints one line
that says what is wrong, and exits 2.

### `zr run [options] <file.rb> [args...]`

Compiles the program, runs it with `args` as `ARGV`, and deletes the
build. Every word after `<file.rb>` goes to the program, including
words that start with `-`. Put `--` before `<file.rb>` when its name
starts with `-`. The exit status is the program's own. With
`--emit wasm`, `wasmtime run --dir .` runs the module. `-o` and
`--emit obj` do not apply.

### `zr build [options] <file.rb> -o <out>`

Compiles the program to `out`. Options can come before or after
`<file.rb>`.

| Option | Output |
|---|---|
| none, or `--emit binary` | a native binary for the target |
| `--emit obj` | an object file of the program's own code: Mach-O, or ELF for `aarch64-linux-musl` |
| `--emit wasm` | a WASI module (the target is `wasm32-wasi`) |
| `--target <triple>` | builds for that target; see [Targets](targets.md) |
| `--path-root <dir>` | writes each path below zr's root, or below the directory the build runs in, as `<dir>` plus the rest of the path; see below |

A binary holds the paths of its files: `__FILE__`, `__dir__`,
backtraces, `$LOADED_FEATURES` and error_highlight read them. With no
`--path-root` they are the paths on the machine that built it. With
`--path-root=/src`, a file at `<build directory>/lib/a.rb` answers
`/src/lib/a.rb`, and so do zr's own files below the root of the gem
or checkout. So two checkouts at two paths, built with the same root,
write the same bytes (`rake repro` checks this). A main file named with
a relative path answers that path, as ruby does. The program cannot read
a file at a mapped path unless that path is there on the machine it
runs on.

### `zr machine [options] <file.rb> -o <out>`

Compiles one file of the [kernel dialect](kernel-dialect.md) with no
runtime. It takes the same options as `build`.

### `zr targets`

Prints a table: each target, the outputs zr makes for it, and the
outputs that this host can make now.

### Exit status

| Status | Meaning |
|---|---|
| 0 | the build succeeded (for `run`: the program's own status) |
| 1 | a build step failed; the message says which. A program that does not parse still builds: its binary prints ruby's syntax error report and exits 1, as ruby does |
| 2 | the command line is wrong; one line on stderr says what is wrong |
| 3 | zr refused the program, or this host cannot build the target; the message names the form and its line, or the missing tool |

## Rake tasks

`rake -T` names them all. These are the ones a change reaches for.

### Tests

| Task | Runs |
|---|---|
| `bin/setup` | installs the gems and builds the runtime |
| `bin/test [paths] [minitest options]` | the tests; with no paths, the three tiers |
| `rake build` | the runtime for this host: its object, the prelinked image and the eval support object |
| `rake build:self` | the compiler compiled by itself, which `exe/zr` then uses until a file under `lib`, `runtime`, `vendor` or the library tree changes (`ZR_COMPILED`) |
| `rake` or `rake test` | the three tiers: unit, spec, e2e |
| `rake test:unit` | zr's own internals |
| `rake test:spec` | Ruby specs, each checked against ruby 4.0.6 |
| `rake test:e2e` | whole programs, built and linked |
| `rake test:spec:slow` | the spec tier, and its 25 slowest files |
| `rake test test/unit/machine_test.rb N=/gc/` | one file, or one example |

`bin/test` and the tiers build the runtime first when it is missing or
out of date. After a change under `lib` or `runtime`, that build takes a
few minutes.

`N=` names the examples to run, `X=` the ones to leave out, `A=`
passes other options to minitest, and `MT_CPU=` sets the number of
workers. `GC=stress` collects at every allocation (`ZR_GC_STRESS=1`).
`TARGET` names a triple to build and run for. A target that zr does not
fully support yet is checked against `test/baselines/<triple>.txt`
instead of the whole tier.

A spec example that zr refuses, or whose build produced no binary,
skips and is counted. Only a wrong answer, a crash or a timeout fails.

### The oracle, the bank and the bootstrap

| Task | Runs |
|---|---|
| `rake 'oracle[test/spec/core/string]'` | every spec literal re-checked against ruby 4.0.6, compiling nothing |
| `rake 'record[test/e2e/lang/programs/hello.rb]'` | runs ruby and writes its answer beside the program |
| `rake 'bench[--runs 5 fib]'` | builds each program in `benchmark/` that matches, checks its answer, and prints the median of `--runs` runs (default 5) beside `ruby` and `ruby --yjit`, with the binary's CPU time; a run of the whole bank writes its report to `benchmark/results/<stamp>-<revision>.txt` |
| `rake stage1` | compiles the compiler (`exe/zr`) twice, in two processes with separate caches, and compares the compiler's and the runtime's object bytes |
| `rake repro` | builds one program from two copies of the tree at two paths, under another home, clock zone, locale and job count, with one `--path-root`, and compares the binaries and the objects (`rake repro[wasm]` adds the wasm module) |
| `rake stage2` | builds `exe/zr` with ruby, then with that binary (`tmp/stage1/zr build exe/zr`), and compares the two binaries |

### The rest

| Task | Runs |
|---|---|
| `MKCONSTANTS=<path> rake tables` | the OS table tools, then fails on a difference |
| `rake gen:*` | writes a generated file from its oracle; see [Tools](tools.md) |
| `rake 'codesize[--all]'` | counts the instructions the backend writes for the runtime |
| `rake gem:build`, `rake gem:release` | Bundler's gem tasks |
