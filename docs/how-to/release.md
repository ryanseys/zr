# How to release zr

A release publishes the platform-independent gem, `zr-<version>.gem`,
to rubygems.org and to gem.coop, and makes a GitHub Release with the
gem and the version's changelog. A tag starts it: the release workflow
(`.github/workflows/release.yml`) does the rest. `rake release` does
not release: it stops and points here, because a gem that no CI run
checked must not go out.

This page also records the design of the platform gems. No release
publishes one yet; see [Platform gems](#platform-gems-not-released).

## Set up once

Do these by hand before the first release:

1. Make the repository public. The homepage, the docs links in the
   gem and in zr's messages, and the free macOS runners need it.
2. On rubygems.org, add a **pending** trusted publisher (Profile, then
   "Trusted publishers", then "Create pending publisher"), because the
   gem `zr` does not exist yet: the gem name `zr`, this repository, the
   workflow `release.yml` and the environment `release`. The first
   push makes it a normal trusted publisher. The workflow then needs no
   API key.
3. On gem.coop, claim the namespace `@ryanseys`, and make a push-only
   API key for it.
4. In the repository settings, make the environment `release`, and add
   the gem.coop key to it as the secret `GEM_COOP_API_KEY`. Limit the
   environment to tags `v*`.

## Check before a release

- [ ] The last `ci.yml` run on `main` passed every job, also the
  stock-ruby jobs (`stock ruby, user cache`). The release workflow
  checks this again for the tagged commit (`.github/scripts/ci_passed.rb`).
- [ ] `bin/test test/unit` passes locally.
- [ ] `gem build zr.gemspec` makes a gem, and `gem spec zr-*.gem
  dependencies` lists none.
- [ ] `ruby .github/scripts/smoke.rb --user-cache zr-*.gem DIR` passes
  in a fresh directory, on a ruby with no Gemfile.
- [ ] The CHANGELOG section describes what a user sees.

## Release a version

1. Change `VERSION` in `lib/zr/version.rb`. Run `bundle install`, and
   commit `Gemfile.lock` with it: the lock records zr's own version.
   For the first release, `VERSION` is already 0.1.0.
2. In `CHANGELOG.md`, change `## [Unreleased]` to
   `## [X.Y.Z] - YYYY-MM-DD`, and add a new empty `## [Unreleased]`
   section above it. Keep the "Planned" part under `[Unreleased]`:
   the version's section becomes the release notes. At the end of the
   file, make the link references:

   ```
   [Unreleased]: https://github.com/ryanseys/zr/compare/vX.Y.Z...HEAD
   [X.Y.Z]: https://github.com/ryanseys/zr/releases/tag/vX.Y.Z
   ```

   `ruby tool/changelog.rb X.Y.Z` prints the notes; it fails when the
   section is missing, has no date, or is empty.
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
   `GEM_HOME` and runs it as a user would, with a fixed cache and
   again with the user cache (`.github/scripts/smoke.rb`);
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

## Release by hand

Only when the workflow cannot run, for example when GitHub Actions is
down. Build the gem from the tagged commit, as CI does, and push it
with a one-time password:

```console
$ git checkout vX.Y.Z
$ SOURCE_DATE_EPOCH="$(git log -1 --format=%ct)" gem build zr.gemspec
$ ruby .github/scripts/smoke.rb --user-cache zr-X.Y.Z.gem "$(mktemp -d)"
$ gem push zr-X.Y.Z.gem --otp 123456
$ gh release create vX.Y.Z zr-X.Y.Z.gem --title "zr X.Y.Z" --notes "$(ruby tool/changelog.rb X.Y.Z)" --verify-tag
```

A gem pushed by hand has no provenance attestation.

## After a release

On a machine with a stock ruby 4.0.7 and no Gemfile:

```console
$ gem install zr -v X.Y.Z
$ zr version
zr X.Y.Z (for ruby 4.0.7)
$ zr doctor
$ echo 'puts "hello"' > hello.rb && zr run hello.rb
```

Then look at <https://rubygems.org/gems/zr>, at the gem.coop page
of `@ryanseys/zr`, and at the GitHub Release: each shows the version,
and the Release has the gem and the notes.

## A bad release

A published version cannot change. If a release is broken:

1. `gem yank zr -v X.Y.Z` removes it from new installs. A lock that
   names it still fails, so yank only a version that does harm (it does
   not install, or it builds wrong programs).
2. Fix the problem, and release X.Y.Z+1 as above. Its CHANGELOG
   section says what was wrong with X.Y.Z.

## What the gem contains

The gem contains the compiler, the runtime, the vendored sources and
the license texts. On the first build, an installed gem on an Apple
Silicon Mac compiles the compiler with itself into the user's cache
(`lib/zr/bootstrap/handoff.rb`), and tells the user.

## Platform gems (not released)

A platform gem is the ruby gem plus the compiled compiler for one
platform, in `exe/<platform>/zr`, with a manifest beside it. RubyGems
installs the platform gem in place of the ruby gem on a host of that
platform. Then the first build needs no self-build.

### Build and test one

```sh
bundle exec rake build:self                                # bin/zr, for this host
ruby tool/zr-dev.rb gem native --local                      # pkg/zr-<version>-arm64-darwin.gem
ruby tool/zr-dev.rb gem native --local --install /tmp/zr    # ... installed, and a program built with it
```

`--install` fails if the installed zr did not build the program with its
shipped binary. `zr-dev gem native` refuses a manifest whose ruby is not
`Zr::RUBY`, and a binary that holds this checkout's path: `Paths::ROOT`
comes from `__dir__`, so `bin/zr` holds the path of the machine that
built it. `--local` packs it anyway, for a test on that machine only.
Such a gem must never be published. A gem to publish needs a compiled
compiler that finds its files from where it is installed.

### How the installed gem finds the binary

`Bootstrap::Handoff.binary` looks in this order: `ZR_BINARY`, then `bin/zr`
in a checkout, then the shipped binary (`Zr::Bootstrap::Prebuilt`), then the user's
cache.

The file stamps of an installed gem say nothing about the build, so the
manifest gives a content digest (`lib/zr/bootstrap/prebuilt.rb`):

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
| `zr-<version>-arm64-darwin.gem` | The sources and the compiled compiler for macOS. | Not released: `zr-dev gem native --local` builds and tests one on this machine. |
| `zr-<version>-aarch64-linux-gnu.gem`, `zr-<version>-aarch64-linux-musl.gem` | The sources and one static Linux binary. The same binary is in both gems. | Not started. It needs a compiled compiler for `aarch64-linux`, built on a Linux host. |

Every gem keeps `required_ruby_version ">= 4.0.7", "< 4.1"`. A platform
gem still needs a host ruby, which runs `exe/zr`.

Before a release publishes platform gems, decide:

- whether a gem ships the runtime objects, and thus the path root of the
  backtraces;
- how CI builds each platform's binary, and checks it with `zr-dev stage 2`
  before it packs it.
