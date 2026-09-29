# How to release zr

A release publishes the platform-independent gem, `zr-<version>.gem`,
to rubygems.org and to gem.coop, and makes a GitHub Release with the
gem and the version's changelog. A tag starts it: the release workflow
(`.github/workflows/release.yml`) does the rest.

This page also records the design of the platform gems. They are a
spike: `zr-dev gem native` builds one and tests it, but no release
publishes one yet.

## Set up once

Do these by hand before the first release:

1. On rubygems.org, add a trusted publisher for the gem `zr`: this
   repository, the workflow `release.yml` and the environment `release`.
   The workflow then needs no API key.
2. On gem.coop, claim the namespace `@ryanseys`, and make a push-only
   API key for it.
3. In the repository settings, make the environment `release`, and add
   the gem.coop key to it as the secret `GEM_COOP_API_KEY`. Limit the
   environment to tags `v*`.
4. Make sure that CI can run: the macOS runners need a public
   repository or an Actions spending limit.

## Release a version

1. Change `VERSION` in `lib/zr/version.rb`.
2. In `CHANGELOG.md`, change `## [Unreleased]` to
   `## [X.Y.Z] - YYYY-MM-DD`, and add a new empty `[Unreleased]`
   section above it.
3. Commit, and push to `main`. Wait until every CI job passes.
4. Tag the commit, and push the tag:

   ```console
   $ git tag vX.Y.Z
   $ git push origin vX.Y.Z
   ```

The workflow then:

1. stops unless the tag is `v` and `Zr::VERSION`, and `CHANGELOG.md`
   has a dated section for the version (`tool/changelog.rb`), which
   becomes the release notes;
2. stops unless every job of `ci.yml` passed for the tagged commit
   (`.github/scripts/ci_passed.rb`);
3. runs the unit tier, builds the gem, installs it in a clean
   `GEM_HOME` and runs it as a user would (`.github/scripts/smoke.rb`);
4. attests the gem's provenance, pushes it to rubygems.org with trusted
   publishing (rubygems attests the push too), and to
   `https://gem.coop/@ryanseys`;
5. makes the GitHub Release, with the gem attached.

## Check a release without publishing

Run the workflow by hand (Actions, then Release, then "Run workflow")
with the tag, and `publish` off. It runs every check and publishes
nothing. With `publish` on and `only: gem-coop`, it pushes an already
published version to gem.coop again, for example after a gem.coop
failure.

## What the gem contains

The gem contains the compiler, the runtime, the vendored sources and
the license texts. On the first build, an installed gem on an Apple
Silicon Mac compiles the compiler with itself into the user's cache
(`lib/zr/compiled_compiler.rb`), and tells the user.

## Platform gems (spike)

A platform gem is the ruby gem plus the compiled compiler for one
platform, in `exe/<platform>/zr`, with a manifest beside it. RubyGems
installs the platform gem in place of the ruby gem on a host of that
platform. Then the first build needs no self-build.

### Build and test one

```sh
bundle exec rake build:self                        # bin/zr, for this host
ruby tool/zr-dev.rb gem native                      # pkg/zr-<version>-arm64-darwin.gem
ruby tool/zr-dev.rb gem native --install /tmp/zr    # ... installed, and a program built with it
```

`--install` fails if the installed zr did not build the program with its
shipped binary.

### How the installed gem finds the binary

`CompiledCompiler.binary` looks in this order: `ZR_BINARY`, then `bin/zr`
in a checkout, then the shipped binary (`Zr::Shipped`), then the user's
cache.

The file stamps of an installed gem say nothing about the build, so the
manifest gives a content digest (`lib/zr/shipped.rb`):

```
version 0.1.0
ruby 4.0.7
platform arm64-darwin
digest <SHA-256>
```

The digest covers each source file that the gem contains (`exe/zr`,
`lib/`, `runtime/`, `vendor/`), by its path below the gem's root and its
bytes, and the digests of the pinned libraries. The same gem gives the
same digest wherever it is installed. The first build reads every source
to check the digest, then keeps the file stamps in the user's cache.
Later builds compare only the stamps. zr never builds over a shipped
binary; if the check fails, ruby runs the build.

### Measurements (arm64-darwin, M2 Pro, 12 cores)

| What | Result |
|---|---|
| The binary | 116 MB |
| The platform gem | 24.5 MB |
| The first digest check | 0.18 s |
| A later check (stamps only) | 0.02 s |
| A small program, empty runtime cache, shipped binary | 57 s |
| The same, ruby | 26 s |
| The same program, warm cache, shipped binary | 0.65 s |
| The same, ruby | 0.77 s |

The committed compile baseline (`benchmark/results/compile/`) gives the
warm-build ratio of the compiled compiler to ruby: 0.56 for a small
program, 0.73 for a program that requires rubygems, and 1.02 for bundler.

The shipped binary is slower than ruby when it builds the runtime: 57 s
against 26 s. A worker of the compiled compiler uses more memory, so
`Native::Parallel.afforded` gives it fewer workers. A platform gem thus
helps warm builds a little, and does not help the first build. Shipping
the runtime objects (next section) would help the first build more.

### The runtime objects

The runtime objects cannot ship today. `Runtime#digest_of`
(`lib/zr/runtime.rb`) hashes the absolute path of each source, so the
cache key of an installed gem depends on where it is installed. To ship
them, the digest must hash each path below a fixed root, as `--path-root`
does (`Paths.shown`). Then the backtraces into the core library show that
root (for example `/zr/runtime/...`) in place of the real path. This is
a decision for later.

The sizes, if a gem ships them:

| File | Size | Compressed |
|---|---|---|
| The runtime object (`runtime-*.o`) | 28.8 MB | 5.8 MB |
| Its symbol table (`symbols-*.json`) | 0.3 MB | 0.1 MB |
| The eval support object (`eval-*.o`) | 89.2 MB | 15.0 MB |
| The prelinked runtime (`prelink-*.bin`) | 29.7 MB | 6.2 MB |

A gem ships the runtime object and its symbols at most. The prelinked
image and the skeletons are made again in the user's cache.

### The release matrix

| Gem | Contains | Status |
|---|---|---|
| `zr-<version>.gem` (platform-independent) | The sources. The first build compiles the compiler. | Released. |
| `zr-<version>-arm64-darwin.gem` | The sources and the compiled compiler for macOS. | Spike: `zr-dev gem native` builds and tests it. |
| `zr-<version>-aarch64-linux-gnu.gem`, `zr-<version>-aarch64-linux-musl.gem` | The sources and one static Linux binary. The same binary is in both gems. | Not started. It needs a compiled compiler for `aarch64-linux`, built on a Linux host. |

Every gem keeps `required_ruby_version ">= 4.0.7", "< 4.1"`. A platform
gem still needs a host ruby, which runs `exe/zr`.

Before a release publishes platform gems, decide:

- whether a gem ships the runtime objects, and thus the path root of the
  backtraces;
- how CI builds each platform's binary, and checks it with `zr-dev stage 2`
  before it packs it.
