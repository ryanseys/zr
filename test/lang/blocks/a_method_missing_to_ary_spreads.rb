# A BasicObject that forwards to an Array through method_missing, and says
# so through respond_to_missing?, spreads over block parameters, a
# multiple assignment and a splat, as rb_check_funcall lets it: prism's
# lex_compat tokens are such objects.
class Tok < BasicObject
  def initialize(a) = @a = a
  def respond_to_missing?(name, include_private = false) = @a.respond_to?(name, include_private)
  def method_missing(name, ...) = @a.send(name, ...)
end
toks = [Tok.new([[1, 2], :on_x, "t", 3])]
toks.each { |(l, c), ev, text, st| p [l, c, ev, text, st] }
toks.each { |a, b| p [a, b] }
a, b = Tok.new([5, 6])
p [a, b]
x, y = *Tok.new([7, 8])
p [x, y]
p [Tok.new([1]).to_ary]

__END__
[1, 2, :on_x, "t", 3]
[[1, 2], :on_x]
[5, 6]
[7, 8]
[[1]]
