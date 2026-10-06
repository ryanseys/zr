# A method that Refinement#import_methods copies runs with its refinement
# active: it calls the other imported methods, from the same module or
# from another one, with self or with no receiver.
str_utils = Module.new do
  def indent(level) = " " * level + self
  def indent_with_dot(level) = self.indent(level) + "."
  def bare_indent(level) = indent(level) + "!"
end
other = Module.new do
  def shout = upcase + indent(1)
end
Module.new do
  refine String do
    import_methods str_utils, other
  end
  using self
  p "foo".indent_with_dot(3), "foo".bare_indent(2), "x".shout
end

# Outside the `using`, the methods are not there.
p(("foo".indent(1) rescue $!.class))

# A name that no method has still misses.
m = Module.new { def missing_here = nope }
Module.new do
  refine(String) { import_methods m }
  using self
  p(("a".missing_here rescue $!.message))
end
