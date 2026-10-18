# A blank slate undefines every method but __id__ and __send__, as rbs's
# test doubles do (RBS::UnitTest::Convertibles), so any send that CRuby's
# C does not make raises here.
class Blank < BasicObject
  instance_methods.each { |im| undef_method im unless im == :__id__ || im == :__send__ }
end
class ToStr < Blank
  def initialize(v) = @v = v
  def to_str = @v
end
class ToInt < Blank
  def initialize(v) = @v = v
  def to_int = @v
end
class ToF < Blank
  def initialize(v) = @v = v
  def to_f = @v
end
class ToS < Blank
  def initialize(v) = @v = v
  def to_s = @v
end
class ToPath < Blank
  def initialize(v) = @v = v
  def to_path = @v
end
class ToIO < Blank
  def initialize(v) = @v = v
  def to_io = @v
end
class Span < Blank
  def initialize(b, e, x = false) = (@b = b; @e = e; @x = x)
  def begin = @b
  def end = @e
  def exclude_end? = @x
end

def t(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue ::Exception => e
  puts "#{label}: !#{e.class}: #{e.message[0, 100]}"
end

# rb_range_values: an object that answers begin, end and exclude_end?
# reads as a Range wherever CRuby's C takes one.
t("array fill") { [1, 2, 3, 4].fill(0, Span.new(1, 2)) }
t("array fill excl to_int") { [1, 2, 3, 4].fill(0, Span.new(ToInt.new(1), ToInt.new(2), true)) }
t("array fill block") { [1, 2, 3, 4].fill(Span.new(2, nil)) { |i| i * 10 } }
t("array fill out") { [1, 2].fill(0, Span.new(-5, 1)) }
t("array slice!") { a = [1, 2, 3, 4]; [a.slice!(Span.new(1, 2)), a] }
t("array slice! excl") { a = [1, 2, 3, 4]; [a.slice!(Span.new(1, 3, true)), a] }
t("array []") { [1, 2, 3, 4][Span.new(1, 2)] }
t("array values_at") { [1, 2, 3, 4].values_at(Span.new(1, 2), 0) }
t("string []") { "abcd"[Span.new(1, 2)] }
t("string []=") { s = +"abcd"; s[Span.new(1, 2)] = "X"; s }
t("string slice!") { s = +"abcd"; [s.slice!(Span.new(1, 2)), s] }
t("string bytesplice") { s = +"abcd"; s.bytesplice(Span.new(1, 2), "X") }
t("string bytesplice both") { s = +"abcd"; s.bytesplice(Span.new(1, 2), "XYZ", Span.new(0, 1)) }
t("string bytesplice blank") { s = +"abcd"; s.bytesplice(Blank.new, "X") }
t("match []") { /(a)(b)(c)/.match("abc")[Span.new(1, 2)] }
t("match values_at") { /(a)(b)(c)/.match("abc").values_at(Span.new(1, 2), 0) }
t("caller") { caller(Span.new(0, 0)).size }
t("caller_locations") { caller_locations(Span.new(0, 0)).size }
t("caller to_int") { caller(ToInt.new(0)).size }
