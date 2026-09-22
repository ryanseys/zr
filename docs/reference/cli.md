# Command line

`ze0` is the gem's command, and the only one. In a checkout it is
`exe/ze0`, and everything the repository itself needs -- the tests, the
bootstrap, the benchmark bank, the generated tables -- is a rake task.

## `ze0`

```
ze0 run <file.rb> [args]              compile a Ruby program with the zr runtime, and run it
ze0 build <file.rb> -o <bin>          compile a Ruby program with the zr runtime
ze0 machine <file.rb> -o <bin>        compile a kernel-dialect file alone
             [--emit obj|wasm] [--target <triple>]
ze0 zr run|build|machine ...          the same three commands, by their older names
ze0 targets                           the targets ze0 builds for, and what this host can do
ze0 version                           print ze0's version
ze0 help                              print the usage
```

### `ze0 run <file.rb> [args]`

Compiles the program, runs it with `args` as `ARGV`, and removes the
binary. The exit status is the program's own. With `--emit wasm`, runs
the module under `wasmtime run --dir .`.

### `ze0 build <file.rb> -o <out>`

Compiles the program to `out`.

| Option | Output |
|---|---|
| none | a native binary for the target |
| `--emit obj` | an object file of the program's own code: Mach-O, or ELF for `aarch64-linux-musl` |
| `--emit wasm` | a WASI module (the target is `wasm32-wasi`) |
| `--target <triple>` | builds for that target; see [Targets](targets.md) |

### `ze0 machine <file.rb> -o <out>`

Compiles one file of the [kernel dialect](kernel-dialect.md) with no
runtime. It takes the same options as `build`.

### `ze0 targets`

Prints each target, what ze0 builds for it, and what this host can
build for it now.

### Exit status

| Status | Meaning |
|---|---|
| 0 | the build succeeded (for `run`: the program's own status) |
| 1 | a build step failed; the message says which. A program that does not parse still builds: its binary prints ruby's syntax error report and exits 1, as ruby does |
| 2 | the command line is wrong; the usage goes to stderr |
| 3 | ze0 refused the program, or this host cannot build the target; the message names the form and its line, or the missing tool |

## Rake tasks

`rake -T` names them all. These are the ones a change reaches for.

### Tests

| Task | Runs |
|---|---|
| `rake build` | the runtime: its object, the prelinked image and the eval road |
| `rake` or `rake test` | the units, the specs and the end-to-end programs |
| `rake test:unit [N=/Exe/]` | ze0's own internals |
| `rake test:spec [N=] [GC=stress] [TARGET=]` | Ruby held to ruby, one compile an example |
| `rake test:e2e [TARGET=]` | whole programs through a real link |
| `rake test:spec:slow` | the slowest 25 files |
| `rake test:unit:isolated` | which files fail when run on their own |
| `minitest test/unit/zr_test.rb -n /gc/` | one file, or one example |

A tier builds the runtime itself, in its own process before it forks
its first worker, so the eight of them share one warm compiler. After
an edit under `lib` or `rt` that build is a cold one and takes minutes;
`rake build` asks for it on its own, which is the thing to do before a
run rather than in the middle of one.

Each tier is a `Minitest::TestTask`, so `N=` names the examples to run,
`X=` the ones to leave out, `A=` passes anything else to minitest, and
`MT_CPU=` says how many workers fork. `GC=stress` collects at every
allocation (`ZR_GC_STRESS=1`). `TARGET` names a triple to build and run
for; a target on its way in is held to `test/baselines/<triple>.txt`
rather than to the whole tier.

A spec example that ze0 refuses, or whose build produced no binary,
skips and is counted; only a wrong answer, a crash or a timeout fails.
That is the same division the buckets used to draw.

### The oracle, the bank and the bootstrap

| Task | Runs |
|---|---|
| `rake 'oracle[test/spec/core/string]'` | every spec literal re-checked against ruby 4.0.6, compiling nothing |
| `rake 'record[e2e/core/io/hello.rb]'` | runs ruby and writes its answer beside the program |
| `rake 'bench[--runs 5 fib]'` | builds each program in `benchmark/` that matches, checks its answer, and prints the median of `--runs` runs (default 5) beside `ruby` and `ruby --yjit`, with the binary's CPU time; a run of the whole bank writes its report to `benchmark/results/<stamp>-<revision>.txt` |
| `rake stage1` | compiles the compiler (`exe/ze0`) twice, in two processes with separate caches, and compares the compiler's and the runtime's object bytes |
| `rake stage2` | builds `exe/ze0` with ruby, then with that binary (`tmp/stage1/ze0 build exe/ze0`), and compares the two binaries |

### The rest

| Task | Runs |
|---|---|
| `MKCONSTANTS=<path> rake tables` | the OS table tools, then fails on a difference |
| `rake gen:*` | writes a generated file from its oracle; see [Tools](tools.md) |
| `rake diff:*` | holds a Ruby port to ruby's own implementation |
| `rake 'codesize[--all]'` | counts the instructions the backend writes for the runtime |
| `rake gem:build`, `rake gem:release` | Bundler's gem tasks |
