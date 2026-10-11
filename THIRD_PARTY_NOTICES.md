# Third-party notices

zr's own code is under the MIT License (`LICENSE.txt`). The gem also
ships code that other people wrote. This file names each part, its
version, its license, and where its license text is.

## The vendored library: `vendor/`

`vendor/` holds code that other people wrote, byte for byte as they
ship it. Nobody edits a file there: `zr-dev vendor` writes it from
`lib/zr/library/vendor.rb`, and `vendor/vendor.lock` names each source (a ruby
revision, a `.gem` with its SHA-256, a git tag) and the SHA-256 of each
file. A program that zr builds carries the files it requires from it,
under each one's own license.

- `vendor/ruby/lib/ruby/4.0.0` holds ruby 4.0.7's own library, as a
  stock ruby 4.0.7 installs it: CRuby's `lib/` and `ext/*/lib`,
  rubygems, and the default gems (among them the Ruby halves of psych
  5.3.1, openssl 4.0.2, digest 3.2.1 and socket, whose C zr ports). The
  license texts are in `vendor/LICENSES`: ruby's own
  (`vendor/LICENSES/ruby`, Ruby or BSD-2-Clause), and each default
  gem's where its gem has one, for example bundler, did_you_mean,
  error_highlight and syntax_suggest (MIT) and psych (MIT, in
  `vendor/LICENSES/psych/LICENSE`).
- `vendor/ruby/gem_prelude.rb` is ruby 4.0.7's own `gem_prelude.rb`,
  under Ruby or BSD-2-Clause.
- `vendor/ruby/lib/ruby/gems/4.0.0/gems` holds the bundled gems and the gems whose C zr
  ports, each in its own directory with its own license files: most are
  Ruby or BSD-2-Clause; minitest and rake are MIT (minitest's text,
  from its README, is in `vendor/LICENSES/minitest`), rexml and rss are
  BSD-2-Clause, and test-unit is Ruby, BSD-2-Clause or PSFL.
- `vendor/src/prism-1.9.0` holds prism's `config.yml` and templates, from
  its git tag, which only `zr-dev gen prism` reads (MIT).
- `vendor/targets/aarch64-linux-musl` holds ruby 4.0.7's C headers
  (`include/ruby-4.0.0`) and its `rbconfig.rb` for that target, as the
  image `docker.io/library/ruby` that `vendor/vendor.lock` names has
  them. zr builds a C extension for that target with them. They are
  under Ruby or BSD-2-Clause (`vendor/LICENSES/ruby`).

The gems whose C zr ports, at zr's versions:

| Component | Version | License | Path | License text |
|---|---|---|---|---|
| prism | 1.9.0 | MIT | `vendor/ruby/lib/ruby/gems/4.0.0/gems/prism-1.9.0` | `vendor/ruby/lib/ruby/gems/4.0.0/gems/prism-1.9.0/LICENSE.md` |
| json | 3.0.2 | Ruby or BSD-2-Clause | `vendor/ruby/lib/ruby/gems/4.0.0/gems/json-3.0.2` | `vendor/ruby/lib/ruby/gems/4.0.0/gems/json-3.0.2/COPYING`, `BSDL`, `LEGAL` |
| bigdecimal | 4.1.2 | Ruby or BSD-2-Clause | `vendor/ruby/lib/ruby/gems/4.0.0/gems/bigdecimal-4.1.2` | `vendor/ruby/lib/ruby/gems/4.0.0/gems/bigdecimal-4.1.2/LICENSE` |
| syslog | 0.4.0 | Ruby or BSD-2-Clause | `vendor/ruby/lib/ruby/gems/4.0.0/gems/syslog-0.4.0` | `vendor/ruby/lib/ruby/gems/4.0.0/gems/syslog-0.4.0/COPYING`, `BSDL` |
| ffi | 1.17.4 | BSD-3-Clause | `vendor/ruby/lib/ruby/gems/4.0.0/gems/ffi-1.17.4` | `vendor/ruby/lib/ruby/gems/4.0.0/gems/ffi-1.17.4/LICENSE` |
| nkf | 0.3.0 | Ruby or BSD-2-Clause | `vendor/ruby/lib/ruby/gems/4.0.0/gems/nkf-0.3.0` | `vendor/ruby/lib/ruby/gems/4.0.0/gems/nkf-0.3.0/COPYING`, `BSDL`, `LEGAL` |
| fiddle | 1.1.8 | Ruby or BSD-2-Clause | `vendor/ruby/lib/ruby/gems/4.0.0/gems/fiddle-1.1.8` | `vendor/ruby/lib/ruby/gems/4.0.0/gems/fiddle-1.1.8/LICENSE.txt` |
| racc | 1.8.1 | Ruby or BSD-2-Clause | `vendor/ruby/lib/ruby/gems/4.0.0/gems/racc-1.8.1` | `vendor/ruby/lib/ruby/gems/4.0.0/gems/racc-1.8.1/COPYING`, `BSDL` |
| psych | 5.3.1 | MIT | `vendor/ruby/lib/ruby/4.0.0/psych` | `vendor/LICENSES/psych/LICENSE` |
| openssl | 4.0.2 | Ruby or BSD-2-Clause | `vendor/ruby/lib/ruby/4.0.0/openssl` | `vendor/LICENSES/openssl/COPYING`, `BSDL` |
| digest | 3.2.1 | Ruby or BSD-2-Clause | `vendor/ruby/lib/ruby/4.0.0/digest` | `vendor/LICENSES/digest/LICENSE.txt` |
| socket | ruby 4.0.7 | Ruby or BSD-2-Clause | `vendor/ruby/lib/ruby/4.0.0/socket.rb` | `vendor/LICENSES/ruby/COPYING`, `BSDL` |

