# The `zr` command

`zr` is the gem's command. In a checkout, it is `exe/zr`. This page
describes only `zr`. For the `bin/` scripts, the rake tasks and the
`zr-dev` commands of a checkout, see [Tools](tools.md).

```
Usage: zr <command> [options]

Commands:
  run <file.rb> [args...]     compile a program, run it, then delete the build
  build <file.rb> -o <out>    compile a program to a binary, a WASI module or an object
  machine <file.rb> -o <out>  compile one machine-dialect file (for runtime work)
  targets                     list the targets, and what this host can build
  doctor                      check this host: ruby, wasmtime, OpenSSL, gems, cache
  cache [path|size|clean]     show or clean the build cache
  version                     print the version
  help [<command>]            print help for zr or for one command
```

`zr help <command>` and `zr <command> --help` (or `-h`) print the
options of a command. `zr version` prints zr's version and the ruby
whose output it gives (`zr 0.1.0 (for ruby 4.0.7)`). `zr --version` and `zr -v` are the
same.

An option takes its value as the next word or after `=`: `--emit wasm`
and `--emit=wasm` are the same. For `build` and `machine`, options can
come before or after `<file.rb>`. For `run`, options come before
`<file.rb>`, because every word after it goes to the program. Put `--`
before `<file.rb>` when the file name starts with `-`.

zr builds only on ruby 4.0.7, the version that `.ruby-version` gives.
On a different ruby, `run`, `build` and `machine` stop with exit
status 3.

## Options

| Option | `run` | `build` | `machine` | Effect |
|---|---|---|---|---|
| `-o`, `--output <path>` | no | required | required | Writes the output to `<path>`. |
| `--emit <kind>` | `binary` or `wasm` | `binary`, `obj` or `wasm` | `binary`, `obj` or `wasm` | The output kind. The default is `binary`. |
| `--target <triple>` | yes | yes | yes | Builds for `<triple>`. `zr targets` lists the triples. `--emit wasm` without `--target` means `wasm32-wasi`. |
| `--path-root <dir>` | yes | yes | yes | Writes source paths in the output as `<dir>` plus the path below zr's root or the working directory. `<dir>` must be an absolute path. |
| `--link <arg>` | yes | yes | yes | Gives `<arg>` to the system linker (`cc`) for a native binary, once for each argument: an object, an archive, `-framework <name>`, `-Wl,<flags>` such as `-Wl,-sectcreate,<segment>,<section>,<file>` or `-Wl,-exported_symbols_list,<file>`. With a link argument, zr links with `cc`, not with its own linker, so the host needs a C toolchain. With `--emit obj` or `--emit wasm` it is a usage error. `ZR_LINK_ARGS` gives the same arguments. |
| `--gem <name>=<version\|dir>` | yes | yes | no | Uses this gem in place of the one in the Gemfile.lock or in zr's standard library, once for each gem: an installed version (`--gem csv=3.3.6`), or a directory with a gemspec or a `lib/` (`--gem rainbow=vendor/rainbow`). See [How to use a library or a gem](../how-to/use-a-library-or-gem.md#another-version-of-a-gem). |
| `--gemfile <path>` | yes | yes | no | Reads the gems of `<path>`'s lock (`Gemfile.lock`, or `gems.locked` for `gems.rb`) before zr's standard library, as `bundle exec ruby` does. `BUNDLE_GEMFILE` does the same. zr reads the lock with its own bundler, not the host's. |
| `--allow-runtime-require` | yes | yes | no | Lets a literal `require` in the program's own files that zr cannot find wait for the run time. The binary then carries the compiler (about 90 MB) to compile what it finds then. Without it, such a require stops the build; see [the require gate](#the-require-gate). |
| `--print-gems` | no | yes | no | After the build, prints the gems that the output was built with, as `zr inspect` does. |
| `-h`, `--help` | yes | yes | yes | Prints the help for the command. |

## `zr run [options] <file.rb> [args...]`

Compiles `<file.rb>`, runs it with `[args...]` as `ARGV`, then deletes
the build. Every word after `<file.rb>` goes to the program, also a
word that starts with `-`. The exit status is the program's own. If a
signal stops the program, the same signal then stops `zr run`, so the
shell sees the status that ruby gives (130 for `SIGINT`, 143 for
`SIGTERM`).

With `--emit wasm`, zr runs the module with `wasmtime run --dir .`, so
the module can read the working directory. If wasmtime is not on
`PATH`, `zr run --emit wasm` stops with status 1 before it builds. `-o` and `--emit obj` are
usage errors for `run`: use `zr build` to keep the output.

