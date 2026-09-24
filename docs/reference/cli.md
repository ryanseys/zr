# The `zr` command

`zr` is the gem's command. In a checkout, it is `exe/zr`. This page
describes only `zr`. For the rake tasks and the `bin/` scripts of a
checkout, see [Rake tasks and scripts](rake-tasks.md).

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

`zr help <command>` and `zr <command> --help` (or `-h`) print the
options of `run`, `build` or `machine`. `zr --version` and `zr -v` are
the same as `zr version`.

An option takes its value as the next word or after `=`: `--emit wasm`
and `--emit=wasm` are the same. Options can come before or after
`<file.rb>`. Put `--` before `<file.rb>` when the file name starts
with `-`.

zr builds only on ruby 4.0.6, the version that `.ruby-version` gives.
On a different ruby, `run`, `build` and `machine` stop with exit
status 3.

## Options

| Option | `run` | `build` | `machine` | Effect |
|---|---|---|---|---|
| `-o`, `--output <path>` | no | required | required | Writes the output to `<path>`. |
| `--emit <kind>` | `binary` or `wasm` | `binary`, `obj` or `wasm` | `binary`, `obj` or `wasm` | The output kind. The default is `binary`. |
| `--target <triple>` | yes | yes | yes | Builds for `<triple>`. `zr targets` lists the triples. `--emit wasm` without `--target` means `wasm32-wasi`. |
| `--path-root <dir>` | yes | yes | yes | Writes source paths in the output as `<dir>` plus the path below zr's root or the working directory. `<dir>` must be an absolute path. |
| `-h`, `--help` | yes | yes | yes | Prints the help for the command. |

## `zr run [options] <file.rb> [args...]`

Compiles `<file.rb>`, runs it with `[args...]` as `ARGV`, then deletes
the build. Every word after `<file.rb>` goes to the program, also a
word that starts with `-`. The exit status is the program's own. If a
signal stops the program, `zr run` prints the signal number and exits
with status 1.

With `--emit wasm`, zr runs the module with `wasmtime run --dir .`, so
the module can read the working directory. `-o` and `--emit obj` are
usage errors for `run`: use `zr build` to keep the output.

`zr run` runs a native binary only on a host of the same target. For
another target, `zr run` exits with status 3; use `zr build` and copy
the binary.

## `zr build [options] <file.rb> -o <out>`

Compiles `<file.rb>` with the zr runtime to `<out>`.

| `--emit` | Output |
|---|---|
| `binary` (the default) | a native binary for the target |
| `obj` | an object file of the program's own code: Mach-O, or ELF for `aarch64-linux-musl` |
| `wasm` | a WASI module (the target is `wasm32-wasi`) |

A `wasm32` `--target` also makes a WASI module.

### Paths in the output

A binary contains the paths of its source files. `__FILE__`,
`__dir__`, backtraces, `$LOADED_FEATURES` and error_highlight read
them. Without `--path-root`, they are the paths on the machine that
built the binary.

With `--path-root=/src`, a file at `<working directory>/lib/a.rb` is
`/src/lib/a.rb` in the output. zr's own files below the root of the
gem or checkout also get the `/src` prefix. Thus two checkouts at two
paths, built with the same root, write the same bytes (`rake repro`
tests this). A main file given as a relative path keeps that path, as
in ruby. The program can read a file at a changed path only if that
path exists on the machine that runs the program.

## `zr machine [options] <file.rb> -o <out>`

Compiles one file of the [machine dialect](machine-dialect.md), without
the zr runtime. It takes the same options as `build`. Use it for work
on the runtime.

## `zr targets`

Prints a table: each target, the outputs zr can make for it, and the
outputs this host can make now.

```
TARGET                 OUTPUTS            ON THIS HOST
aarch64-apple-darwin   binary, obj        binary, obj
aarch64-linux-musl     binary, obj        obj
wasm32-wasi            wasm               wasm
```

See [Targets](targets.md).

## Messages

A usage error prints one line that tells what is wrong, and one line
that tells where to find help:

```
zr build: missing -o <path>
Run 'zr help build' for usage.
```

Other errors print one line that starts with `zr:`, for example
`zr: no such file: app.rb`.

## Exit status

| Status | Meaning |
|---|---|
| 0 | Success. For `zr run`, the program's own status. |
| 1 | An error. A build step failed; the message tells which. |
| 2 | A usage error: the command line is wrong. |
| 3 | A refusal: zr does not support the program, or this host cannot build the target, or the ruby is not 4.0.6. The message gives the form and its line, or the missing tool. |

A program that does not parse still builds. Its binary prints ruby's
syntax error report and exits with status 1, as ruby does.

The environment variables that change `zr` are in
[Environment variables](environment-variables.md).
