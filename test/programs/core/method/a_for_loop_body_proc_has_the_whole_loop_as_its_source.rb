# The Proc that a `for` loop passes to each has the whole loop as its
# source: source_range covers `for ... end`, and syntax_tree is the
# ForNode, as ruby 4.1 gives them.
$stdout.sync = true
iter = Object.new
def iter.each(&block)
  block.call(block)
end

for pr in iter
  42
end
r = pr.source_range
p [r.start_line, r.start_column, r.end_line, r.end_column]
loc = pr.source_location
p [File.basename(loc[0]), *loc.drop(1)]
node = pr.syntax_tree
p [node.class, node.start_line, node.end_line]

two = Object.new
def two.each = yield(proc { :inner }, 2)
for c, d in two
  got = c
end
p [got.call, d]
