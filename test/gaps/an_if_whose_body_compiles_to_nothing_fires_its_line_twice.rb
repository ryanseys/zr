# When the body of an `if` with an `elsif` compiles to no instruction (an
# unused literal), CRuby gives the body's :line event to the jump at its
# end, which is at the `if`'s line: TracePoint fires that line twice, and
# line coverage counts it twice. Which branches do so depends on how
# CRuby's compiler places the jump (an `elsif` before an `else` does not).
# zr fires and counts the line once.
require "coverage"
require "tmpdir"

Dir.mktmpdir do |dir|
  path = File.join(dir, "target.rb")
  File.write(path, "def f(a)\n  if a\n    3\n  elsif a.nil?\n    4\n  end\n  nil\nend\nf(1)\n")
  Coverage.start(lines: true)
  require path
  p Coverage.result.fetch(path)[:lines]
end
