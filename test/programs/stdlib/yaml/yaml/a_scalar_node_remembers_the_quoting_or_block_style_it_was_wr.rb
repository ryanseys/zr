# `Psych.parse` and the `Psych::Nodes::*` tree it answers.
#
# The tree is the DOCUMENT rather than the data: a gem walks it to read a tag,
# rewrite a scalar or count anchors, and `to_ruby` turns any node -- parsed or
# hand-built -- into the value it describes.

require "psych"

def show(label, v)
  puts "#{label}\t#{v.inspect}"
end

# --- quoting and block scalars keep their style ---------------------------
styles = Psych.parse("- plain\n- 'single'\n- \"double\"\n- |\n  literal\n- >\n  folded\n")
show "styles", styles.root.children.map(&:style)
show "quoted flags", styles.root.children.map(&:quoted)

