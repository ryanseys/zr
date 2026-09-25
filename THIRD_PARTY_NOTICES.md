# Third-party notices

zr's own code is under the MIT License (`LICENSE.txt`). The gem also
ships code that other people wrote. This file names each part, its
version, its license, and where its license text is.

## Ruby halves of extension gems

| Component | Version | License | Path | License text |
|---|---|---|---|---|
| prism | 1.9.0 | MIT | `vendor/ext/prism` | `vendor/ext/prism/LICENSE.md` |
| json | 2.21.2 | Ruby or BSD-2-Clause | `vendor/ext/json` | `vendor/ext/json/COPYING`, `BSDL`, `LEGAL` |
| psych | 5.3.1 | MIT | `vendor/ext/psych` | `vendor/ext/psych/LICENSE` |
| bigdecimal | as bundled with ruby 4.0.7 | Ruby or BSD-2-Clause | `vendor/ext/bigdecimal` | `vendor/ext/bigdecimal/LICENSE`, `BSDL` |
| digest | 3.2.1 | Ruby or BSD-2-Clause | `vendor/ext/digest` | `vendor/ext/digest/COPYING`, `BSDL` |
| syslog | as bundled with ruby 4.0.7 | Ruby or BSD-2-Clause | `vendor/ext/syslog` | `vendor/ext/syslog/COPYING`, `BSDL` |
| socket | ruby 4.0.7 | Ruby or BSD-2-Clause | `vendor/ext/socket` | `vendor/ext/socket/COPYING`, `BSDL` |
| ffi | 1.17.4 | BSD-3-Clause | `vendor/ext/ffi` | `vendor/ext/ffi/LICENSE` |
| openssl | 4.0.2 | Ruby or BSD-2-Clause | `vendor/ext/openssl` | `vendor/ext/openssl/COPYING`, `BSDL` |

## Ruby's pure-Ruby standard library

`vendor/lib` holds the files of ruby 4.0.7's pure-Ruby library that no
gem ships (CRuby's own `lib/` and `ext/*/lib`), unedited, under Ruby or
BSD-2-Clause. `vendor/lib/VERSIONS` names them; the license texts are
`vendor/lib/LICENSES/COPYING` and `BSDL`.

The rest of ruby's library is not in this gem. It is the default and
bundled gems `zr.gemspec` depends on (`Zr::Libraries::PINS` in
`lib/zr/libraries.rb`), which rubygems installs with their own license
files. A program zr builds carries the files it requires from them,
under each gem's own license.

`vendor/prelude/gem_prelude.rb` is ruby 4.0.7's own `gem_prelude.rb`,
unedited, under Ruby or BSD-2-Clause.

## Code in `runtime/` derived from other work

| File | Derived from | License |
|---|---|---|
| `runtime/kernel/fpconv.rb` | fpconv (Andreas Samoljuk), as vendored by the json gem | MIT |
| `runtime/kernel/float.rb` (the Ryu section), `runtime/kernel/ryu_tables.rb` | Ryu (Ulf Adams) | Apache-2.0 or Boost-1.0 |
| `runtime/ext/date/parse.rb` | CRuby's `date_parse.c` (date gem) | Ruby or BSD-2-Clause |
| `runtime/core/regexp/onig.rb`, `runtime/core/regexp/onig/*.rb`, `runtime/core/regexp/unicode_tables.rb`, `runtime/kernel/regexp.rb`, `runtime/kernel/onig_enc.rb`, `runtime/kernel/onig_stack.rb`, `runtime/kernel/onig_match.rb`, `runtime/kernel/onig_cache.rb`, `runtime/kernel/onig_search.rb` | Onigmo, the regular expression engine of CRuby 4.0.7 (K. Kosako, K. Takata); the license text is in `runtime/kernel/regexp.rb` | BSD-2-Clause |
| `runtime/core/regexp_pattern.rb` | CRuby 4.0.7's `re.c` (the preprocess, encoding and description functions) | Ruby or BSD-2-Clause |
| `runtime/ext/prism/prism.rb`, `runtime/ext/prism/ruby/*.rb` | prism 1.9.0's C (the parser, lexer, encodings, options, serializer and extension); the license text is in `vendor/ext/prism/LICENSE.md` | MIT |
| `runtime/ext/openssl.so.rb`, `runtime/ext/openssl/ossl/*.rb` | the C half of ruby's openssl gem 4.0.2 (`ext/openssl/ossl*.c` in CRuby 4.0.7); the license text is in `vendor/ext/openssl/COPYING` | Ruby or BSD-2-Clause |
| `runtime/kernel/zlib_check.rb`, `runtime/kernel/zlib_tables.rb`, `runtime/kernel/zlib_stream.rb`, `runtime/kernel/zlib_inftrees.rb`, `runtime/kernel/zlib_inffast.rb`, `runtime/kernel/zlib_inflate.rb`, `runtime/kernel/zlib_trees.rb`, `runtime/kernel/zlib_deflate.rb`, `runtime/kernel/os/*/zlib.rb` | zlib 1.3.1 (Jean-loup Gailly and Mark Adler); the license text is in `runtime/kernel/zlib.rb` | Zlib |

## Benchmarks (repository only, not in the gem)

`benchmark/` holds benchmarks from spinel (MIT); see `benchmark/UPSTREAM.md`.
