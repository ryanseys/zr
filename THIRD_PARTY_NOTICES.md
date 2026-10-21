# Third-party notices

zr's own code is under the MIT License (`LICENSE.txt`). The gem also
ships code that other people wrote. This file names each part, its
version, its license, and where its license text is.

## The vendored library: `vendor/`

`vendor/` holds code that other people wrote, byte for byte as they
ship it. Nobody edits a file there: `zr-dev vendor` writes it from
`tool/lib/zr/dev/vendored.rb`, and `vendor/vendor.lock` names each source (a ruby
revision, a `.gem` with its SHA-256, a git commit) and the SHA-256 of each
file. A program that zr builds carries the files it requires from it,
under each one's own license. `<ruby_version>` in a path below is the
library version of the ruby that `.ruby-version` names (RbConfig's
`ruby_version`).

- `vendor/ruby/lib/ruby/<ruby_version>` holds the pinned ruby's own library, as a
  stock ruby installs it: CRuby's `lib/` and `ext/*/lib`,
  rubygems, and the default gems (among them the Ruby halves of psych,
  openssl, digest and socket, whose C zr ports, at the versions of the
  table below). The
  license texts are in `vendor/LICENSES`: ruby's own
  (`vendor/LICENSES/ruby`, Ruby or BSD-2-Clause), and each default
  gem's where its gem has one, for example bundler, did_you_mean,
  error_highlight and syntax_suggest (MIT) and psych (MIT, in
  `vendor/LICENSES/psych/LICENSE`).
- `vendor/ruby/gem_prelude.rb` is the pinned ruby's own `gem_prelude.rb`,
  under Ruby or BSD-2-Clause.
- `vendor/ruby/lib/ruby/gems/<ruby_version>/gems` holds the bundled gems and the gems whose C zr
  ports, each in its own directory with its own license files: most are
  Ruby or BSD-2-Clause; minitest and rake are MIT (minitest's text,
  from its README, is in `vendor/LICENSES/minitest`), rexml and rss are
  BSD-2-Clause, and test-unit is Ruby, BSD-2-Clause or PSFL.
- `vendor/src/prism-1.9.0` holds prism's `config.yml` and templates, from
  the commit that ruby bundles, which only `zr-dev gen prism` reads (MIT).
- Each directory of `vendor/targets` (`aarch64-linux-musl`,
  `aarch64-linux-gnu` and `x86_64-linux-gnu`) holds the pinned ruby's C
  headers (`include/ruby-<ruby_version>`) and its `rbconfig.rb` for that
  target, from a build of the pinned ruby's release tarball (with the
  configure of the official ruby image) in the `alpine` image for musl
  and the `ubuntu` image for glibc: `vendor/vendor.lock` names the
  tarball and the image of each. zr builds a C extension for that target
  with them. They are under Ruby or BSD-2-Clause (`vendor/LICENSES/ruby`).

The gems whose C zr ports, at zr's versions:

