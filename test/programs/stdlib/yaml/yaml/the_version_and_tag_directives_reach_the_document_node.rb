# `Psych.parse` and the `Psych::Nodes::*` tree it answers.
#
# The tree is the DOCUMENT rather than the data: a gem walks it to read a tag,
# rewrite a scalar or count anchors, and `to_ruby` turns any node -- parsed or
# hand-built -- into the value it describes.

require "psych"

def show(label, v)
  puts "#{label}\t#{v.inspect}"
end

# --- directives -----------------------------------------------------------
withdirs = Psych.parse("%YAML 1.1\n%TAG !e! tag:example.com,2000:\n---\na: 1\n")
show "version", withdirs.version
show "tag directives", withdirs.tag_directives

