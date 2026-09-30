# How to check a gem

This guide shows you how to find out if zr compiles a gem, and what
stops it if zr does not. The tool is `zr-dev gems`. It runs in a
checkout of zr, under ruby 4.0.7.

For each gem, the tool builds a small program (the probe) that requires
the gem and prints each constant that the require defines, with its
`VERSION`. It runs the probe under ruby 4.0.7 and as a zr binary, and
compares stdout, stderr and the exit status. It never runs `gem install`
and never compiles C.

## Before you start

Set up the reference ruby. The tool compares each probe with it:

```
$ ruby tool/zr-dev.rb reference
```

This guide writes `zr-dev` for `ruby tool/zr-dev.rb`.

## Try one gem

```
$ zr-dev gems try faraday
found faraday 2.14.4 (rubygems), with faraday-net_http 3.4.4
building probe.rb
running probe.rb under ruby and as a zr binary
--- probe.rb: output-diff

--- stdout (ruby, then zr)
@@ -11,7 +11,7 @@
 Digest Module
   VERSION 3.2.1
-  Base Class Instance REQUIRE_MUTEX VERSION
+  Base Class Instance REQUIRE_MUTEX SHA2 SHA256 SHA384 SHA512 VERSION
 Faraday Module
...
compiles  faraday 2.14.4  output-diff
  stdout line 14: ruby "  Base Class Instance REQUIRE_MUTEX VERSION", zr "  Base Class ..."
log: tmp/gems/logs/faraday-2.14.4.txt
```

The tool gets the newest release from rubygems.org, and the gems that it
needs, as `bundle install` would pick them. It takes only releases for
the `ruby` platform: a precompiled platform gem holds native code. A gem
that zr has already (its standard library, and the gems whose C zr
ports, such as json 3.0.2) is not fetched. The fetched gems are in
`tmp/gems`, a gem home as `gem install` leaves one (`gems/`,
`specifications/`, `cache/`), so `GEM_PATH=tmp/gems ruby` reads them too.

You can name a gem in three ways, as with `zr build --gem`:

| Word | Gem |
|---|---|
| `rack` | The newest release |
| `rack=3.1.8` | That version |
| `./src/rack` | The unpacked gem in that directory (a word with a `/` is a path) |

Options of `try`:

- `--keep` keeps the work directory (`tmp/gems/work/...`) with the probe
  and the binary, so that you can run them again.