## Code in `lib/zr/runtime/` derived from other work

| File | Derived from | License |
|---|---|---|
| `lib/zr/runtime/kernel/fpconv.rb` | fpconv (Andreas Samoljuk), as the json gem 3.0.2 vendors it; the license texts are in `licenses/fpconv.txt` | MIT, and Boost-1.0 for the json gem's copy |
| `lib/zr/runtime/kernel/float.rb` (the Ryu section), `lib/zr/runtime/kernel/ryu_tables.rb` | Ryu (Ulf Adams); the license texts are in `licenses/ryu.txt` | Apache-2.0 or Boost-1.0 |
| `lib/zr/runtime/core/regexp/onig.rb`, `lib/zr/runtime/core/regexp/onig/*.rb`, `lib/zr/runtime/core/regexp/unicode_tables.rb`, `lib/zr/runtime/kernel/regexp.rb`, `lib/zr/runtime/kernel/onig_enc.rb`, `lib/zr/runtime/kernel/onig_stack.rb`, `lib/zr/runtime/kernel/onig_match.rb`, `lib/zr/runtime/kernel/onig_cache.rb`, `lib/zr/runtime/kernel/onig_search.rb` | Onigmo, the regular expression engine of CRuby 4.0.7 (K. Kosako, K. Takata); the license text is in `lib/zr/runtime/kernel/regexp.rb` | BSD-2-Clause |
| `lib/zr/runtime/core/regexp_pattern.rb` | CRuby 4.0.7's `re.c` (the preprocess, encoding and description functions) | Ruby or BSD-2-Clause |
| `lib/zr/runtime/ext/prism/prism.rb`, `lib/zr/runtime/ext/prism/ruby/*.rb` | prism 1.9.0's C (the parser, lexer, encodings, options, serializer and extension); the license text is in `vendor/ruby/lib/ruby/gems/4.0.0/gems/prism-1.9.0/LICENSE.md` | MIT |
| `lib/zr/runtime/ext/openssl.so.rb`, `lib/zr/runtime/ext/openssl/ossl/*.rb` | the C half of ruby's openssl gem 4.0.2 (`ext/openssl/ossl*.c` in CRuby 4.0.7); the license text is in `vendor/LICENSES/openssl/COPYING` | Ruby or BSD-2-Clause |
| `lib/zr/runtime/kernel/zlib_check.rb`, `lib/zr/runtime/kernel/zlib_tables.rb`, `lib/zr/runtime/kernel/zlib_stream.rb`, `lib/zr/runtime/kernel/zlib_inftrees.rb`, `lib/zr/runtime/kernel/zlib_inffast.rb`, `lib/zr/runtime/kernel/zlib_inflate.rb`, `lib/zr/runtime/kernel/zlib_trees.rb`, `lib/zr/runtime/kernel/zlib_deflate.rb`, `lib/zr/runtime/kernel/os/*/zlib.rb` | zlib 1.3.1 (Jean-loup Gailly and Mark Adler); the license text is in `lib/zr/runtime/kernel/zlib.rb` | Zlib |
| `lib/zr/runtime/core/random.rb` | MT19937 (Makoto Matsumoto and Takuji Nishimura), as CRuby 4.0.7's `missing/mt19937.c` has it; the license text is in `licenses/mt19937.txt` | BSD-3-Clause |
| `lib/zr/runtime/kernel/os/wasi/strtod.rb` | the decimal conversion of Go's strconv package (`decimal.go`, `atof.go`; The Go Authors); the license text is in `licenses/go.txt` | BSD-3-Clause |
| `lib/zr/runtime/kernel/digest.rb`, `lib/zr/runtime/ext/digest/*.rb`, `lib/zr/runtime/ext/digest.so.rb` | CRuby 4.0.7's `ext/digest`: MD5 (L. Peter Deutsch, Aladdin Enterprises; `licenses/md5.txt`, zlib-style), RIPEMD-160 (Antoon Bosselaers, Katholieke Universiteit Leuven; `licenses/rmd160.txt`, BSD), SHA-2 (Aaron D. Gifford; `licenses/sha2.txt`, BSD-3-Clause), SHA-1 (Steve Reid, public domain), and ruby's own glue | as named, and Ruby or BSD-2-Clause for the glue |
| `lib/zr/runtime/ext/psych/libyaml/*.rb` | libyaml 0.2.5 (Kirill Simonov, Ingy döt Net); the license text is in `licenses/libyaml.txt` | MIT |
| `lib/zr/runtime/ext/psych.so.rb` | the C half of the psych gem 5.3.1; the license text is in `vendor/LICENSES/psych/LICENSE` | MIT |
| `lib/zr/runtime/ext/nkf.so.rb`, `lib/zr/runtime/ext/nkf/*.rb` | nkf 2.1.5 (Itaru Ichikawa, Fujitsu; the nkf Project), as the nkf gem 0.3.0 has it; the license text is in `licenses/nkf.txt` | zlib-style |
| `lib/zr/runtime/core/unicode.rb`, `lib/zr/runtime/core/regexp/unicode_tables.rb`, `lib/zr/runtime/kernel/onig_tables.rb`, `vendor/ruby/lib/ruby/4.0.0/unicode_normalize/tables.rb` | the Unicode Character Database 17.0.0, as ruby 4.0.7 carries it; the license text is in `licenses/unicode.txt` | Unicode-3.0 |
| `lib/zr/runtime/core/cjk.rb`, `lib/zr/runtime/core/transcode.rb`, `lib/zr/runtime/core/emoji.rb`, `lib/zr/runtime/core/iso2022.rb` | CRuby 4.0.7's `enc/trans` tables; the notices of the mapping data are in `licenses/enc-trans.txt` | Ruby or BSD-2-Clause, and the mapping data's own notices |
| `lib/zr/runtime/ext/json/ext/*.rb` | the C half of the json gem 3.0.2; the license text is in `vendor/ruby/lib/ruby/gems/4.0.0/gems/json-3.0.2/COPYING` | Ruby or BSD-2-Clause |
| `lib/zr/runtime/ext/racc/cparse.rb` | the C half of the racc gem 1.8.1 (`cparse.c`); the license text is in `vendor/ruby/lib/ruby/gems/4.0.0/gems/racc-1.8.1/COPYING` | Ruby or BSD-2-Clause |
| `lib/zr/runtime/ext/ffi_c/*.rb`, `lib/zr/runtime/ext/ffi_c.rb` | the C half of the ffi gem 1.17.4; the license text is in `vendor/ruby/lib/ruby/gems/4.0.0/gems/ffi-1.17.4/LICENSE` | BSD-3-Clause |
| `lib/zr/runtime/ext/date_core.rb`, `lib/zr/runtime/ext/date/*.rb`, `lib/zr/runtime/ext/stringio.rb`, `lib/zr/runtime/ext/strscan.rb`, `lib/zr/runtime/ext/socket/*.rb`, `lib/zr/runtime/ext/socket.so.rb`, `lib/zr/runtime/ext/syslog_ext.rb`, `lib/zr/runtime/ext/fiddle.so.rb`, `lib/zr/runtime/ext/ripper.so.rb`, `lib/zr/runtime/lib/zr/ast.rb`, `lib/zr/runtime/ext/os/*/io/console/*.rb`, `lib/zr/runtime/core/hash.rb`, `lib/zr/runtime/core/set.rb`, `lib/zr/runtime/core/time.rb`, `lib/zr/runtime/core/format.rb`, `lib/zr/runtime/core/pathname.rb`, `lib/zr/runtime/kernel/objspace.rb`, `lib/zr/runtime/kernel/os/*/env.rb`, `lib/zr/runtime/kernel/zlib.rb` | the C of CRuby 4.0.7 and of its default gems (date, stringio, strscan, socket, syslog, fiddle, io-console, etc and others): these files follow the C functions they name; the license texts are in `vendor/LICENSES/ruby` | Ruby or BSD-2-Clause |

The full texts of the licenses that have no other copy in the gem are
in `licenses/`.

## What a compiled program contains

A binary or a WASI module that zr builds contains the zr runtime, so it
contains code from some of the parts above. Every program contains
Onigmo (BSD-2-Clause), MT19937 (BSD-3-Clause), Ryu (Apache-2.0 or
Boost-1.0), fpconv (MIT and Boost-1.0), the Unicode tables (Unicode-3.0) and ruby's
own code (Ruby or BSD-2-Clause). A program that requires zlib, digest,
psych, nkf, json, ffi or openssl also contains that part, and the files
it requires from ruby's library.

Several of these licenses ask that a binary copy reproduces the
notice. If you distribute a binary that zr built, give its users the
notices of the parts it contains: this file and the texts in
`licenses/`, `vendor/LICENSES`, the bundled gems' own license files and `lib/zr/runtime/kernel/regexp.rb` are
one way to do that.

## Benchmarks (repository only, not in the gem)

`benchmark/` holds benchmarks from spinel (MIT); see `benchmark/UPSTREAM.md`.
The license text is in `benchmark/LICENSE.txt`.
