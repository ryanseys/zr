# Command line

ze0 has two commands. `ze0` is the gem's command. `bin/ze0` is the
checkout's command: it has every `ze0` command and five more that need
the tests and tools in the repository.

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

## `bin/ze0`

```
ze0 test <filter>... | --all          does ze0 answer what ruby answered?
             [--gc plain|stress] [--show N] [--target <triple>] [--baseline <rows>]
ze0 bench [<filter>...]               how long does what ze0 built take?
             [--runs N] [--target <triple>]
ze0 check [<file>...]                 the repo's own checks, a process a file
ze0 stage1                            ze0 compiles itself, twice, to the same bytes
ze0 stage2                            the compiler compiled by itself is a fixed point
```

### `bin/ze0 test`

Builds and runs corpus programs and compares each answer with its
recording.

| Argument | Meaning |
|---|---|
| `<filter>` | a directory (`lang/blocks/`), a suite (`ze0::`) or any part of a case's name (`core::string/upcase`) |
| `--all` | every program in the corpus |
| `--gc stress` | collect at every allocation (`ZR_GC_STRESS=1`) |
| `--show N` | list at most N rows of each bucket (default 10) |
| `--target <triple>` | build and run for that target |
| `--baseline <file>` | pass when every defect row is one the file lists |

Every program goes into one bucket:

| Bucket | Meaning |
|---|---|
| `skipped` | no recording, or a directive opts the program out |
| `refused` | ze0 named a form it does not compile, at its line |
| `backend` | the build made no binary, or passed its memory bound |
| `matched` | the binary answered what ruby answered |
| `diverged` | the binary answered something else |
| `crashed` | the binary died on a signal ruby did not, or passed its memory bound |
| `timeout` | the binary ran past the time limit |

Only `diverged`, `crashed` and `timeout` are defects. Every row goes to
`tmp/sweep.txt`.

### `bin/ze0 bench`

Builds each benchmark in `test/bench/` that matches a filter, checks
its answer, and prints the median time of `--runs` runs (default 3)
beside `ruby` and `ruby --yjit`.

### `bin/ze0 check`

Runs each `test/unit/*_test.rb` file whose name holds one of the
arguments, or all of them, one process per file or shard.

### `bin/ze0 stage1` and `bin/ze0 stage2`

`stage1` compiles the compiler (`tools/stage.rb`) twice, in two
processes with separate caches, and compares the compiler's and the
runtime's object bytes. `stage2` builds the compiler with ruby, then
with that binary, and compares the two binaries.

## Rake tasks

| Task | Runs |
|---|---|
| `rake` or `rake check` | `bin/ze0 check` |
| `rake "check[exe zr]"` | `bin/ze0 check exe zr` |
| `rake "corpus[lang/blocks/]"` | `bin/ze0 test lang/blocks/`; with no argument, `--all` |
| `rake stage1`, `rake stage2` | `bin/ze0 stage1`, `bin/ze0 stage2` |
| `MKCONSTANTS=<path> rake tables` | the OS table tools, then fails on a difference |
| `rake build`, `rake release` | Bundler's gem tasks |
