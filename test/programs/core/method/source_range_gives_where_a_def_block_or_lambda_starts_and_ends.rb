# Proc#source_range, Method#source_range and UnboundMethod#source_range
# (ruby 4.1) give a Ruby::SourceRange: the path, the real path when the
# code comes from a file (nil in an eval), and the line and byte column
# where the def, the block (from its `{` or `do`) or the lambda (from its
# `->`) starts and ends. A heredoc past the end is not in it. A C method,
# an attribute method or a Proc that the runtime made has none; a core
# method that ruby writes in Ruby has its `<internal:…>` def.
$stdout.sync = true
def show(label, x)
  r = x.source_range
  if r
    p [label, File.basename(r.path), r.absolute_path && r.absolute_path == File.realpath(r.path), r.start_line, r.start_column, r.end_line, r.end_column,
       r.inspect.sub(r.absolute_path || r.path, "F")]
  else
    p [label, nil]
  end
end

def m1 = 42
  def m2(a, b = 1)
    a
  end
class K
  def self.s; end
  define_method(:dm) { 1 }
  define_method(:dl, &->(x) { x })
  attr_reader :ar
  def k = 1
end
show :m1, method(:m1)
show :m2, method(:m2)
show :m2u, Object.instance_method(:m2)
show :s, K.method(:s)
show :dm, K.instance_method(:dm)
show :dl, K.instance_method(:dl)
show :ar, K.instance_method(:ar)
show :k, K.new.method(:k)
show :puts, method(:puts)
show :tap, method(:tap)
show :proc, proc { 1 }
show :lam, ->(x) { x }
show :lamdo, (lambda do |x|
  x
end)
show :pdo, (proc do
  2
end)
show :lam0, -> {}
x = -> { }
show :x, x
show :sym, :upcase.to_proc
show :mproc, method(:m1).to_proc
show :heredoc, proc { <<~H }
  text
H
show :ev, eval("proc { 1 }")
show :ev2, eval("proc { 1 }", binding, "f.rb", 10)
show :ev3, eval("\n  def em; end; method(:em)", binding, "/abs/g.rb", 3)
show :ie, K.class_eval("def ce; end; instance_method(:ce)")
show :alias, (K.alias_method(:k2, :k); K.instance_method(:k2))
p Ruby::SourceRange.respond_to?(:new), (Ruby::SourceRange.allocate rescue $!.class)
p Ruby::SourceRange.instance_methods(false).sort
r = method(:m1).source_range
p r == method(:m1).source_range, r.frozen?, r.class, r.to_s.start_with?("#<Ruby::SourceRange:")
show :multi, [1].map { |v|
  v
}.then { method(:m2) }
show :blk, (def bb(&b) = b; bb { })
show :blk2, (def bb2(&b) = b; bb2 do |q| end)
show :num, proc { _1 }
show :curried, ->(a, b) { a }.curry
show :unicode, proc { "é" }; show :after, proc { "é" }
p eval("proc { 1 }").source_range.absolute_path
p eval("proc { 1 }", binding, "f.rb", 10).source_range.absolute_path
p eval("proc { 1 }", binding, "/abs/g.rb", 3).source_range.absolute_path
p eval("proc { 1 }", binding, __FILE__, 3).source_range.absolute_path
p method(:p).source_range, proc { 1 }.source_range.absolute_path == File.realpath(__FILE__)
m = Module.new { def self.q = 1 }
p m.method(:q).source_range.start_column
p Kernel.instance_method(:then).source_range, Kernel.instance_method(:frozen?).source_range, Integer.instance_method(:times).source_range
p Comparable.instance_method(:clamp).source_range, Array.instance_method(:each).source_range
