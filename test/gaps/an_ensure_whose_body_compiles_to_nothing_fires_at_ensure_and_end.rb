# An `ensure` whose body compiles to nothing (a plain value) gives its
# :line event to the next instruction. CRuby compiles the body twice: on
# the raise path the event goes to the `ensure` line, and on the normal
# path to what follows, which for the last statement of a block is its
# `end`. So line coverage counts those lines, and TracePoint fires the
# `end` line. zr gives such a body no event.
require "coverage"
require "tmpdir"

Dir.mktmpdir do |dir|
  path = File.join(dir, "target.rb")
  File.write(path, "def f\n  [1].map do |w|\n    w.to_s\n  ensure\n    nil\n  end\nend\nf\n")
  Coverage.start(lines: true)
  require path
  p Coverage.result.fetch(path)[:lines]
end
