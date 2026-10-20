# How to install zr

This guide shows you how to get the ruby that zr runs on, install zr,
and check the host. At the end, it lists the problems that an install
can have, and what to do for each.

zr runs on ruby 4.0 or later. It targets the latest Ruby 4 release:
its tests compare zr with the ruby that zr's `.ruby-version` names (the
pinned ruby). The gem has no dependencies, and the install compiles
nothing.

## 1. Get ruby

Use the latest Ruby 4 release. Each of these installs it next to the
ruby that you have. Replace `<version>` with the version that
`.ruby-version` names at zr's release tag:

| Tool | Commands |
|---|---|
| mise | `mise use -g ruby@<version>` |
| rbenv with ruby-build | `brew upgrade ruby-build` (or `git -C ~/.rbenv/plugins/ruby-build pull`), then `rbenv install <version>` and `rbenv global <version>` |
| ruby-install with chruby | `ruby-install ruby <version>`, then `chruby <version>` |
| Docker | `docker run -it ruby:<version> bash` |

In a checkout of zr, `$(cat .ruby-version)` gives the version, for
example `mise install ruby@$(cat .ruby-version)`.

Homebrew's `ruby` formula gives the newest ruby release, which can be of
another series than the pinned ruby. zr runs on it with a warning. A
version manager gives the exact version.

Check the version:

```console
$ ruby -v
ruby 4.x.y (...) +PRISM [arm64-darwin24]
```

## 2. Install zr

```console
$ gem install zr
```

The install downloads only zr: zr carries the pinned ruby's standard
library itself. On a ruby older than 4.0, rubygems stops the install
with a message that names the ruby version that zr needs:

```
ERROR:  Error installing zr:
	zr requires Ruby version >= 4.0. The current ruby version is 3.4.7.
```

Get ruby (step 1), then install zr again.

## 3. Check the host

```console
$ zr doctor
ok    zr                 0.1.0  /Users/you/.gem/ruby/<ruby_version>/gems/zr-0.1.0
ok    ruby               <version>
ok    host               aarch64-apple-darwin
ok    target             aarch64-apple-darwin   binary, obj; this host: binary, obj
warn  target             aarch64-linux-musl     binary, obj; this host: obj
ok    target             wasm32-wasi            wasm; this host: wasm
warn  wasmtime           not on PATH; needed only for 'zr run --emit wasm'. See https://wasmtime.dev
ok    openssl            /opt/homebrew/opt/openssl@3/lib/libssl.3.dylib
ok    libraries          stdlib of ruby <version> (73 gems), 18 ports
ok    C extensions       3 of 34 installed gems with one need nothing more of zr's C API: msgpack, nokogiri, websocket-driver
ok    cache              /Users/you/Library/Caches/zr, 0 MB
```

Each `warn` line says what zr cannot do here, and what to do. Only a
`fail` line stops a build.

## 4. Optional tools

- **wasmtime** runs a WebAssembly module (`zr run --emit wasm`):
  `brew install wasmtime`, or
  `curl https://wasmtime.dev/install.sh -sSf | bash`.
- **OpenSSL 3** is needed only by a macOS program that requires
  `openssl`: `brew install openssl@3`. For another location, set
  `OPENSSL_DIR` to its prefix.
- **A C compiler** is needed only for a Linux binary, and for `--link`.
  On macOS, `xcode-select --install`. On Alpine, `apk add build-base`.
  On Debian or Ubuntu, `apt install build-essential` (and `musl-tools`
  for a static musl binary).

## 5. Build a program

```console
$ echo 'puts "Hello from #{RUBY_PLATFORM}"' > hello.rb
$ zr run hello.rb
zr: building the zr runtime for aarch64-apple-darwin. This occurs one time and takes some minutes.
zr: to download it in place of the build, stop zr (Ctrl-C) and run 'zr cache fetch --target aarch64-apple-darwin'.
Hello from arm64-darwin23
```

The first build fills zr's cache. The builds after it take seconds. On
macOS (Apple silicon) and on aarch64 and x86_64 Linux (glibc or musl),
`gem install zr` takes the platform gem of your host, which carries its
runtime: the first build takes seconds too, and prints neither line. A
Gemfile.lock that lists only the `ruby` platform keeps the `ruby` gem;
`bundle lock --add-platform arm64-darwin` (or your host's platform)
adds it. `gem install zr --platform ruby` takes the `ruby` gem on
purpose.

With the `ruby` gem, to skip the first build, run `zr cache fetch`
before it: it downloads the
runtime that this zr release built for your target, checks its SHA-256,
and puts it in the cache. Add `--target T` for another target. zr
downloads nothing unless you run it.
`zr cache size` shows the cache, and `zr cache clean --all` frees all of
it.

Next: [Compile your first program](../tutorials/compile-your-first-program.md).

## Troubleshooting

### `zr: zr 0.1.0 runs on ruby 4.0 or later. Install ruby <version>: …/how-to/install.md`

The `ruby` on your `PATH` is older than 4.0. `ruby -v` shows it, and
`which zr` shows the ruby that the `zr` command belongs to. Select
the latest Ruby 4 release with your version manager (step 1), and
install zr for it. zr exits with status 3. `zr doctor` gives a `fail`
line for `ruby`: `<v>; zr needs ruby 4.0 or later. See …`.

### `zr: warning: zr 0.1.0 is tested with ruby <version>; this is ruby <v>`

zr runs on this ruby, but its tests use the pinned ruby, of another
series. `zr doctor` gives a `warn` line for `ruby`:
`<v>; zr is tested with <version>`. A compiled program is the same: it
uses zr's own standard library, not the host's. To remove the warning,
use a ruby of the pinned ruby's series (step 1).

### A `fail` line in `zr doctor` for `libraries`

A file of zr's standard library is missing, so the install is damaged.
Run `gem install zr` again. The line names the missing directory:
`<dir> is missing; reinstall zr (gem install zr)`.

### `Permission denied` or `No space left on device` under the cache

zr keeps its cache in `~/Library/Caches/zr` on macOS and `~/.cache/zr`
on other hosts. Set `XDG_CACHE_HOME` (or `ZR_CACHE`) to a directory
that you can write to, or run `zr cache clean` to free space.

### `HOME is not set, so zr has no cache directory`

Set `HOME`, or set `ZR_CACHE` to a directory that you can write to. This
occurs in some containers and CI jobs.

### `Gem::LoadError` or `Bundler` errors under `bundle exec`

zr needs no bundle. Run `zr` directly. To build a program with the gems
of a Gemfile, set `BUNDLE_GEMFILE=Gemfile` for the `zr` command; see
[How to use a library or a gem](use-a-library-or-gem.md). If `RUBYOPT`
has `-rbundler/setup`, remove it for the `zr` command.

### `this computer cannot run aarch64-apple-darwin binaries`

zr builds native binaries for an Apple Silicon Mac and for aarch64
and x86_64 Linux. On another host (an Intel Mac), build a WebAssembly
module and run it with wasmtime:

```console
$ zr run --emit wasm hello.rb
```

`zr build` without `--target` still writes a macOS binary, which you
can copy to an Apple Silicon Mac.

### `a native binary needs cc on the PATH`

Only a Linux binary, and a build with `--link`, need a C compiler. Install one as `zr doctor` says (step 4), or build with
`--emit wasm`.

### `zr: internal error: ...`

This is a defect in zr. Report it at
<https://github.com/ryanseys/zr/issues> with the output of `zr doctor`.
Run the command again with `zr --backtrace` (or `ZR_DEBUG=1`) to get the backtrace for the
report.
