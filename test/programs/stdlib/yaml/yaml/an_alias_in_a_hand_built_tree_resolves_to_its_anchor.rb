# `Psych.parse` and the `Psych::Nodes::*` tree it answers.
#
# The tree is the DOCUMENT rather than the data: a gem walks it to read a tag,
# rewrite a scalar or count anchors, and `to_ruby` turns any node -- parsed or
# hand-built -- into the value it describes.

require "psych"

def show(label, v)
  puts "#{label}\t#{v.inspect}"
end

# --- an alias in a hand-built tree resolves ------------------------------
aliased = Psych::Nodes::Mapping.new
aliased.children << Psych::Nodes::Scalar.new("a")
aliased.children << Psych::Nodes::Sequence.new("keep")
aliased.children << Psych::Nodes::Scalar.new("b")
aliased.children << Psych::Nodes::Alias.new("keep")
built_alias = aliased.to_ruby
show "alias resolved", built_alias["a"].equal?(built_alias["b"])

# `Nodes::Node#yaml` is deliberately absent from these rows: zr refuses it
# (see tests/gaps/a_psych_node_tree_emits_yaml.rb) and ruby raises a
# different error again for a bare Document, so the row would compare two
# unrelated refusals rather than one behaviour.
