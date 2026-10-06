# An eval of a UTF-8 String that holds Big5 bytes, under a magic comment
# that says so, runs as Big5 while Coverage measures evals.
require "coverage"

Coverage.start(lines: true, eval: true)
source = "# encoding: big5\n$result = '\xA7A\xA6n'.bytes.inspect\n$name = __ENCODING__.name\n".dup.force_encoding("UTF-8")
p source.valid_encoding?
eval(source, binding, __FILE__, 20)
p $result, $name
eval("x = 1\ny = '\xff'\n".dup.force_encoding("BINARY"), binding, __FILE__, 30)
lines = Coverage.result[__FILE__][:lines]
p lines.size
p lines[19..21], lines[29..30]
