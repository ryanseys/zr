# aref_fallback: a fallback that is no Hash, Proc or Method gives each
# character through its public [] (rb_funcallv_public), also a blank slate's.
class Blank < BasicObject
  instance_methods.each { |im| undef_method im unless im == :__id__ || im == :__send__ }
  def [](c) = "<#{c.ord}>"
end
s = "aעb"
p s.encode("ISO-8859-1", fallback: Blank.new)
p s.encode("ISO-8859-1", fallback: { "ע" => "?" })
p s.encode("ISO-8859-1", fallback: ->(c) { "L" })
p s.encode("ISO-8859-1", fallback: "M".method(:itself).unbind.bind("M").owner.instance_method(:itself).bind("M").then { |m| ->(_) { m.call } })
hidden = Object.new
class << hidden
  private def [](c) = "p"
end
p((s.encode("ISO-8859-1", fallback: hidden) rescue $!.class))
p s.encode("ISO-8859-1", fallback: { "ע" => "m" }.method(:[]))
