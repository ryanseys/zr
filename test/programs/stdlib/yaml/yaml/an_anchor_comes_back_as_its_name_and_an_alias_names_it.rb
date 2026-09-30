# `Psych.parse` and the `Psych::Nodes::*` tree it answers.
#
# The tree is the DOCUMENT rather than the data: a gem walks it to read a tag,
# rewrite a scalar or count anchors, and `to_ruby` turns any node -- parsed or
# hand-built -- into the value it describes.

require "psych"

def show(label, v)
  puts "#{label}\t#{v.inspect}"
end

# --- anchors come back as NAMES, not numbers ------------------------------
anchored = Psych.parse("a: &base {x: 1}\nb: *base\n")
pairs = anchored.root.children
show "anchor name", pairs[1].anchor
show "alias class", pairs[3].class
show "alias anchor", pairs[3].anchor

