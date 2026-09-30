# `Psych.parse` and the `Psych::Nodes::*` tree it answers.
#
# The tree is the DOCUMENT rather than the data: a gem walks it to read a tag,
# rewrite a scalar or count anchors, and `to_ruby` turns any node -- parsed or
# hand-built -- into the value it describes.

require "psych"

def show(label, v)
  puts "#{label}\t#{v.inspect}"
end

# --- each walks depth first, self first -----------------------------------
show "each classes", Psych.parse("a: [1]\n").each.map { |n| n.class.to_s.split("::").last }

