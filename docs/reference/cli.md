# The `zr` command

`zr` is the gem's command. In a checkout, it is `exe/zr`. This page
describes only `zr`. For the `bin/` scripts, the rake tasks and the
`zr-dev` commands of a checkout, see [Tools](tools.md).

```
Usage: zr <command> [options]

Commands:
  run <file.rb> [args...]     compile a program, run it, then delete the build
  build <file.rb> -o <out>    compile a program to a binary, a WASI module or an object
  gems [<file.rb>]            list the gems that a build reads, and their sources
  inspect <binary>            print the gems that a binary was built with
  diff <file.rb> [args...]    run a program under ruby and as a zr binary, and compare
  doctor                      check this host: ruby, targets, wasmtime, OpenSSL, gems, cache
  cache [path|size|clean]     show or clean the build cache
  version                     print the version
  help [<command>]            print help for zr or for one command
```

`zr help <command>` and `zr <command> --help` (or `-h`) print the
options of a command. `zr version` prints zr's version and the ruby
whose output it gives (`zr 0.1.0 (for ruby 4.0.7)`). `zr --version` and `zr -v` are the
same.

An option takes its value as the next word or after `=`: `--emit wasm`
and `--emit=wasm` are the same. For `build`, options can
come before or after `<file.rb>`. For `run`, options come before
`<file.rb>`, because every word after it goes to the program. Put `--`
before `<file.rb>` when the file name starts with `-`.

zr runs on ruby 4.0.7, and on a later 4.0 release with a warning. On
another ruby, `run` and `build` stop with exit status 3,
and the message links [How to install zr](../how-to/install.md).

## Options

| Option | `run` | `build` | Effect |
|---|---|---|---|
| `-o`, `--output <path>` | no | required | Writes the output to `<path>`. |
| `--emit <kind>` | `binary` or `wasm` | `binary`, `obj` or `wasm` | The output kind. The default is `binary`. |
| `--target <triple>` | yes | yes | Builds for `<triple>`: `aarch64-apple-darwin`, `aarch64-linux-musl` or `wasm32-wasi`. `zr doctor` shows what this host can build. `--emit wasm` without `--target` means `wasm32-wasi`. |
| `--path-root <dir>` | yes | yes | Writes source paths in the output as `<dir>` plus the path below zr's root or the working directory. `<dir>` must be an absolute path. |
| `--link <arg>` | yes | yes | Gives `<arg>` to the system linker (`cc`) for a native binary, once for each argument: an object, an archive, `-framework <name>`, `-Wl,<flags>` such as `-Wl,-sectcreate,<segment>,<section>,<file>` or `-Wl,-exported_symbols_list,<file>`. With a link argument, zr links with `cc`, not with its own linker, so the host needs a C toolchain. With `--emit obj` or `--emit wasm` it is a usage error. `ZR_LINK_ARGS` gives the same arguments. |
| `--gem <name>=<version\|dir>` | yes | yes | Uses this gem in place of the one in the Gemfile.lock or in zr's standard library, once for each gem: an installed version (`--gem csv=3.3.6`), or a directory with a gemspec or a `lib/` (`--gem rainbow=vendor/rainbow`). See [How to use a library or a gem](../how-to/use-a-library-or-gem.md#another-version-of-a-gem). |
| `--gemfile <path>` | yes | yes | Reads the gems of `<path>`'s lock (`Gemfile.lock`, or `gems.locked` for `gems.rb`) before zr's standard library, as `bundle exec ruby` does. `BUNDLE_GEMFILE` does the same. zr reads the lock with its own bundler, not the host's. |
| `--allow-runtime-require` | yes | yes | Lets a literal `require` in the program's own files that zr cannot find wait for the run time. The binary then carries the compiler (such a binary is about 110 MB) to compile what it finds then. Without it, such a require stops the build; see [the require gate](#the-require-gate). |
| `--trace` | yes | yes | Builds the program with its trace events armed (`ZR_TRACE=1` does the same). zr arms them by itself when a file of the program names `TracePoint`, `set_trace_func` or `Coverage`, in code or in a string. A program that reaches TracePoint only by a name it computes (`Object.const_get(name)`) needs this flag; without it, its code fires no events, and zr warns when it enables a TracePoint. |
| `--print-gems` | no | yes | After the build, prints the gems that the output was built with, as `zr inspect` does. |
| `-h`, `--help` | yes | yes | Prints the help for the command. |

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
paths, built with the same root, write the same bytes. A main file given as a relative path keeps that path, as
in ruby. The program can read a file at a changed path only if that
path exists on the machine that runs the program.

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
ok    target             aarch64-apple-darwin   binary, obj; this host: binary, obj
warn  target             aarch64-linux-musl     binary, obj; this host: obj
ok    target             wasm32-wasi            wasm; this host: wasm
ok    wasmtime           /opt/homebrew/bin/wasmtime
ok    openssl            /opt/homebrew/opt/openssl@3/lib/libssl.3.dylib
ok    libraries          stdlib of ruby 4.0.7 (59 gems), 17 ports
ok    cache              ~/Library/Caches/zr, 2703 MB
```

A `target` line gives a target, the outputs that zr makes for it, and
after `this host:`, the outputs that this host can make now. The line
is `warn` when this host cannot make one of the outputs: for example, a
Linux binary needs a musl cross toolchain. See [Targets](targets.md).

`warn` means that zr can do less on this host: for example, with no
wasmtime, `zr run --emit wasm` does not work. Each `warn` and `fail`
line says what to do.

`fail` means that zr cannot build, and `zr doctor` then exits with
status 1. Put the output of `zr doctor` in a bug report.

## `zr cache [path|size|clean [--days N | --all]]`

zr keeps what it builds once in a cache: the runtime, eval support, the
prelinked images, machine code, parsed trees and the binaries of
`zr run`. The cache is some hundred MB for each zr version.

| Command | Effect |
|---|---|
| `zr cache` or `zr cache path` | Prints the cache directory. |
| `zr cache size` | Prints what the cache holds, by kind, and the compiled compilers that older zr versions kept. It also prints the size of wasmtime's own cache, if there is one. zr does not clean that cache. |
| `zr cache clean` | Deletes the entries that this zr does not use, the files of a zr from before the store, and the compiled compilers that older zr versions kept. The next build rebuilds nothing. |
| `zr cache clean --days N` | Does the same as `zr cache clean`, but keeps the entries used in the last N days. In a checkout, `--days 1` keeps the entries of a branch that you used today. |
| `zr cache clean --all` | Deletes every entry in the cache. The next build makes them again. |

The cache is one content store, `<cache>/store/`. Each entry is at
`<kind>/<first two characters of its key>/<key>`, where the key is a
SHA-256 digest of every input of the entry:

| Kind | Holds |
|---|---|
| `object` | the runtime object and the eval support object |
| `image` | the prelinked images and their skeletons |
| `meta` | symbol tables, gem prelude lists and eval support metadata |
| `code` | the machine code of each function, one directory for each backend |
| `lowering` | what the core and eval support need from each file that they did not lower again |
| `kernel` | the kernel's lowering, so an edit to the core or to `lib/zr/lower` does not lower the kernel again |
| `unit` | the machine code of each file of a program |
| `parse` | parsed trees |
| `gems` | the gems that `--gem` and a Gemfile.lock resolved |
| `wasm` | the prelude of a WASI module |
| `run` | the binaries of `zr run` (at most 2 GB) |
| `binary` | the binaries that the program tests keep (at most `ZR_TEST_BINARIES_GB`) |
| `result` | the host program tests that passed, with no data (`test/support/result_cache.rb`) |
| `source` | the digest of a compiler file without its comments, so a comment edit rebuilds nothing |

Each build names the entries that the next build needs, such as the
runtime object and the machine code of its backend, in a root
(`<cache>/store/roots/`). A clean keeps what a root names. A root that
no build wrote in 30 days protects nothing. When a kind is over its
limit, zr deletes its entries that were used longest ago.

An installed zr also cleans its cache after a build when the cache is
larger than `ZR_CACHE_MAX_GB` (5 GB by default). It deletes the entries
that were used longest ago and that no root names. If the cache is
still too large, it then deletes the compiled compilers that older zr
versions kept. It measures the cache at most once a day
(`Cache::Janitor.trim`, `lib/zr/cache/janitor.rb`).

## Messages

A usage error prints one line that tells what is wrong, and one line
that tells where to find help:

```
zr build: missing -o <path>
Run 'zr help build' for usage.
```

Other errors print one line that starts with `zr:`, for example
`zr: no such file: app.rb`, and no backtrace. A bad value of a `ZR_*`
variable names the variable and a value that works, and exits with
status 2:

```
zr: ZR_JOBS is "abc". Set it to a whole number of 1 or more, for example ZR_JOBS=4.
```

An error that zr did not expect is a defect in zr. Its line says so:

```
zr: internal error: NoMethodError: undefined method 'x' for nil. This is a defect in zr. Report it at https://github.com/ryanseys/zr/issues with the output of 'zr doctor'. Set ZR_DEBUG=1 to see the backtrace.
```

A refusal of a form of Ruby gives the file, the line and the column,
the form, the source line with a caret under the column, and the page
that lists what zr supports. It has this format:

```
zr: app.rb:2:1: zr does not support <the form> yet
    <the source line>
    ^
