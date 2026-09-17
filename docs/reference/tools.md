# Tools

Scripts in `tools/`. Run each from the checkout's root. Each script's
header comment gives its full usage.

## The corpus

| Tool | Does |
|---|---|
| `ruby tools/record.rb [--os linux\|wasi] [--ruby <cmd>] <case>...` | runs ruby and writes its answer under `__END__` |
| `ruby tools/test.rb <case or dir>... [--gc stress] [--jobs N] [--target <triple>] [--keep] [--verbose]` | runs cases as `ze0 test` does and shows every difference; writes `tmp/test-report/` |
| `ruby tools/gap.rb <case>...` | moves cases to `test/gaps/` |
| `ruby tools/gap.rb --sweep tmp/sweep.txt` | moves every defect row of a sweep to `test/gaps/` |
| `ruby tools/gap.rb --promote gaps/<case> [dir]` | moves a gap that matches back to its topic |
| `ruby tools/dispatch.rb` | writes the programs that show which of its own methods a core class calls; record them next |

## Holding ports to ruby

Each runs a Ruby port and ruby's own implementation on the host, and
compares the two.

| Tool | Compares |
|---|---|
| `ruby tools/prism_diff.rb` | the prism port with ruby's prism: nodes, tokens, comments, diagnostics |
| `ruby tools/prism_upstream_tests.rb` | runs prism 1.9.0's own test suite on the port |
| `ruby tools/regexp_diff.rb` | the Onigmo port with ruby's regexp engine |
| `ruby tools/zlib_diff.rb` | the zlib port with ruby's zlib, byte for byte |
| `ruby tools/ast.rb` | `rt/ext/ze0/ast.rb` with ruby's `RubyVM::AbstractSyntaxTree` |

## Generated files

Each writes a file from an oracle: ruby, or a C source read at
development time. Do not edit the output by hand.

| Tool | Writes |
|---|---|
| `ruby -Ilib tools/description.rb [triple]` | `rt/ext/os/<os>/zr_description.rb`: the kernel description an eval carries |
| `ruby tools/errno.rb`, `fcntl.rb`, `etc.rb`, `socket.rb` | the OS tables of the ruby that runs them, under `rt/core/os/<os>/` and `rt/ext/os/<os>/` |
| `ruby -Ilib tools/libsystem.rb` | `lib/ze0/obj/macho/libsystem.rb`: the libSystem names ze0 imports |
| `ruby tools/features.rb` | `lib/ze0/hir/features.rb`: every name `require` answers in ruby |
| `ruby tools/builtin_lines.rb` | `rt/core/builtin_lines.rb`: the lines of the methods CRuby writes in Ruby |
| `ruby tools/prism_generate.rb` | `rt/ext/prism/ruby/*.rb` from `tools/prism/templates/` |
| `ruby tools/prism_encoding_tables.rb` | `rt/ext/prism/ruby/encoding_tables.rb` |
| `ruby tools/zlib_tables.rb` | `rt/kernel/zlib_tables.rb` |
| `ruby tools/onig_unicode.rb`, `onig_encodings.rb` | the Onigmo port's Unicode and encoding tables |
| `ruby tools/unicode.rb` | `rt/core/unicode.rb`: case mappings |
| `ruby tools/encodings.rb` | `rt/core/encodings.rb`: the encoding registry |
| `ruby tools/transcode.rb` | `rt/core/transcode.rb`: single-byte encoding tables |
| `ruby tools/cjk.rb`, `enc_mb.rb`, `emoji.rb` | multibyte encoding tables |
| `ruby tools/nkf.rb` | the nkf port's conversion tables |

## Measurement and bootstrap

| Tool | Does |
|---|---|
| `ruby -Ilib tools/codesize.rb [--all] [<was.tsv>]` | counts the instructions the backend writes for the runtime |
| `tools/stage.rb` | the compiler as a program; `bin/ze0 stage1` and `stage2` compile it |
