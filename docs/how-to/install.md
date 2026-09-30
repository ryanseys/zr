# How to install zr

This guide shows you how to get the ruby that zr runs on, install zr,
and check the host. At the end, it lists the problems that an install
can have, and what to do for each.

zr runs on ruby 4.0.7, or on a later 4.0 release. The gem has no
dependencies, and the install compiles nothing.

## 1. Get ruby 4.0.7

Use one of these. Each installs ruby 4.0.7 next to the ruby that you
have:

| Tool | Commands |
|---|---|
| mise | `mise use -g ruby@4.0.7` |
| rbenv with ruby-build | `brew upgrade ruby-build` (or `git -C ~/.rbenv/plugins/ruby-build pull`), then `rbenv install 4.0.7` and `rbenv global 4.0.7` |
| ruby-install with chruby | `ruby-install ruby 4.0.7`, then `chruby 4.0.7` |
| Docker | `docker run -it ruby:4.0.7 bash` |

Homebrew's `ruby` formula gives the newest ruby release, which can be a
version that zr does not run on. A version manager gives the exact
version.

Check the version:

```console
$ ruby -v
ruby 4.0.7 (2026-09-15 revision 229531a6cf) +PRISM [arm64-darwin24]
```

## 2. Install zr

```console
$ gem install zr
```

The install downloads only zr: zr carries ruby 4.0.7's standard
library itself. On another ruby, rubygems stops the install with a
message that names the ruby version that zr needs:

```
ERROR:  Error installing zr:
	zr requires Ruby version >= 4.0.7, < 4.1. The current ruby version is 3.4.7.
```

Get ruby 4.0.7 (step 1), then install zr again.

## 3. Check the host

```console
$ zr doctor
ok    zr                 0.1.0  /Users/you/.gem/ruby/4.0.0/gems/zr-0.1.0
ok    ruby               4.0.7
ok    host               aarch64-apple-darwin
warn  wasmtime           not on PATH; needed only for 'zr run --emit wasm'. See https://wasmtime.dev
ok    openssl            /opt/homebrew/opt/openssl@3/lib/libssl.3.dylib
ok    libraries          stdlib of ruby 4.0.7 (59 gems), 17 ports
ok    cache              /Users/you/Library/Caches/zr, 0 MB
ok    fast compiler      not built yet; the first build makes it
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
- **A C compiler** is needed only for an `aarch64-linux-musl` binary,
  and for `--link`. On macOS, `xcode-select --install`. On Alpine,
  `apk add build-base`. On Debian or Ubuntu, `apt install musl-tools`.

## 5. Build a program

```console
$ echo 'puts "Hello from #{RUBY_PLATFORM}"' > hello.rb
$ zr run hello.rb
zr: building the zr runtime for aarch64-apple-darwin. This occurs one time and takes some minutes.
zr: zr is compiling itself to make later builds faster. This occurs one time for each zr version and takes some minutes. You can stop it with Ctrl-C. ZR_COMPILED=0 turns it off.
Hello from arm64-darwin23
```

The first build fills zr's cache. The builds after it take seconds.
`zr cache size` shows the cache, and `zr cache clean --all` frees all of
it.

Next: [Compile your first program](../tutorials/compile-your-first-program.md).

## Troubleshooting

### `zr: zr 0.1.0 runs on ruby 4.0.7 or a later 4.0 release.`

The `ruby` on your `PATH` is another version. `ruby -v` shows it, and
`which zr` shows the ruby that the `zr` command belongs to. Select
ruby 4.0.7 with your version manager (step 1), and install zr for it.
zr exits with status 3.

### `zr: warning: zr 0.1.0 is tested with ruby 4.0.7; this is ruby 4.0.9`

zr runs on a later 4.0 release, but its tests use 4.0.7. A compiled
program is the same: it uses zr's own standard library, not the host's.

### A `fail` line in `zr doctor` for `libraries`

A file of zr's standard library is missing, so the install is damaged.
Run `gem install zr` again. A build then says:
`zr: zr's install is damaged: ... Reinstall zr with 'gem install zr -v 0.1.0'`.

### `Permission denied` or `No space left on device` under the cache

zr keeps its cache in `~/Library/Caches/zr` on macOS and `~/.cache/zr`
on other hosts. Set `XDG_CACHE_HOME` (or `ZR_CACHE`) to a directory
that you can write to, or run `zr cache clean` to free space.

### `HOME is not set, so zr has no cache directory`

Set `HOME`, or set `ZR_CACHE` to a directory that you can write to. This
occurs in some containers and CI jobs.

### `Gem::LoadError` or `Bundler` errors under `bundle exec`

zr needs no bundle. Run `zr` directly. To build a program with the gems
of a Gemfile, give `--gemfile Gemfile`; see
[How to use a library or a gem](use-a-library-or-gem.md). If `RUBYOPT`
has `-rbundler/setup`, remove it for the `zr` command.

### `this computer cannot run aarch64-apple-darwin binaries`

zr builds native binaries for an Apple Silicon Mac and for aarch64
Linux. On another host (x86_64 Linux, an Intel Mac), build a
WebAssembly module and run it with wasmtime:

```console
$ zr run --emit wasm hello.rb
```

`zr build` without `--target` still writes a macOS binary, which you
can copy to an Apple Silicon Mac.

### `a native binary needs cc on the PATH`

Only an `aarch64-linux-musl` binary, and a build with `--link`, need a C
compiler. Install one as `zr doctor` says (step 4), or build with
`--emit wasm`.

### `zr: internal error: ...`

This is a defect in zr. Report it at
<https://github.com/ryanseys/zr/issues> with the output of `zr doctor`.
Run the command again with `ZR_DEBUG=1` to get the backtrace for the
report.
