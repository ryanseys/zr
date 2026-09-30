# `Psych.parse` and the `Psych::Nodes::*` tree it answers.
#
# The tree is the DOCUMENT rather than the data: a gem walks it to read a tag,
# rewrite a scalar or count anchors, and `to_ruby` turns any node -- parsed or
# hand-built -- into the value it describes.

require "psych"

def show(label, v)
  puts "#{label}\t#{v.inspect}"
end

# --- to_ruby on a parsed tree --------------------------------------------
show "document to_ruby", Psych.parse("a: 1\nb: [2, 3]\n").to_ruby
show "root to_ruby", Psych.parse("a: 1\n").root.to_ruby
show "scalar to_ruby", Psych.parse("--- 42\n").root.to_ruby
show "stream to_ruby", Psych.parse_stream("--- 7\n").to_ruby

