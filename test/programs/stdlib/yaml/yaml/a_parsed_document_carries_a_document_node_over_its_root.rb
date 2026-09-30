# `Psych.parse` and the `Psych::Nodes::*` tree it answers.
#
# The tree is the DOCUMENT rather than the data: a gem walks it to read a tag,
# rewrite a scalar or count anchors, and `to_ruby` turns any node -- parsed or
# hand-built -- into the value it describes.

require "psych"

def show(label, v)
  puts "#{label}\t#{v.inspect}"
end

# --- the shape of a parsed document --------------------------------------
doc = Psych.parse("--- \na: 1\nb: [2, 3]\n")
show "document class", doc.class
show "document children", doc.children.size
show "implicit", doc.implicit
show "version", doc.version
show "tag directives", doc.tag_directives

root = doc.root
show "root class", root.class
show "root style block", root.style == Psych::Nodes::Mapping::BLOCK
show "root children", root.children.size

key = root.children[0]
show "key class", key.class
show "key value", key.value
show "key plain", key.plain
show "key quoted", key.quoted
show "key style plain", key.style == Psych::Nodes::Scalar::PLAIN

seq = root.children[3]
show "seq class", seq.class
show "seq style flow", seq.style == Psych::Nodes::Sequence::FLOW
show "seq children", seq.children.map(&:value)

