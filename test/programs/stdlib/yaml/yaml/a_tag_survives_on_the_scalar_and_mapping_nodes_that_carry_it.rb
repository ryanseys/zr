# `Psych.parse` and the `Psych::Nodes::*` tree it answers.
#
# The tree is the DOCUMENT rather than the data: a gem walks it to read a tag,
# rewrite a scalar or count anchors, and `to_ruby` turns any node -- parsed or
# hand-built -- into the value it describes.

require "psych"

def show(label, v)
  puts "#{label}\t#{v.inspect}"
end

# --- tags survive ---------------------------------------------------------
tagged = Psych.parse("--- !!str 42\n")
show "scalar tag", tagged.root.tag
show "scalar value", tagged.root.value

taggedmap = Psych.parse("--- !ruby/object:Widget\nname: bolt\n")
show "mapping tag", taggedmap.root.tag