| Component | Version | License | Path | License text |
|---|---|---|---|---|
| prism | 1.9.0 | MIT | `vendor/ruby/lib/ruby/gems/<ruby_version>/gems/prism-1.9.0` | `vendor/ruby/lib/ruby/gems/<ruby_version>/gems/prism-1.9.0/LICENSE.md` |
| json | 3.0.2 | Ruby or BSD-2-Clause | `vendor/ruby/lib/ruby/gems/<ruby_version>/gems/json-3.0.2` | `vendor/ruby/lib/ruby/gems/<ruby_version>/gems/json-3.0.2/COPYING`, `BSDL`, `LEGAL` |
| bigdecimal | 4.1.3 | Ruby or BSD-2-Clause | `vendor/ruby/lib/ruby/gems/<ruby_version>/gems/bigdecimal-4.1.3` | `vendor/ruby/lib/ruby/gems/<ruby_version>/gems/bigdecimal-4.1.3/LICENSE` |
| syslog | 0.4.0 | Ruby or BSD-2-Clause | `vendor/ruby/lib/ruby/gems/<ruby_version>/gems/syslog-0.4.0` | `vendor/ruby/lib/ruby/gems/<ruby_version>/gems/syslog-0.4.0/COPYING`, `BSDL` |
| ffi | 1.17.4 | BSD-3-Clause | `vendor/ruby/lib/ruby/gems/<ruby_version>/gems/ffi-1.17.4` | `vendor/ruby/lib/ruby/gems/<ruby_version>/gems/ffi-1.17.4/LICENSE` |
| nkf | 0.3.0 | Ruby or BSD-2-Clause | `vendor/ruby/lib/ruby/gems/<ruby_version>/gems/nkf-0.3.0` | `vendor/ruby/lib/ruby/gems/<ruby_version>/gems/nkf-0.3.0/COPYING`, `BSDL`, `LEGAL` |
| fiddle | 1.1.8 | Ruby or BSD-2-Clause | `vendor/ruby/lib/ruby/gems/<ruby_version>/gems/fiddle-1.1.8` | `vendor/ruby/lib/ruby/gems/<ruby_version>/gems/fiddle-1.1.8/LICENSE.txt` |
| racc | 1.8.1 | Ruby or BSD-2-Clause | `vendor/ruby/lib/ruby/gems/<ruby_version>/gems/racc-1.8.1` | `vendor/ruby/lib/ruby/gems/<ruby_version>/gems/racc-1.8.1/COPYING`, `BSDL` |
| rbs | 4.2.0 | Ruby or BSD-2-Clause | `vendor/ruby/lib/ruby/gems/<ruby_version>/gems/rbs-4.2.0` | `vendor/ruby/lib/ruby/gems/<ruby_version>/gems/rbs-4.2.0/COPYING`, `BSDL` |
| debug | 1.11.1 | Ruby or BSD-2-Clause | `vendor/ruby/lib/ruby/gems/<ruby_version>/gems/debug-1.11.1` | `vendor/ruby/lib/ruby/gems/<ruby_version>/gems/debug-1.11.1/LICENSE.txt` |
| psych | 5.5.0 | MIT | `vendor/ruby/lib/ruby/<ruby_version>/psych` | `vendor/LICENSES/psych/LICENSE` |
| openssl | 4.0.2 | Ruby or BSD-2-Clause | `vendor/ruby/lib/ruby/<ruby_version>/openssl` | `vendor/LICENSES/openssl/COPYING`, `BSDL` |
| digest | 3.3.0 | Ruby or BSD-2-Clause | `vendor/ruby/lib/ruby/<ruby_version>/digest` | `vendor/LICENSES/digest/LICENSE.txt` |
| socket | the pinned ruby's | Ruby or BSD-2-Clause | `vendor/ruby/lib/ruby/<ruby_version>/socket.rb` | `vendor/LICENSES/ruby/COPYING`, `BSDL` |

## Code in `lib/zr/runtime/` derived from other work

