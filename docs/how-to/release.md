# How to release zr

A release publishes the platform-independent gem, `zr-<version>.gem`,
to rubygems.org and to gem.coop, and makes a GitHub Release with the
gem and the version's changelog. A tag starts it: the release workflow
(`.github/workflows/release.yml`) does the rest. `rake release` does
not release: it stops and points here, because a gem that no CI run
checked must not go out.

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
- [ ] `bin/minitest test/unit` passes locally.
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
the license texts. It contains no binary: a release ships the
platform-independent gem only. The host ruby runs zr (`exe/zr`). On
the first build, an installed gem builds the runtime into the user's
cache, and tells the user (`lib/zr/runtime.rb`).