zr: https://github.com/ryanseys/zr/blob/v0.1.0/docs/reference/support.md lists what zr supports
```

The link names the docs of this zr version.

### The require gate

A literal `require` in the program's own files (the main file, and
each file that it reaches by `require_relative` or by a path) that zr
finds nowhere stops the build, with status 1:

```
zr: app.rb:2: cannot load such file -- rainbow. Give --gem rainbow=<dir> or a --gemfile that has it, put the require in `begin ... rescue LoadError`, or build with --allow-runtime-require
```

Without the gate, the require would wait for the run time, and the
binary would carry the compiler (such a binary is about 110 MB) to
compile what it finds then. A require inside `begin ... rescue LoadError` (or `ScriptError`,
or `Exception`) does not stop the build: the program handles the
LoadError, as in ruby. A bare `rescue` does not catch LoadError, so it
does not count. A require in a library's file, and a require of a
computed name, do not stop the build either.

When a backend cannot compile code that the front end accepted, the
message starts with `zr: zr cannot compile this program`, and says
that this is a limit or a defect in zr, not a problem in the program.
Please report it.

## Exit status

| Status | Meaning |
|---|---|
| 0 | Success. For `zr run`, the program's own status. |
| 1 | An error. A build step failed, or a require in the program's own files has no file; the message tells which. For `zr diff`, the two runs differ. |
| 2 | A usage error: the command line is wrong, or a `ZR_*` variable has a value that zr cannot use. |
| 3 | A refusal: zr does not support the program, or this host cannot build or run the target, or the ruby is not 4.0.7 or a later 4.0 release. The message gives the form and its line, or the missing tool. |
| 130 | Ctrl-C stopped zr. zr removes its temporary files first. |

A program that does not parse still builds, and `zr build` gives a
warning. Its binary prints ruby's syntax error report and exits with
status 1, as ruby does.

The environment variables that change `zr` are in
[Environment variables](environment-variables.md).
