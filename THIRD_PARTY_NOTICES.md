# Third-party notices

zr's own code is under the MIT License (`LICENSE.txt`). The gem also
ships code that other people wrote. This file names each part, its
version, its license, and where its license text is.

## The vendored library: `vendor/`

`vendor/` holds code that other people wrote, byte for byte as they
ship it. Nobody edits a file there: `zr-dev vendor` writes it from
`lib/zr/vendor.rb`, and `vendor/vendor.lock` names each source (a ruby
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

## Code in `runtime/` derived from other work

| File | Derived from | License |
|---|---|---|
| `runtime/kernel/fpconv.rb` | fpconv (Andreas Samoljuk), as vendored by the json gem | MIT |
| `runtime/kernel/float.rb` (the Ryu section), `runtime/kernel/ryu_tables.rb` | Ryu (Ulf Adams) | Apache-2.0 or Boost-1.0 |
| `runtime/core/regexp/onig.rb`, `runtime/core/regexp/onig/*.rb`, `runtime/core/regexp/unicode_tables.rb`, `runtime/kernel/regexp.rb`, `runtime/kernel/onig_enc.rb`, `runtime/kernel/onig_stack.rb`, `runtime/kernel/onig_match.rb`, `runtime/kernel/onig_cache.rb`, `runtime/kernel/onig_search.rb` | Onigmo, the regular expression engine of CRuby 4.0.7 (K. Kosako, K. Takata); the license text is in `runtime/kernel/regexp.rb` | BSD-2-Clause |
| `runtime/core/regexp_pattern.rb` | CRuby 4.0.7's `re.c` (the preprocess, encoding and description functions) | Ruby or BSD-2-Clause |
| `runtime/ext/prism/prism.rb`, `runtime/ext/prism/ruby/*.rb` | prism 1.9.0's C (the parser, lexer, encodings, options, serializer and extension); the license text is in `vendor/ruby/lib/ruby/gems/4.0.0/gems/prism-1.9.0/LICENSE.md` | MIT |
| `runtime/ext/openssl.so.rb`, `runtime/ext/openssl/ossl/*.rb` | the C half of ruby's openssl gem 4.0.2 (`ext/openssl/ossl*.c` in CRuby 4.0.7); the license text is in `vendor/LICENSES/openssl/COPYING` | Ruby or BSD-2-Clause |
| `runtime/kernel/zlib_check.rb`, `runtime/kernel/zlib_tables.rb`, `runtime/kernel/zlib_stream.rb`, `runtime/kernel/zlib_inftrees.rb`, `runtime/kernel/zlib_inffast.rb`, `runtime/kernel/zlib_inflate.rb`, `runtime/kernel/zlib_trees.rb`, `runtime/kernel/zlib_deflate.rb`, `runtime/kernel/os/*/zlib.rb` | zlib 1.3.1 (Jean-loup Gailly and Mark Adler); the license text is in `runtime/kernel/zlib.rb` | Zlib |

| `runtime/core/random.rb` | MT19937 (Makoto Matsumoto and Takuji Nishimura), as CRuby 4.0.7's `missing/mt19937.c` has it; the license text is in `licenses/mt19937.txt` | BSD-3-Clause |
| `runtime/kernel/digest.rb`, `runtime/ext/digest/*.rb`, `runtime/ext/digest.so.rb` | CRuby 4.0.7's `ext/digest`: MD5 (L. Peter Deutsch, Aladdin Enterprises; `licenses/md5.txt`, zlib-style), RIPEMD-160 (Antoon Bosselaers, Katholieke Universiteit Leuven; `licenses/rmd160.txt`, BSD), SHA-2 (Aaron D. Gifford; `licenses/sha2.txt`, BSD-3-Clause), SHA-1 (Steve Reid, public domain), and ruby's own glue | as named, and Ruby or BSD-2-Clause for the glue |
| `runtime/ext/psych/libyaml/*.rb` | libyaml 0.2.5 (Kirill Simonov, Ingy döt Net); the license text is in `licenses/libyaml.txt` | MIT |
| `runtime/ext/psych.so.rb` | the C half of the psych gem 5.3.1; the license text is in `vendor/LICENSES/psych/LICENSE` | MIT |
| `runtime/ext/nkf.so.rb`, `runtime/ext/nkf/*.rb` | nkf 2.1.5 (Itaru Ichikawa, Fujitsu; the nkf Project), as the nkf gem 0.3.0 has it; the license text is in `licenses/nkf.txt` | zlib-style |
| `runtime/core/unicode.rb`, `runtime/core/regexp/unicode_tables.rb`, `runtime/kernel/onig_tables.rb`, `vendor/ruby/lib/ruby/4.0.0/unicode_normalize/tables.rb` | the Unicode Character Database 17.0.0, as ruby 4.0.7 carries it; the license text is in `licenses/unicode.txt` | Unicode-3.0 |
| `runtime/core/cjk.rb`, `runtime/core/transcode.rb`, `runtime/core/emoji.rb`, `runtime/core/iso2022.rb` | CRuby 4.0.7's `enc/trans` tables; the notices of the mapping data are in `licenses/enc-trans.txt` | Ruby or BSD-2-Clause, and the mapping data's own notices |
| `runtime/ext/json/ext/*.rb` | the C half of the json gem 3.0.2; the license text is in `vendor/ruby/lib/ruby/gems/4.0.0/gems/json-3.0.2/COPYING` | Ruby or BSD-2-Clause |
| `runtime/ext/racc/cparse.rb` | the C half of the racc gem 1.8.1 (`cparse.c`); the license text is in `vendor/ruby/lib/ruby/gems/4.0.0/gems/racc-1.8.1/COPYING` | Ruby or BSD-2-Clause |
| `runtime/ext/ffi_c/*.rb`, `runtime/ext/ffi_c.rb` | the C half of the ffi gem 1.17.4; the license text is in `vendor/ruby/lib/ruby/gems/4.0.0/gems/ffi-1.17.4/LICENSE` | BSD-3-Clause |
| `runtime/ext/date.rb`, `runtime/ext/date/*.rb`, `runtime/ext/stringio.rb`, `runtime/ext/strscan.rb`, `runtime/ext/socket/*.rb`, `runtime/ext/socket.so.rb`, `runtime/ext/syslog_ext.rb`, `runtime/ext/fiddle.so.rb`, `runtime/ext/ripper.so.rb`, `runtime/lib/zr/ast.rb`, `runtime/ext/os/*/io/console/*.rb`, `runtime/core/hash.rb`, `runtime/core/set.rb`, `runtime/core/time.rb`, `runtime/core/format.rb`, `runtime/core/pathname.rb`, `runtime/kernel/objspace.rb`, `runtime/kernel/os/*/env.rb`, `runtime/kernel/zlib.rb` | the C of CRuby 4.0.7 and of its default gems (date, stringio, strscan, socket, syslog, fiddle, io-console, etc and others): these files follow the C functions they name; the license texts are in `vendor/LICENSES/ruby` | Ruby or BSD-2-Clause |

The full texts of the licenses that have no other copy in the gem are
in `licenses/`.

## What a compiled program contains

A binary or a WASI module that zr builds contains the zr runtime, so it
contains code from some of the parts above. Every program contains
Onigmo (BSD-2-Clause), MT19937 (BSD-3-Clause), Ryu (Apache-2.0 or
Boost-1.0), fpconv (MIT), the Unicode tables (Unicode-3.0) and ruby's
own code (Ruby or BSD-2-Clause). A program that requires zlib, digest,
psych, nkf, json, ffi or openssl also contains that part, and the files
it requires from ruby's library.

Several of these licenses ask that a binary copy reproduces the
notice. If you distribute a binary that zr built, give its users the
notices of the parts it contains: this file and the texts in
`licenses/`, `vendor/LICENSES`, the bundled gems' own license files and `runtime/kernel/regexp.rb` are
one way to do that.

## Benchmarks (repository only, not in the gem)

`benchmark/` holds benchmarks from spinel (MIT); see `benchmark/UPSTREAM.md`.