- `--save` writes the result into `gems/compat.tsv`.
- `--corpus DIR` and `--offline`: see [Use a corpus](#use-a-corpus).

The exit status is 0 when the gem loads, and 1 when it does not.

## Read the result

Each gem gets a tier, from the worst to the best:

| Tier | Meaning |
|---|---|
| `refused` | zr refuses the gem: it has a C extension that zr does not port, or it uses a form of Ruby that zr does not support. |
| `fails` | The build fails, or the tool cannot find or resolve the gem. |
| `compiles` | zr builds the probe, but the binary's output is not ruby's. |
| `loads` | The probe gives ruby's output. |
| `verified` | The probe and the gem's smoke program give ruby's output. |
| `skipped` | The tool did not try the gem: an override skips it, or the probe fails under ruby too. |

A gem that stops below `loads` also gets a kind, the cause in one word:

| Kind | Cause |
|---|---|
| `cext:<gem>` | The gem, or a gem that it needs, has a C extension, and zr has no port of it. The tool knows this from the gemspec, before it builds. |
| `port-range:<gem>` | zr ports the gem's C, but not for this version (`lib/zr/ports.rb`). |
| `refused:<form>` | zr refuses a form of Ruby in the gem ([What zr supports](../reference/support.md)). |
| `missing-require:<feature>` | A `require` of the gem resolves to no file. |
| `build-error` | The build fails for another cause. |
| `zr-crash` | zr stops with an internal error, or the binary stops on a signal. |
| `timeout`, `memory` | A build (10 minutes, 2 GB) or a run (60 s, 1 GB) goes past its limit. |
| `output-diff`, `exception-diff`, `status-diff` | The binary's stdout, stderr or exit status is not ruby's. |
| `no-entry` | The tool cannot guess the feature to require. Name it in an override. |
| `not-found`, `resolve` | The gem or a gem that it needs cannot be found, or its versions do not agree. |
| `ruby-error` | The probe fails under ruby too. |
| `skip` | An override skips the gem. |

The full log of each gem is in `tmp/gems/logs/<name>-<version>.txt`:
each command, each output, and the diff.

## Check many gems

```
$ zr-dev gems top --refresh            # gems/top.tsv: the 1000 most downloaded gems
$ zr-dev gems sweep --top 100 --save
loads     bundler 4.0.21
compiles  aws-sdk-core 3.257.0  output-diff
...
refused   nokogiri 1.19.4  cext:nokogiri
...
100 gems: ...
wrote gems/compat.tsv
```

`sweep` takes gems by name, the top N of `gems/top.tsv` (`--top N`), or
both. It tries one gem at a time; `--jobs N` tries N at a time, but
each build can use 2 GB. Ctrl-C stops it and keeps the rows so far.

Without `--save`, the rows go into a new `tmp/gems/sweep-<time>.tsv`.
With `--save`, they go into `gems/compat.tsv`, which is committed. It
has one row for each gem, sorted by name, and a sweep replaces only the
rows of the gems that it tried. Its columns are `gem`, `version`,
`source`, `tier`, `kind`, `detail` (at most 200 characters),
`zr_commit`, `date` and `downloads`.

### Change zr while a sweep runs

A build fails when zr changes under it. To change zr while a long
sweep runs, sweep with a copy of zr:

```
$ dir=$(zr-dev gems snapshot)            # a copy of HEAD, with its compiled compiler
$ zr-dev gems sweep --zr "$dir" --top 200 --save
```

The copy is a git worktree in `tmp/gems/zr/<commit>` with its own
cache, so only committed work is in it. Each row names the copy's
commit. `zr-dev gems snapshot --list` prints the copies, and
`--remove DIR` removes one.

## Find what to fix next

```
$ zr-dev gems triage
 gems       downloads  kind           gems (most downloaded first)
   18  20,742,204,375  output-diff    aws-sdk-core, aws-sigv4, rake, concurrent-ruby, +14
    6   5,249,618,718  cext:nokogiri  nokogiri, actionpack, rails, railties, +2

24 of 50 gems do not load
$ zr-dev gems triage output-diff          # each gem of one kind, with its detail
```

`triage` groups the gems that do not load by kind. The kind that stops
the most gems comes first. `triage cext` gives every `cext:` kind.

Then write the docs page again:

```
$ zr-dev gen gem-compat
```

It writes [Gem compatibility](../reference/gem-compat.md) from
`gems/compat.tsv`.

## Help the tool with a gem

A file `gems/<name>.rb` changes how the tool tries the gem `<name>`:

```ruby
# zr-gems: skip -- needs a running Redis server
```

skips the gem, with that reason in its row.

```ruby
require "active_support"
require "active_support/core_ext"
```

names the features that the probe requires, in place of the guess. The
guess is the gem's name (`rack`), then its name with each `-` as a `/`
(`net-http` as `net/http`), then the `.rb` file at the top of its `lib`
whose name is the gem's without `_` and `-` (`activerecord` as
`active_record`), then the only `.rb` file there.

A file with more than requires is also a smoke program. It runs under
ruby and as a zr binary after the probe. When the two outputs agree, the
gem is `verified`:

```ruby
require "rainbow"

puts Rainbow("zr").red.bright
```

## Use a corpus

A corpus is a directory of unpacked gems, one directory for each name
(`<corpus>/rake`), as zeo's corpus has them. `--corpus DIR`, or the
variable `ZR_GEM_CORPUS`, makes the tool look in the corpus first, for
the gem and for each gem that it needs:

```
$ zr-dev gems sweep --corpus ~/dev/all-gems/gems --offline rake thor rack
```

The tool finds each gem by its exact path, and never lists the corpus,
so a corpus can hold every gem. It reads the version from
`.zeo-probe-version`, the require paths and the extensions from
`.zeo-probe-spec`, and the dependencies from `<name>.gemspec`.

`--offline` fetches nothing. A gem that is not in the corpus then comes
from `tmp/gems`, the gems that an earlier run fetched.
