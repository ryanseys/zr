# Tasks

`rake -T` names every task. There is no `tools/` directory: a task's
body lives in `rakelib/*.rake`, which rake loads after the `Rakefile`,
and `rake` is the only way to run one. Each file's header comment gives
its full usage.

## Tests

| Task | Does |
|---|---|
| `rake test` | the units, the specs and the end-to-end programs |
| `rake test:unit [N=/Exe/]` | zr's own internals |
| `rake test:spec [N=] [GC=stress] [TARGET=]` | Ruby held to ruby, program by program |
| `rake test:e2e [TARGET=]` | whole programs through a real link |
| `minitest test/unit/zr_test.rb -n /gc/` | one file, or one example |
| `rake 'oracle[test/spec/core/string]'` | every spec literal re-checked against ruby 4.0.6 |
| `rake 'record[e2e/core/io/hello.rb]'` | runs ruby and writes its answer beside the program |
| `rake 'bench[--runs 5 fib]'` | how long does what zr built take? |
| `rake stage1`, `rake stage2` | the bootstrap |

## Generated files

Each writes a file from an oracle: ruby itself, or a CRuby source read
at ruby 4.0.6's revision. The output carries a header saying so. Do not
edit it by hand.

| Task | Writes |
|---|---|
| `rake gen:features` | `lib/zr/hir/features.rb` |
| `rake gen:unicode` | `rt/core/unicode.rb`: case mappings |
| `rake gen:encodings` | `rt/core/encodings.rb`: the encoding registry |
| `rake gen:transcode` | `rt/core/transcode.rb`: single-byte encoding tables |
| `rake gen:cjk`, `gen:enc_mb` | multibyte encoding tables |
| `rake gen:emoji` | `rt/core/emoji.rb` |
| `rake gen:builtin_lines` | `rt/core/builtin_lines.rb` |
| `rake tables` | this OS's errno, fcntl, etc and socket tables, then fails on a difference |
| `rake 'gen:dispatch[Hash]'` | prints the program a spec example carries, so a stale one shows |

Four more are written again on every `rake test:unit` and compared with
what is committed, so a stale one is a failing test rather than
something to remember. Their generators live in `test/support/oracle/`,
beside the tests that run them.

| Task | Writes | Held by |
|---|---|---|
| `rake gen:description` | `rt/ext/os/<os>/zr_description.rb` | `test/unit/description_test.rb` |
| `rake gen:libsystem` | `lib/zr/obj/macho/libsystem.rb` | `test/unit/libsystem_test.rb` |
| `rake gen:prism_generate` | `rt/ext/prism/ruby/*.rb` | `test/unit/prism_test.rb` |
| `rake gen:prism_encoding_tables` | `rt/ext/prism/ruby/encoding_tables.rb` | `test/unit/prism_test.rb` |

`ZR_BLESS=1 rake test:unit N=/Description/` writes the first two again
from inside the check.

### Tables with no generator here

Five tables were written once from a version that does not move, and
the generators are not carried: `git log` finds them.

| File | Written from |
|---|---|
| `rt/ext/nkf/tables.rb` | nkf 0.3.0's `utf8tbl.c` |
| `rt/core/regexp/unicode_tables.rb`, `rt/kernel/onig_tables.rb` | ruby 4.0.6's `enc/unicode/17.0.0` headers |
| `rt/core/regexp/onig/encoding_tables.rb` | CRuby 4.0.6's `enc/*.c` |
| `rt/kernel/zlib_tables.rb` | zlib's `crc32.c` and `trees.c` |
| `rt/ext/openssl/ossl/constants.rb` | ruby 4.0.6's openssl 4.0.2 |

## Measurement and bootstrap

| Task | Does |
|---|---|
| `rake 'codesize[--all]'` | counts the instructions the backend writes for the runtime |
