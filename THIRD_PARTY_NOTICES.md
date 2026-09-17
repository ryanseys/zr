# Third-party notices

ze0's own code is under the MIT License (`LICENSE.txt`). The gem also
ships code that other people wrote. This file names each part, its
version, its license, and where its license text is.

## Ruby halves of extension gems

| Component | Version | License | Path | License text |
|---|---|---|---|---|
| prism | 1.9.0 | MIT | `vendor/ext/prism` | `vendor/ext/prism/LICENSE.md` |
| json | 2.21.2 | Ruby or BSD-2-Clause | `vendor/ext/json` | `vendor/ext/json/COPYING`, `BSDL`, `LEGAL` |
| psych | 5.3.1 | MIT | `vendor/ext/psych` | `vendor/ext/psych/LICENSE` |
| bigdecimal | as bundled with ruby 4.0.6 | Ruby or BSD-2-Clause | `vendor/ext/bigdecimal` | `vendor/ext/bigdecimal/LICENSE`, `BSDL` |
| digest | 3.2.1 | Ruby or BSD-2-Clause | `vendor/ext/digest` | `vendor/ext/digest/COPYING`, `BSDL` |
| syslog | as bundled with ruby 4.0.6 | Ruby or BSD-2-Clause | `vendor/ext/syslog` | `vendor/ext/syslog/COPYING`, `BSDL` |
| socket | ruby 4.0.6 | Ruby or BSD-2-Clause | `vendor/ext/socket` | `vendor/ext/socket/COPYING`, `BSDL` |
| ffi | 1.17.4 | BSD-3-Clause | `vendor/ext/ffi` | `vendor/ext/ffi/LICENSE` |

## Ruby's pure-Ruby standard library and bundled gems

`vendor/lib` holds ruby 4.0.6's pure-Ruby standard library and bundled
gems, unedited. `vendor/lib/VERSIONS` names each version. The license
texts are in `vendor/lib/LICENSES/`.

| Components | License | License text |
|---|---|---|
| The standard library and every bundled gem not named below | Ruby or BSD-2-Clause | `COPYING`, `BSDL` |
| rake | MIT | `rake-MIT-LICENSE` |
| minitest | MIT | `minitest-LICENSE` |
| rexml, rss | BSD-2-Clause | `rexml-LICENSE.txt`, `rss-LICENSE.txt` |
| test-unit | Ruby, BSD-2-Clause, or PSFL (parts) | `test-unit-COPYING`, `test-unit-PSFL` |
| reline (parts from rb-readline) | Ruby, and BSD-3-Clause for the rb-readline parts | `reline-license_of_rb-readline` |
| rubygems | Ruby or MIT | `COPYING`, `rubygems-MIT.txt` |
| bundler | MIT | `bundler-LICENSE.md` |
| did_you_mean | MIT | `did_you_mean-LICENSE.txt` |
| error_highlight | MIT | `error_highlight-LICENSE.txt` |
| syntax_suggest | MIT | `syntax_suggest-LICENSE` |

`vendor/prelude/gem_prelude.rb` is ruby 4.0.6's own `gem_prelude.rb`,
unedited, under Ruby or BSD-2-Clause.

## Code in `rt/` derived from other work

| File | Derived from | License |
|---|---|---|
| `rt/kernel/fpconv.rb` | fpconv (Andreas Samoljuk), as vendored by the json gem | MIT |
| `rt/kernel/float.rb` (the Ryu section), `rt/kernel/ryu_tables.rb` | Ryu (Ulf Adams) | Apache-2.0 or Boost-1.0 |
| `rt/ext/date/parse.rb` | CRuby's `date_parse.c` (date gem) | Ruby or BSD-2-Clause |
| `rt/core/regexp/onig.rb`, `rt/core/regexp/onig/*.rb`, `rt/core/regexp/unicode_tables.rb`, `rt/kernel/regexp.rb`, `rt/kernel/onig_enc.rb`, `rt/kernel/onig_stack.rb`, `rt/kernel/onig_match.rb`, `rt/kernel/onig_cache.rb`, `rt/kernel/onig_search.rb` | Onigmo, the regular expression engine of CRuby 4.0.6 (K. Kosako, K. Takata); the license text is in `rt/kernel/regexp.rb` | BSD-2-Clause |
| `rt/core/regexp_pattern.rb` | CRuby 4.0.6's `re.c` (the preprocess, encoding and description functions) | Ruby or BSD-2-Clause |
| `rt/ext/prism/prism.rb`, `rt/ext/prism/ruby/*.rb` | prism 1.9.0's C (the parser, lexer, encodings, options, serializer and extension); the license text is in `vendor/ext/prism/LICENSE.md` | MIT |
| `rt/kernel/zlib_check.rb`, `rt/kernel/zlib_tables.rb`, `rt/kernel/zlib_stream.rb`, `rt/kernel/zlib_inftrees.rb`, `rt/kernel/zlib_inffast.rb`, `rt/kernel/zlib_inflate.rb`, `rt/kernel/zlib_trees.rb`, `rt/kernel/zlib_deflate.rb`, `rt/kernel/os/*/zlib.rb` | zlib 1.3.1 (Jean-loup Gailly and Mark Adler); the license text is in `rt/kernel/zlib.rb` | Zlib |

## Benchmarks (repository only, not in the gem)

`test/bench` holds benchmarks from spinel (MIT); see `test/bench/UPSTREAM.md`.
