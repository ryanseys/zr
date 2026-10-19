# The `zr` command

`zr` is the gem's command. In a checkout, it is `exe/zr`. This page
describes only `zr`. For the `bin/` scripts, the rake tasks and the
`zr-dev` commands of a checkout, see [Tools](tools.md).

```
Usage: zr <command> [options]
       zr [ruby switches] [--] [<file.rb> | -] [args...]

Commands:
  run <file.rb> [args...]     compile a program, run it, then delete the build
  build <file.rb> -o <out>    compile a program to a binary, a WASI module or
                              an object (`compile` is another name)
  gems [<file.rb>]            list the gems of a build and their sources
  inspect <binary>            print the gems that a binary was built with
  diff <file.rb> [args...]    run a program in ruby and as a zr binary; compare
  doctor                      check this host: ruby, targets, wasmtime,
                              OpenSSL, gems, cache
  cache [path|size|clean]     show or clean the build cache
  version                     print the version
  help [<command>]            print help for zr or for one command

Any other first word runs zr as a ruby, with ruby's switches: zr -e 'p 1'
-h prints this text; use --help for settings and more.
```

`zr -h` prints this short list, which fits a terminal of 80 columns
and 25 rows. `zr --help` and `zr help` print the long one: the
commands, ruby mode, each [setting](#settings) and the exit statuses,
in lines of at most 80 columns.

`zr help <command>` and `zr <command> --help` (or `-h`) print the
options of a command. `zr version` prints zr's version and the ruby
whose output it gives (`zr 0.1.0 (for ruby <version>)`, where `<version>` is the pinned ruby). `zr --version` and `zr -v` are the
same. A first word that names no command runs zr as a ruby: see
[`zr` as a ruby](#zr-as-a-ruby).

An option takes its value as the next word or after `=`: `--emit wasm`
and `--emit=wasm` are the same. For `build`, options can
come before or after `<file.rb>`. For `run`, options come before
`<file.rb>`, because every word after it goes to the program. Put `--`
before `<file.rb>` when the file name starts with `-`.

zr runs on ruby 4.0 or later. On a ruby of another series than the
pinned one (`.ruby-version`), it gives a warning. On a ruby older than
4.0, `run` and `build` stop with exit status 3,
and the message links [How to install zr](../how-to/install.md).

## Options

| Option | `run` | `build` | Effect |
|---|---|---|---|
| `-o`, `--output <path>` | no | required | Writes the output to `<path>`. |
| `--emit <kind>` | `binary` or `wasm` | `binary`, `obj` or `wasm` | The output kind. The default is `binary`. |
| `--target <triple>` | yes | yes | Builds for `<triple>`: `aarch64-apple-darwin`, `aarch64-linux-musl` or `wasm32-wasi`. `zr doctor` shows what this host can build. `--emit wasm` without `--target` means `wasm32-wasi`. |
| `--path-root <dir>` | yes | yes | Writes source paths in the output as `<dir>` plus the path below zr's root or the working directory. `<dir>` must be an absolute path. |
| `--link <arg>` | yes | yes | Gives `<arg>` to the system linker (`cc`) for a native binary, once for each argument: an object, an archive, `-framework <name>`, `-Wl,<flags>` such as `-Wl,-sectcreate,<segment>,<section>,<file>` or `-Wl,-exported_symbols_list,<file>`. With a link argument, zr links with `cc`, not with its own linker, so the host needs a C toolchain. With `--emit obj` or `--emit wasm` it is a usage error. `ZR_LINK_ARGS` gives the same arguments. |
| `--allow-runtime-require` | yes | yes | Lets a literal `require` in the program's own files that zr cannot find wait for the run time. The binary then carries the compiler, which makes it some times larger, to compile what it finds then. Without it, the build warns about such a require, and the require raises `LoadError` if it runs; see [the require gate](#the-require-gate). |
| `--trace` | yes | yes | Builds the program with its trace events armed (`ZR_TRACE=1` does the same). zr arms them by itself when the code of a file of the program names `TracePoint`, `set_trace_func` or `Coverage`. A program that reaches TracePoint only by a name in a string or a symbol (`Object.const_get("TracePoint")`), or in an eval's code, needs this flag; without it, its code fires no events, and zr warns when it enables a TracePoint. |
| `--print-gems` | no | yes | After the build, prints the gems that the output was built with, as `zr inspect` does. |
| `-h`, `--help` | yes | yes | Prints the help for the command. |

## Settings

Each `ZR_*` setting of the compiler also has a flag: `--jobs N` (or
`-j N`) for `ZR_JOBS`, `--no-tune` for `ZR_TUNE=0`, `--cache-dir DIR`
for `ZR_CACHE`, and so on. `zr help` lists them, and
[Environment variables](environment-variables.md#the-compiler) gives
each one with its variable. A flag comes before the command or right
after its name, and wins over the variable:

```
zr --jobs 2 build app.rb -o app
zr build --timing app.rb -o app
zr --no-run-cache -e 'p 1'
```

A switch takes `--name` for on and `--no-name` for off. A setting with
a value takes it as the next word or after `=`. A bad value stops zr
with exit status 2 and a line that names the flag:
`zr: --jobs is "x". Set it to a whole number of 1 or more, for example --jobs=4.`

## `zr` as a ruby

`zr` takes ruby's command line when its first word names no command.
A script that is not there stops as ruby stops for it
(`zr: No such file or directory -- name (LoadError)`, status 1). Only
a word one letter away from a command name (`zr biuld`) is a mistyped
command, unless it is a file, a path or a name that ends in `.rb`. With
no words, zr reads the program from standard input, unless standard
input is a terminal (then it prints the usage and exits with status 2).

```sh
zr app.rb a b                        # the same as `zr run app.rb a b`
zr -e 'p ARGV' -- -x y               # $0 and __FILE__ are "-e"
echo 'p 1' | zr                      # $0 and __FILE__ are "-"
zr -lane 'print $F.last' input.txt
zr -i.bak -pe '$_.upcase!' notes.txt
zr -Ilib -rapp -w script.rb
```

A command's name always wins: run a script named `build` as
`zr ./build` or `zr -- build`. zr reads the switches as ruby does,
in order, up to the script's name, `-` or `--`; a cluster such as
`-lane` is one switch per letter. It also reads the switches on the
script's first line when that line starts with `#!` and names ruby
(`#!/usr/bin/env ruby -w`), also for `zr run` and `zr build`.

| Switch | Effect |
|---|---|
| `-e code` | The program is each `-e` as a line. Every word after the switches goes to `ARGV`. |
| `-n`, `-p`, `-a`, `-l` | The `while gets` loop around the program (`-p` prints `$_`), `$F = $_.split`, and a chomped `$_` with `$\ = $/`. The program's `BEGIN` blocks run once, before the loop. |
| `-0[octal]`, `-F pattern` | `$/` and `$;`. |
| `-i[ext]` | `ARGF` edits each file in place, with a backup named `<file><ext>`, or none for `-i`. |
| `-s` | Each word of `ARGV` up to the first that does not start with `-` (or up to `--`) sets a global: `-x` sets `$x` to true, `-name=value` sets `$name` to "value". |
| `-I dir`, `-r library` | `$LOAD_PATH` starts with `dir`, and the program requires `library` before its first line. The build reads both. |
| `-w`, `-W[0\|1\|2]`, `-W:[no-]category`, `-v`, `--verbose`, `-d` | `$VERBOSE`, the `Warning` categories and `$DEBUG`. `-v` also prints zr's version (`zr version`). |
| `-E ext[:int]`, `-U`, `-K[esun]`, `--encoding`, `--external-encoding`, `--internal-encoding` | The default external and internal encodings. |
| `-x[dir]` | The program starts at the first line that starts with `#!` and names ruby. |
| `-C dir`, `-X dir` | zr changes to `dir` before it reads the script, and the program runs there. |
| `-S` | Searches `RUBYPATH`, then `PATH`, for the script. |
| `-c`, `--dump=syntax` | Prints the parser's warnings, then `Syntax OK`, or ruby's syntax error and status 1, and runs nothing. |
| `--dump=parsetree` | Prints prism's tree of the program, as ruby prints it, and runs nothing. |
| `-y`, `--yydebug`, `--dump=yydebug` | Parses the program and runs nothing. With prism, as in ruby, this prints nothing. |
| `--backtrace-limit=n` | Shows at most `n` lines of each backtrace. |
| `--enable`/`--disable` `gems`, `frozen-string-literal`, `all` | `--disable-gems` does not load rubygems as the program starts. `frozen-string-literal` is the default of every file without the magic comment. |
| `--jit`, `--yjit`, `--zjit`, `--parser=prism`, `--crash-report` | No effect: zr compiles the program ahead of time, with prism. |
| `--dump=insns`, `--parser=parse.y` | Exit status 3: zr compiles to machine code with prism, so it has no YARV instructions and no parse.y. |
| `-h`, `--dump=usage` | zr's short usage, as `zr -h` prints it. |
| `--help`, `--dump=help` | zr's long usage, as `zr --help` prints it. With `-h` too, as in ruby, the long one. |
| `--version`, `--dump=version` | zr's version. |

zr's own flags `--trace` and `--allow-runtime-require` can come
before the script. A switch that ruby
does not know stops zr as it stops ruby, with status 1:
`zr: invalid option -q  (-h will show valid options) (RuntimeError)`.

zr builds the program, runs it, and keeps the binary in the run cache,
as `zr run` does. The cache keys a program from `-e` or standard input
on its text and its switches, so the same command line runs the kept
binary at once.

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
source: `stdlib` (the pinned ruby's library in zr), `port` (a gem with a C
part that zr ports), `Gemfile.lock` or `installed`. zr finds the gems
as ruby does, from the environment: with `BUNDLE_GEMFILE` (which
`bundle exec` sets), the gems of that Gemfile's lock; else the newest
version of each gem that rubygems has installed on its path
(`GEM_HOME`, `GEM_PATH`). See
[How to use a library or a gem](../how-to/use-a-library-or-gem.md#installed-gems-and-gemfiles).
For a gem that replaces a port, the row also gives the versions whose
C zr implements. With `<file.rb>`, it prints only the gems that the
build of `<file.rb>` reads. `--target` works as for `zr build`, and
`--json` prints one JSON object for each gem.

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
exits with status 0 when the two runs are the same, 1 when they differ
(`output-diff`, `exception-diff`, `status-diff`, `crash`, `timeout`), 2
for a `build-error`, and 3 when zr refused the program.

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

An object address (`0x` and 8 to 16 hex digits) is `0xADDR` in both outputs.
ruby runs with the same environment, so it finds the same gems. With
`BUNDLE_GEMFILE`, it runs as `bundle exec ruby`. Where ruby has
other versions of its gems than zr, the two runs can differ for that
reason; `zr gems` shows zr's.

## `zr doctor`

Checks what zr needs on this host, and prints one line for each check:

```
ok    zr                 0.1.0  /Users/you/.gem/ruby/<ruby_version>/gems/zr-0.1.0
ok    ruby               <version>
ok    host               aarch64-apple-darwin
ok    target             aarch64-apple-darwin   binary, obj; this host: binary, obj
warn  target             aarch64-linux-musl     binary, obj; this host: obj
ok    target             wasm32-wasi            wasm; this host: wasm
ok    wasmtime           /opt/homebrew/bin/wasmtime
ok    openssl            /opt/homebrew/opt/openssl@3/lib/libssl.3.dylib
ok    libraries          stdlib of ruby <version> (73 gems), 18 ports
ok    C extensions       3 of 34 installed gems with one need nothing more of zr's C API: msgpack, nokogiri, websocket-driver
ok    cache              ~/Library/Caches/zr, 2703 MB
```

A `target` line gives a target, the outputs that zr makes for it, and
after `this host:`, the outputs that this host can make now. The line
is `warn` when this host cannot make one of the outputs: for example, a
Linux binary needs a musl cross toolchain. See [Targets](targets.md).

The `C extensions` line names the gems installed in this ruby whose
real C extension `--native-ext` can put in a binary now: zr's C API has
every function that their extensions call. The line is `warn` without
`cc`, which links an extension's objects and builds one from source,
or without `make`, which an `extconf.rb` with rules of its own needs.

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
| `zr cache size` | Prints what the cache holds, by kind. It also prints the size of wasmtime's own cache, if there is one. zr does not clean that cache. |
| `zr cache clean` | Deletes the entries that this zr does not use, and the binaries that a build server left. The next build rebuilds nothing. |
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
| `gems` | the gems that a Gemfile.lock or rubygems' path resolved |
| `wasm` | the prelude of a WASI module |
| `run` | the binaries of `zr run` (at most 2 GB) |
| `ext` | the C extensions that zr built from a gem's sources (`--native-ext`) |
| `binary` | the binaries that the program tests keep (at most `ZR_TEST_BINARIES_GB`) |
| `result` | the program tests that passed, with no data (`test/support/result_cache.rb`) |
| `built` | the test runs' mark of each whole runtime build, written last (`test/support/built.rb`) |
| `source` | the digest of a compiler file without its comments, so a comment edit rebuilds nothing |

Each build names the entries that the next build needs, such as the
runtime object and the machine code of its backend, in a root
(`<cache>/store/roots/`). A clean keeps what a root names. A root that
no build wrote in 30 days protects nothing. When a kind is over its
limit, zr deletes its entries that were used longest ago.

An installed zr also cleans its cache after a build when the cache is
larger than `ZR_CACHE_MAX_GB` (5 GB by default). It deletes the entries
that were used longest ago and that no root names. It measures the cache at most once a day
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
zr: internal error: NoMethodError: undefined method 'x' for nil. This is a defect in zr. Report it at https://github.com/ryanseys/zr/issues with the output of 'zr doctor'. Run zr --backtrace (or set ZR_DEBUG=1) to see the backtrace.
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
finds nowhere makes the build warn:

```
zr: warning: app.rb:2: cannot load such file -- rainbow; the require raises LoadError if it runs. To load it, install the rainbow gem (GEM_HOME, GEM_PATH) or name a Gemfile that has it (BUNDLE_GEMFILE), or build with --allow-runtime-require
```

For a require of a path, the message says `add the file`.

Without the gate, the require would wait for the run time, and the
binary would carry the compiler, which makes it some times larger,
to compile what it finds then. A require inside `begin ... rescue LoadError` (or `ScriptError`,
or `Exception`) does not make the build warn: the program handles the
LoadError, as in ruby. A bare `rescue` does not catch LoadError, so it
does not count. A require in a library's file, and a require of a
computed name, do not make the build warn either.

When a backend cannot compile code that the front end accepted, the
message starts with `zr: zr cannot compile this program`, and says
that this is a limit or a defect in zr, not a problem in the program.
Report it at https://github.com/ryanseys/zr/issues.

## Exit status

| Status | Meaning |
|---|---|
| 0 | Success. For `zr run`, the program's own status. |
| 1 | An error. A build step failed, or a require in the program's own files has no file; the message tells which. For `zr diff`, the two runs differ. In ruby mode (`zr app.rb`, `zr -e`), the statuses that ruby gives: 1 for a missing script or a switch that ruby rejects. |
| 2 | A usage error: the command line is wrong, the file that a command names does not exist, or a setting (a `ZR_*` variable or its flag) has a value that zr cannot use, or the cache is not yours alone (see `SECURITY.md`). For `zr diff`, the build failed. |
| 3 | A refusal: zr does not support the program, or this host cannot build or run the target, or the ruby is older than 4.0. The message gives the form and its line, or the missing tool. `zr diff` also exits 3 when zr refused the program. |
| 70 | A defect in zr: an error that zr did not expect. The message names zr's version, ruby's and the host's, and a crash log in `<cache>/crash/` with the backtrace; report it with that log. |
| 130 | Ctrl-C stopped zr. zr removes its temporary files first. |

A program that does not parse still builds, and `zr build` gives a
warning. Its binary prints ruby's syntax error report and exits with
status 1, as ruby does.

The environment variables that change `zr` are in
[Environment variables](environment-variables.md).
