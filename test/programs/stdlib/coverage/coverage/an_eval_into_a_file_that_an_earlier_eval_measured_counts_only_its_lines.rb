# Under `eval: true`, the first eval into a file gives the file its line
# array. A later eval into that file counts into the same array, each of
# its lines from zero again, and its lines past the end count nowhere.
require "coverage"

Coverage.start(lines: true, eval: true)
eval("x = 1\ny = 2\n", binding, __FILE__, 20)
eval("x = 3\n", binding, __FILE__, 19)
eval("x = 1\ny = 2\n", binding, __FILE__, 30)
eval("x = 1\n\ny = 2\n", binding, "other.rb", 1)
eval("y = 3\n", binding, "other.rb", 3)
eval("3.times do\n  x = 1\nend\n", binding, "loop.rb", 1)
eval("\nx = 2\n", binding, "loop.rb", 1)
result = Coverage.result
lines = result[__FILE__][:lines]
p lines.size, lines[18..20], lines[29]
p result["other.rb"], result["loop.rb"]