| File | Derived from | License |
|---|---|---|
| `lib/zr/runtime/kernel/fpconv.rb` | fpconv (Andreas Samoljuk), as the json gem vendors it, at the version of the table above; the license texts are in `licenses/fpconv.txt` | MIT, and Boost-1.0 for the json gem's copy |
| `lib/zr/runtime/kernel/float.rb` (the Ryu section), `lib/zr/runtime/kernel/ryu_tables.rb` | Ryu (Ulf Adams); the license texts are in `licenses/ryu.txt` | Apache-2.0 or Boost-1.0 |
| `lib/zr/runtime/core/regexp/onig.rb`, `lib/zr/runtime/core/regexp/onig/*.rb`, `lib/zr/runtime/core/regexp/unicode_tables.rb`, `lib/zr/runtime/kernel/regexp.rb`, `lib/zr/runtime/kernel/onig_enc.rb`, `lib/zr/runtime/kernel/onig_stack.rb`, `lib/zr/runtime/kernel/onig_match.rb`, `lib/zr/runtime/kernel/onig_cache.rb`, `lib/zr/runtime/kernel/onig_search.rb`, `lib/zr/runtime/kernel/enc_mb.rb`, `lib/zr/runtime/kernel/capi/regex.rb` | Onigmo, the regular expression engine of CRuby (K. Kosako, K. Takata); the license text is in `lib/zr/runtime/kernel/regexp.rb` | BSD-2-Clause |
| `lib/zr/runtime/core/regexp_pattern.rb` | CRuby's `re.c` (the preprocess, encoding and description functions) | Ruby or BSD-2-Clause |
| `lib/zr/runtime/ext/prism/prism.so.rb`, `lib/zr/runtime/ext/prism/ruby.rb`, `lib/zr/runtime/ext/prism/ruby/*.rb`, `lib/zr/runtime/ext/ruby/prism/prism.rb` | prism's C, at the version of the table above (the parser, lexer, encodings, options, serializer and extension); the license text is in `vendor/ruby/lib/ruby/gems/<ruby_version>/gems/prism-1.9.0/LICENSE.md` | MIT |
| `lib/zr/runtime/ext/openssl.so.rb`, `lib/zr/runtime/ext/openssl/ossl/*.rb` | the C half of ruby's openssl gem, at the version of the table above (`ext/openssl/ossl*.c` in CRuby); the license text is in `vendor/LICENSES/openssl/COPYING` | Ruby or BSD-2-Clause |
| `lib/zr/runtime/kernel/zlib_check.rb`, `lib/zr/runtime/kernel/zlib_tables.rb`, `lib/zr/runtime/kernel/zlib_stream.rb`, `lib/zr/runtime/kernel/zlib_inftrees.rb`, `lib/zr/runtime/kernel/zlib_inffast.rb`, `lib/zr/runtime/kernel/zlib_inflate.rb`, `lib/zr/runtime/kernel/zlib_trees.rb`, `lib/zr/runtime/kernel/zlib_deflate.rb`, `lib/zr/runtime/kernel/os/*/zlib.rb` | zlib 1.3.1 (Jean-loup Gailly and Mark Adler); the license text is in `lib/zr/runtime/kernel/zlib.rb` | Zlib |
| `lib/zr/runtime/core/random.rb` | MT19937 (Makoto Matsumoto and Takuji Nishimura), as CRuby's `missing/mt19937.c` has it; the license text is in `vendor/LICENSES/ruby/LEGAL`, section `[missing/mt19937.c]` | BSD-3-Clause |
| `lib/zr/runtime/kernel/os/wasi/libm.rb`, `lib/zr/runtime/kernel/os/wasi/libm_*.rb` | musl 1.2.5's `src/math` (Rich Felker, et al.), with code from FreeBSD's msun (Sun Microsystems) and from Arm Limited's optimized routines; the license texts are in `licenses/musl.txt` | MIT, the Sun notice, and MIT for Arm's files |
| `lib/zr/runtime/kernel/sort.rb` (from `zr_sort_apple_all` to `zr_sort_heap`) | FreeBSD's `qsort.c` and `heapsort.c` (The Regents of the University of California; heapsort by Ronnie Kon, Kevin Lew and Elmer Yglesias), as Apple Libc-1752 ships them; the license texts are in `licenses/freebsd-libc.txt` | BSD-3-Clause |
| `lib/zr/runtime/kernel/os/linux/libc/musl/smoothsort.rb` | musl 1.2.6's `src/stdlib/qsort.c`, Lynn Ochs's smoothsort; the license text is in `licenses/musl.txt` | MIT |
| `lib/zr/runtime/kernel/os/wasi/strtod.rb` | the decimal conversion of Go's strconv package (`decimal.go`, `atof.go`; The Go Authors); the license text is in `licenses/go.txt` | BSD-3-Clause |
| `lib/zr/runtime/kernel/digest.rb`, `lib/zr/runtime/ext/digest/*.rb`, `lib/zr/runtime/ext/digest.so.rb` | CRuby's `ext/digest`: MD5 (L. Peter Deutsch, Aladdin Enterprises; zlib-style; the license text is in `vendor/LICENSES/ruby/LEGAL`, section `[ext/digest/md5/md5.c]`), RIPEMD-160 (Antoon Bosselaers, Katholieke Universiteit Leuven; BSD; the license text is in `vendor/LICENSES/ruby/LEGAL`, section `[ext/digest/rmd160/rmd160.c]`), SHA-2 (Aaron D. Gifford; BSD-3-Clause; the license text is in `vendor/LICENSES/ruby/LEGAL`, section `[ext/digest/sha2/sha2.c]`), SHA-1 (Steve Reid, public domain), and ruby's own glue | as named, and Ruby or BSD-2-Clause for the glue |
| `lib/zr/runtime/ext/psych/libyaml/*.rb` | libyaml 0.2.5 (Kirill Simonov, Ingy döt Net); the license text is in `licenses/libyaml.txt` | MIT |
| `lib/zr/runtime/ext/psych.so.rb` | the C half of the psych gem, at the version of the table above; the license text is in `vendor/LICENSES/psych/LICENSE` | MIT |
| `lib/zr/runtime/ext/nkf.so.rb`, `lib/zr/runtime/ext/nkf/*.rb` | nkf 2.1.5 (Itaru Ichikawa, Fujitsu; the nkf Project), as the nkf gem has it, at the version of the table above; the license text is in `licenses/nkf.txt` | zlib-style |
| `lib/zr/runtime/kernel/case_tables.rb`, `lib/zr/runtime/core/regexp/unicode_tables.rb`, `lib/zr/runtime/kernel/onig_tables.rb`, `vendor/ruby/lib/ruby/<ruby_version>/unicode_normalize/tables.rb` | the Unicode Character Database 17.0.0, as ruby carries it; the license text is in `licenses/unicode.txt` | Unicode-3.0 |
| `lib/zr/runtime/core/cjk.rb`, `lib/zr/runtime/core/transcode.rb`, `lib/zr/runtime/core/emoji.rb`, `lib/zr/runtime/core/iso2022.rb` | CRuby's `enc/trans` tables; the notices of the mapping data are in `vendor/LICENSES/ruby/LEGAL`, sections `[enc/trans/GB/GB12345%UCS.src]` to `[enc/trans/ucm/windows-950_hkscs-2001.ucm]` | Ruby or BSD-2-Clause, and the mapping data's own notices |
| `lib/zr/runtime/ext/digest/blake3.so.rb` | BLAKE3 1.8.5's portable C (`blake3.c`, `blake3_portable.c`; Jack O'Connor and Samuel Neves), as the digest gem has it in `ext/digest/blake3`, at the version of the table above; the license texts are in `licenses/blake3.txt` | CC0-1.0, Apache-2.0 or Apache-2.0 WITH LLVM-exception |
| `lib/zr/runtime/ext/bigdecimal.so.rb` | the C half of the bigdecimal gem (`ext/bigdecimal/bigdecimal.c`), at the version of the table above; the license text is in `vendor/ruby/lib/ruby/gems/<ruby_version>/gems/bigdecimal-4.1.3/LICENSE` | Ruby or BSD-2-Clause |
| `lib/zr/runtime/ext/json/ext/*.rb` | the C half of the json gem, at the version of the table above; the license text is in `vendor/ruby/lib/ruby/gems/<ruby_version>/gems/json-3.0.2/COPYING` | Ruby or BSD-2-Clause |
| `lib/zr/runtime/ext/racc/cparse.so.rb` | the C half of the racc gem, at the version of the table above (`cparse.c`); the license text is in `vendor/ruby/lib/ruby/gems/<ruby_version>/gems/racc-1.8.1/COPYING` | Ruby or BSD-2-Clause |
| `lib/zr/runtime/ext/rbs_extension.so.rb`, `lib/zr/runtime/ext/rbs_extension/*.rb` | the C part of the rbs gem, at the version of the table above (`ext/rbs_extension` and the parser in `src/`); the license text is in `vendor/ruby/lib/ruby/gems/<ruby_version>/gems/rbs-4.2.0/COPYING` | Ruby or BSD-2-Clause |
| `lib/zr/runtime/ext/ffi_c/*.rb`, `lib/zr/runtime/ext/ffi_c.so.rb` | the C half of the ffi gem, at the version of the table above; the license text is in `vendor/ruby/lib/ruby/gems/<ruby_version>/gems/ffi-1.17.4/LICENSE` | BSD-3-Clause |
| `lib/zr/runtime/ext/date_core.so.rb`, `lib/zr/runtime/ext/date/*.rb`, `lib/zr/runtime/ext/stringio.so.rb`, `lib/zr/runtime/ext/strscan.so.rb`, `lib/zr/runtime/ext/socket/*.rb`, `lib/zr/runtime/ext/socket.so.rb`, `lib/zr/runtime/ext/syslog_ext.so.rb`, `lib/zr/runtime/ext/debug/debug.so.rb`, `lib/zr/runtime/ext/fiddle.so.rb`, `lib/zr/runtime/ext/ripper.so.rb`, `lib/zr/runtime/lib/zr/ast.rb`, `lib/zr/runtime/ext/os/*/io/console/*.rb`, `lib/zr/runtime/core/hash.rb`, `lib/zr/runtime/core/set.rb`, `lib/zr/runtime/core/time.rb`, `lib/zr/runtime/core/format.rb`, `lib/zr/runtime/core/pathname.rb`, `lib/zr/runtime/kernel/objspace.rb`, `lib/zr/runtime/kernel/os/*/env.rb`, `lib/zr/runtime/kernel/zlib.rb`, `lib/zr/runtime/ext/zlib.so.rb`, `lib/zr/runtime/ext/erb/escape.so.rb`, `lib/zr/runtime/core/argf.rb`, `lib/zr/runtime/core/c_format.rb`, `lib/zr/runtime/core/converter.rb`, `lib/zr/runtime/kernel/capi/numeric.rb`, `lib/zr/runtime/kernel/crash.rb`, `lib/zr/runtime/lib/zr/eval/arguments.rb`, `lib/zr/runtime/core/rubyvm.rb`, `lib/zr/runtime/core/rubyopt.rb`, `lib/zr/runtime/kernel/os/wasi/missing.rb` | the C of CRuby and of its default and bundled gems (date, stringio, strscan, socket, syslog, debug, fiddle, io-console, zlib, erb and others): these files follow the C functions they name; the license texts are in `vendor/LICENSES/ruby` | Ruby or BSD-2-Clause |

