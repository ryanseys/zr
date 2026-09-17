# Tools

`rake -T` names every task. The scripts live in `tools/`, and each
script's header comment gives its full usage; a task is the spelling to
reach for, since it puts the compiler and the test support on the load
path itself.

## Tests

| Task | Does |
|---|---|
| `rake test` | the units, the specs and the end-to-end programs |
| `rake test:unit [FILTER=exe,zr]` | ze0's own internals |
| `rake test:spec [FILTER=] [GC=stress]` | Ruby held to ruby, program by program |
| `rake test:e2e` | whole programs through a real link |
| `rake 'test:one[test/unit/zr_test.rb,-n /gc/]'` | one file, with minitest's own options |
| `rake bench[filters]` | how long does what ze0 built take? |
| `rake stage1`, `rake stage2` | the bootstrap |

## The corpus, while it converts

| Tool | Does |
|---|---|
| `ruby tools/convert.rb --plan <dir>` | which cases convert to specs, and why the rest do not |
| `ruby tools/convert.rb --describe TEXT --out PATH <dir>` | writes the specs |
| `ruby tools/convert_verify.rb <spec> <dir>` | holds a written spec to the cases it came from |
| `ruby -Ilib -Itest tools/measure_spec.rb <dir> [--limit N]` | what a compile costs, and how the heap grows |
| `rake record[case]` | runs ruby and writes its answer under `__END__` |
| `rake gaps:demote[case]`, `gaps:promote[case,dir]`, `gaps:sweep` | moves a program in and out of `test/gaps/` |

## Holding ports to ruby

Each runs a Ruby port and ruby's own implementation on the host, and
compares the two.

| Task | Compares |
|---|---|
| `rake 'diff:prism[--writer]'` | the prism port with ruby's prism |
| `rake diff:prism_upstream` | prism 1.9.0's own test suite on the port |
| `rake 'diff:regexp[--fuzz 3000]'` | the Onigmo port with ruby's regexp engine |
| `rake 'diff:zlib[--deflate]'` | the zlib port with ruby's zlib, byte for byte |
| `rake diff:ast` | `rt/ext/ze0/ast.rb` with ruby's `RubyVM::AbstractSyntaxTree` |
| `rake diff:openssl` | ruby 4.0.6's `test/openssl` against the port |

## Generated files

Each writes a file from an oracle: ruby, or a C source read at
development time. The output carries a header saying so. Do not edit it
by hand.

| Task | Writes |
|---|---|
| `rake gen:features` | `lib/ze0/hir/features.rb` |
| `rake gen:unicode` | `rt/core/unicode.rb`: case mappings |
| `rake gen:encodings` | `rt/core/encodings.rb`: the encoding registry |
| `rake gen:transcode` | `rt/core/transcode.rb`: single-byte encoding tables |
| `rake gen:cjk`, `gen:enc_mb`, `gen:emoji` | multibyte encoding tables |
| `rake gen:onig_unicode`, `gen:onig_encodings` | the Onigmo port's tables |
| `rake gen:zlib_tables` | `rt/kernel/zlib_tables.rb` |
| `rake gen:builtin_lines` | `rt/core/builtin_lines.rb` |
| `rake gen:nkf` | `rt/ext/nkf/tables.rb` |
| `rake gen:prism_generate`, `gen:prism_encoding_tables` | `rt/ext/prism/ruby/*.rb` |
| `rake gen:openssl_constants` | `rt/ext/openssl/ossl/constants.rb` |
| `rake gen:dispatch` | the programs that show which of its own methods a core class calls |
| `rake tables` | this OS's errno, fcntl, etc and socket tables, then fails on a difference |

`rt/ext/os/<os>/zr_description.rb` and `lib/ze0/obj/macho/libsystem.rb`
are snapshots the checks hold rather than tasks:
`ZE0_BLESS=1 rake test:unit FILTER=description` writes them again.

## Measurement and bootstrap

| Task | Does |
|---|---|
| `rake 'codesize[--all]'` | counts the instructions the backend writes for the runtime |
| `tools/stage.rb` | the compiler as a program; `rake stage1` and `stage2` compile it |