`zr run` keeps each native binary that it builds. A second run of the
same program, with the same bytes in the program and in every file it
requires, runs the kept binary without a build. `ZR_RUN_CACHE=0` turns
this off (see [Environment variables](environment-variables.md)).

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
paths, built with the same root, write the same bytes (`zr-dev repro`
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

## `zr gems [options] [<file.rb>]`

Prints each gem that a build can read, with its version and its
source: `stdlib` (ruby 4.0.7's library in zr), `port` (a gem with a C
part that zr ports), `Gemfile.lock` or `--gem`. For a gem that
replaces a port, the row also gives the versions whose C zr
implements. With `<file.rb>`, it prints only the gems that the build
of `<file.rb>` reads. `--gem`, `--gemfile` and `--target` work as for
`zr build`, and `--json` prints one JSON object for each gem.

```
$ zr gems app.rb
NAME     VERSION    SOURCE
csv      3.3.5      stdlib
english  0.8.1      stdlib
time     0.4.2      stdlib
```

## `zr inspect [--json] <binary>`

Prints the gems that zr built `<binary>` with. Each binary, object and
WASI module carries a manifest: the zr version, the ruby version, the
target, and each gem with its version and source. The manifest has no
paths, so two machines build the same bytes.

## `zr diff [options] <file.rb> [args...]`

Runs `<file.rb>` with `[args...]` under ruby and as a zr binary, and
compares stdout, stderr, the exit status and the signal. It prints the
kind of difference, then a unified diff of each part that differs. It
exits with status 0 only when the two runs are the same.

| Kind | Meaning |
|---|---|
| `same` | Every part is the same. |
| `output-diff` | Only stdout differs. |
| `exception-diff` | stderr differs: ruby's report of an exception, or a warning. |
| `status-diff` | The exit statuses differ. |
| `crash` | A signal stopped the zr binary, and not ruby. |
| `timeout` | The zr binary ran longer than 60 seconds. |
| `refused` | zr does not support the program (the build's status 3). |
| `build-error` | The build failed for another reason. |

An object address (`0x` and 16 hex digits) is `0x...` in both outputs.
ruby reads the same `--gem` directories, and with `--gemfile` or
`BUNDLE_GEMFILE` it runs as `bundle exec ruby` does. Where ruby has
other versions of its gems than zr, the two runs can differ for that
reason; `zr gems` shows zr's.

## `zr doctor`

Checks what zr needs on this host, and prints one line for each check:

```
ok    zr                 0.1.0  /Users/you/.gem/ruby/4.0.0/gems/zr-0.1.0
ok    ruby               4.0.7
ok    host               aarch64-apple-darwin
ok    wasmtime           /opt/homebrew/bin/wasmtime
ok    openssl            /opt/homebrew/opt/openssl@3/lib/libssl.3.dylib
ok    libraries          stdlib of ruby 4.0.7 (59 gems), 17 ports
ok    cache              ~/Library/Caches/zr, 2703 MB
ok    fast compiler      current
```

`warn` means that zr can do less on this host: for example, with no
wasmtime, `zr run --emit wasm` does not work. Each `warn` and `fail`
line says what to do.

The fast compiler is zr compiled by itself. An installed zr builds it at
its first build (some minutes), and uses it for each later build. If
that build fails, ruby runs zr, and zr tries again one day later, at
most three times. `ZR_COMPILED=1` tries at once. `fail` means that zr
cannot build, and `zr doctor` then exits with status 1. Put the
output of `zr doctor` in a bug report.

## `zr cache [path|size|clean [--all]]`

zr keeps what it builds once in a cache: the runtime, eval support, the
prelinked images and the compiled compiler. The cache is some hundred
MB for each zr version.

| Command | Effect |
|---|---|
| `zr cache` or `zr cache path` | Prints the cache directory. |
| `zr cache size` | Prints what the cache holds, by kind. |
| `zr cache clean` | Deletes the files that this zr does not use, and the compiled compilers of other zr versions. The next build rebuilds nothing. |
| `zr cache clean --all` | Deletes every file in the cache. The next build makes them again. |

An installed zr also cleans its cache after a build when the cache is
larger than `ZR_CACHE_MAX_GB` (5 GB by default). It measures the cache
at most once a day.

## Messages

A usage error prints one line that tells what is wrong, and one line
that tells where to find help:

```
zr build: missing -o <path>
Run 'zr help build' for usage.
```

Other errors print one line that starts with `zr:`, for example
`zr: no such file: app.rb`.

A refusal of a form of Ruby gives the file, the line and the column,
the form, the source line with a caret under the column, and the page
that lists what zr supports:

```
zr: app.rb:2:1: zr does not support `BEGIN { }` here yet
    BEGIN { p 2 }
    ^
zr: https://github.com/ryanseys/zr/blob/main/docs/reference/support.md lists what zr supports
```

### The require gate

A literal `require` in the program's own files (the main file, and
each file that it reaches by `require_relative` or by a path) that zr
finds nowhere stops the build, with status 1:

```
zr: app.rb:2: cannot load such file -- rainbow. Give --gem rainbow=<dir> or a --gemfile that has it, put the require in `begin ... rescue LoadError`, or build with --allow-runtime-require
```

Without the gate, the require would wait for the run time, and the
binary would carry the compiler (about 90 MB) to compile what it finds
then. A require inside `begin ... rescue LoadError` (or `ScriptError`,
or `Exception`) does not stop the build: the program handles the
LoadError, as in ruby. A bare `rescue` does not catch LoadError, so it
does not count. A require in a library's file, and a require of a
computed name, do not stop the build either.

When a backend cannot compile code that the front end accepted, the
message starts with `zr: the backend cannot compile this program`. This
is a limit or a defect in zr, not a problem in the program. Please
report it.

## Exit status

| Status | Meaning |
|---|---|
| 0 | Success. For `zr run`, the program's own status. |
| 1 | An error. A build step failed, or a require in the program's own files has no file; the message tells which. For `zr diff`, the two runs differ. |
| 2 | A usage error: the command line is wrong. |
| 3 | A refusal: zr does not support the program, or this host cannot build the target, or the ruby is not 4.0.7. The message gives the form and its line, or the missing tool. |

A program that does not parse still builds. Its binary prints ruby's
syntax error report and exits with status 1, as ruby does.

The environment variables that change `zr` are in
[Environment variables](environment-variables.md).
