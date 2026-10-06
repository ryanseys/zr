# `Psych.parse` and the `Psych::Nodes::*` tree it answers.
#
# The tree is the DOCUMENT rather than the data: a gem walks it to read a tag,
# rewrite a scalar or count anchors, and `to_ruby` turns any node -- parsed or
# hand-built -- into the value it describes.

require "psych"

def show(label, v)
  puts "#{label}\t#{v.inspect}"
end

# --- to_ruby on a tree built by hand -------------------------------------
built = Psych::Nodes::Mapping.new
built.children << Psych::Nodes::Scalar.new("k")
built.children << Psych::Nodes::Scalar.new("9")
show "hand-built to_ruby", built.to_ruby

wrapped = Psych::Nodes::Document.new
wrapped.children << built
show "hand-built document", wrapped.to_ruby