The full texts of the licenses that have no other copy in the gem are
in `licenses/`.

## What a compiled program contains

A binary or a WASI module that zr builds contains the zr runtime, so it
contains code from some of the parts above. Every program contains
Onigmo (BSD-2-Clause), MT19937 (BSD-3-Clause), Ryu (Apache-2.0 or
Boost-1.0), fpconv (MIT and Boost-1.0), the Unicode tables (Unicode-3.0) and ruby's
own code (Ruby or BSD-2-Clause). A macOS binary also contains the port
of FreeBSD's qsort and heapsort (BSD-3-Clause), and a binary for a musl
target the port of musl's smoothsort (MIT). A WASI module also contains the port
of musl's libm (MIT, and the Sun notice) and the port of Go's decimal
conversion (BSD-3-Clause). A program that requires zlib, digest,
psych, nkf, json, ffi or openssl also contains that part, and the files
it requires from ruby's library.

Several of these licenses ask that a binary copy reproduces the
notice. If you distribute a binary that zr built, give its users the
notices of the parts it contains: this file and the texts in
`licenses/`, `vendor/LICENSES`, the bundled gems' own license files and `lib/zr/runtime/kernel/regexp.rb` are
one way to do that.

## Benchmarks (repository only, not in the gem)

`benchmark/` holds benchmarks from spinel (MIT); see `benchmark/UPSTREAM.md`.
Some of them come, through spinel, from yjit-bench (MIT, Shopify), and
`bm_splay.rb` from V8's Octane suite (BSD-3-Clause). The license texts
are in `benchmark/LICENSE.txt`.
