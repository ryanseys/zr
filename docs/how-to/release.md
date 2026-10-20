# How to release zr

A release publishes zr's gems to rubygems.org and to gem.coop, and
makes a GitHub Release with the gems, each target's prebuilt runtime
(`zr cache fetch` downloads it) and the version's changelog. The gems
are one name in several variants, as nokogiri ships:

- `zr-<version>.gem`, the `ruby` gem: the compiler with no runtime. It
  builds the runtime on its first use, or `zr cache fetch` takes it.
- `zr-<version>-<platform>.gem` for each host whose lane passed:
  `arm64-darwin`, `x86_64-linux-gnu`, `aarch64-linux-gnu`,
  `x86_64-linux-musl` and `aarch64-linux-musl` (`Target#gem_platform`).
  It carries that host's runtime unpacked at `data/runtime/<triple>`, so
  its first build builds none. RubyGems and Bundler take it in place of
  the `ruby` gem on that host (RubyGems 3.3.22 and later; Bundler 2.5.6
  for the gnu and musl names). A host with no platform gem takes the
  `ruby` gem.

wasm32-wasi is a target, not a host, so it has no platform gem: its
runtime is only a release file. That bundle also holds each runtime as
a standard module (`modules/zr-runtime-<key>.wasm`), which wasmtime
preloads for a program module that `zr build --wasm-split` writes. A tag starts it: the release workflow
(`.github/workflows/release.yml`) does the rest. `rake release` does
not release: it stops and points here, because a gem that no CI run
checked must not go out.

## Prereleases

Each CI run on `main` makes a GitHub prerelease of the commit that it
tested: the last job of CI, "release: prerelease of this commit"
(`.github/workflows/ci.yml`, `release`). It does not wait for `ci-ok`.
Each target's lane has a tier (`.github/scripts/lanes.rb`):

| Tier | Targets | When its lane does not pass |
|---|---|---|
| 1 | aarch64-apple-darwin, x86_64-linux-gnu | no prerelease |
| 2 | aarch64-linux-gnu, aarch64-linux-musl, x86_64-linux-musl | its bundle is left out |
| 3 | wasm32-wasi | its bundle is left out |

A failed `checks`, `units` or gem smoke test also stops it. A lane
passed when its test job uploaded the `passed-<triple>` marker. The
job summary and the release notes name each target that was left out.
`ci-ok` stays red for any failure, so `main` still shows it. Its tag is the
version in `lib/zr/version.rb`, then `.g` and the first 7 characters of
the commit's SHA: `v0.1.0.geebf308`. It holds the files that the run
tested, with no build of its own:

- the gem of the `checks` job, `zr-<version>.gem`;
- the runtime bundle of each target whose lane passed,
  `zr-runtime-<version>-<triple>.tar.gz`, by the name that `zr cache fetch`
  reads;
- their `SHA256SUMS`, and an attestation of each (`gh attestation verify`).

The gem's version is the release's, so a bundle of the run imports into
it. To take a prerelease's runtimes:

    gem install ./zr-0.1.0.gem
    ZR_PREBUILT_URL=https://github.com/ryanseys/zr/releases/download/v0.1.0.geebf308 zr cache fetch

A prerelease goes to no gem server. A second CI run of the same commit
makes no second prerelease. The release workflow does not start on a
prerelease's tag.

## Set up once

Do these by hand before the first release:

1. Make the repository public. The homepage, the docs links in the
   gem and in zr's messages, and the free macOS runners need it. The
   README's links and the links that zr prints name the `vX.Y.Z` tag,
   so they work only after the first release: release on the day the
   repository goes public.
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
5. Add a ruleset for the tags `v*`, with `v*.g*` excluded (the
   prereleases' tags, which CI makes): no deletion, no update
   and no force push, and only admins create one. Add a ruleset for `main`: no
   deletion and no force push, and the status check `ci-ok` is
   required (an admin can bypass it to push directly).
6. Turn on private vulnerability reporting (Security), which
   `SECURITY.md` names, and Dependabot alerts, secret scanning and push
   protection.

## Check before a release

- [ ] The last `ci.yml` run on `main` made the commit's prerelease, and
  the prerelease names no target that was left out that you want in
  the release. The nightly run also runs every program; a push
  runs each target's units and a slice of its programs. The release
  workflow checks this again for the tagged commit
  (`.github/scripts/ci_passed.rb`).
- [ ] `bin/minitest test/unit` passes locally.
- [ ] `gem build zr.gemspec` makes a gem, and `gem spec zr-*.gem
  dependencies` lists none.
- [ ] `ruby .github/scripts/smoke.rb --user-cache zr-*.gem DIR` passes
  in a fresh directory, on a ruby with no Gemfile.
- [ ] The CHANGELOG section describes what a user sees.

## Release a version

1. Run `bin/zr-dev bump X.Y.Z` (`--dry-run` first to see the files).
   It sets `VERSION` in `lib/zr/version.rb` and `zr (X.Y.Z)` in
   `Gemfile.lock`, points the README's links at the `vX.Y.Z` tag, dates
   the `[Unreleased]` section of `CHANGELOG.md` as X.Y.Z with a new
   empty one above it, and writes the link references. For the first
   release, `VERSION` is already 0.1.0, and only the changelog changes.
   `bin/zr-dev changelog X.Y.Z` prints the notes.
2. Read the diff. A plan for later versions goes in
   `docs/explanation/roadmap.md`, not in the notes.
3. Commit, and push to `main`. Wait until the run passes `ci-ok` and
   makes the commit's prerelease. To run every program on the commit
   first, run CI by hand (`gh workflow run ci.yml --ref main`).
4. Tag the commit, and push the tag:

   ```console
   $ git tag vX.Y.Z
   $ git push origin vX.Y.Z
   ```

The workflow then:

1. stops unless the tag is `v` and `Zr::VERSION`, and `CHANGELOG.md`
   has a dated section for the version, which becomes the release
   notes (`.github/scripts/release_notes.rb`);
2. stops unless a CI run of the tagged commit (a push, the nightly run
   or a run by hand) has a release job that passed, which needs every
   tier 1 lane (`.github/scripts/ci_passed.rb`), and the commit's
   prerelease is there. The release runs no test tier itself. Its
   files are the prerelease's, checked against its `SHA256SUMS`. If
   the prerelease is gone, run CI on the tag again
   (`gh workflow run ci.yml --ref vX.Y.Z`): a run on a tag makes it;
3. builds the `ruby` gem, and stops unless its SHA-256 is the one of
   the prerelease's;
4. installs the gem in a clean `GEM_HOME` and runs it as a user would,
   with a fixed cache and again with the user cache
   (`.github/scripts/smoke.rb`);
5. on a runner of each target in the prerelease: installs its platform
   gem in an empty `GEM_HOME`, which must build a program and an eval
   with an empty cache and no runtime build (for wasm32-wasi, imports
   the bundle with the `ruby` gem). A target that the prerelease left
   out is left out of the release;
6. in the `release` environment: attests the provenance of each gem
   and bundle, makes the GitHub Release as a draft with them and their
   `SHA256SUMS`, pushes each platform gem and then the `ruby` gem to
   rubygems.org with trusted publishing (rubygems attests the push too;
   check the attestation on rubygems.org after the first release) and
   to `https://gem.coop/@ryanseys`, and then publishes the draft. The
   `ruby` gem goes last: a host that resolves zr between the pushes
   finds its platform gem.

A platform that a version left out comes back only as a gem built from
the same tag: a gem of a version cannot be pushed again, and a fix
that changes code is the next version.

## Check a release without publishing

Run the workflow by hand (Actions, then Release, then "Run workflow")
with the tag, and `publish` off. It runs every check and publishes
nothing, from any ref. To publish by hand, choose the tag in "Use
workflow from": the `release` environment takes only a `v*` tag.

When a publish step fails, the draft GitHub Release stays. Run the
workflow from the tag with `publish` on and `only` set to the step that
failed: `rubygems`, `gem-coop`, or `github-release` (which makes the
draft if there is none, and publishes it).

## Release by hand

Only when the workflow cannot run, for example when GitHub Actions is
down. Build the gem from the tagged commit, as CI does, and push it
with a one-time password:

```console
$ git checkout vX.Y.Z
$ SOURCE_DATE_EPOCH="$(git log -1 --format=%ct)" gem build zr.gemspec
$ ruby .github/scripts/smoke.rb --user-cache zr-X.Y.Z.gem "$(mktemp -d)"
$ gem push zr-X.Y.Z.gem --otp 123456
$ gh release create vX.Y.Z zr-X.Y.Z.gem --title "zr X.Y.Z" --notes "$(bin/zr-dev changelog X.Y.Z)" --verify-tag
```

A gem pushed by hand has no provenance attestation.

## After a release

On a machine with a stock ruby of the version in `.ruby-version` and no
Gemfile:

```console
$ gem install zr -v X.Y.Z
$ zr version
zr X.Y.Z (for ruby <version>)
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

The gem contains the compiler, the runtime, the vendored library
(`vendor/ruby`), ruby's headers and `rbconfig.rb` for each target that
builds C extensions (`vendor/targets`), and the license texts. It contains no binary: a release ships the
platform-independent gem only. The host ruby runs zr (`exe/zr`). On
the first build, an installed gem builds the runtime into the user's
cache, and tells the user (`lib/zr/runtime.rb`).
