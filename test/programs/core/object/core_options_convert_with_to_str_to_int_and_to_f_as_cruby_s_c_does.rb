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

# Options and operands that CRuby's C converts with rb_check_string_type,
# rb_check_id, NUM2INT, NUM2CHR, NUM2DBL or rb_get_path take an object
# that only converts.
require "stringio"
t("round half to_str") { [38.round(half: ToStr.new("up")), 25.round(-1, half: ToStr.new("even")), 2.5.round(half: ToStr.new("down"))] }
t("round half case") { [1.5.round(half: "UP"), 2.5.round(half: "Even"), 2.5.round(half: :DOWN), 25.round(-1, half: "DOWN")] }
t("round half bad") { 2.5.round(half: "upp") }
t("round half blank") { 2.5.round(half: Blank.new) }
t("test to_int") { test(ToInt.new("e".ord), __FILE__) }
t("test wide") { [test("e".ord + 256, "/"), test(101.9, "/")] }
t("test empty") { test("", "/") }
t("test to_str") { test(ToStr.new("e"), "/") }
t("test unknown") { ["'", "\\", "q", 0, 31].map { |c| test(c, "/") rescue $!.message } }
t("unpack offset") { ["abc".unpack("C", offset: ToInt.new(1)), "abc".unpack1("C", offset: ToInt.new(1)), "abc".unpack("C", offset: 1.9)] }
t("unpack offset str") { "abc".unpack("C", offset: "1") }
t("regexp timeout") { [ToF.new(1.5), 2, 1/2r].map { |v| Regexp.timeout = v; Regexp.timeout } }
t("regexp timeout str") { Regexp.timeout = "1" }
t("regexp timeout blank") { Regexp.timeout = Blank.new }
t("regexp timeout neg") { Regexp.timeout = -1.0 }
Regexp.timeout = nil
t("full_message order") { RuntimeError.new("a").full_message(highlight: false, order: ToStr.new("top")).lines.size }
t("full_message order int") { RuntimeError.new("a").full_message(order: 1) }
t("full_message order bad") { RuntimeError.new("a").full_message(order: "x") }
t("marshal limit") { [Marshal.dump([[1]], StringIO.new, ToInt.new(3)).string.size, Marshal.dump([[1]], StringIO.new, ToInt.new(-1)).string.size] }
t("marshal limit float") { Marshal.dump([[1]], StringIO.new, 3.5).string.size }
t("marshal limit nil") { Marshal.dump([[1]], StringIO.new, nil).string.size }
t("marshal nil port") { Marshal.dump(1, nil) }
t("marshal nil port limit") { Marshal.dump(1, nil, 2) }
t("marshal bignum port") { Marshal.dump(1, 2**70) }
t("marshal limit two") { Marshal.dump([[1]], 1) }
t("encode replace") { "\xff".encode("UTF-16LE", "UTF-8", invalid: :replace, replace: ToStr.new("?")).bytesize }
t("encode! replace") { s = +"\xff"; s.encode!("UTF-16LE", "UTF-8", invalid: :replace, replace: ToStr.new("?")); s.bytesize }
t("encode replace int") { "\xff".encode("UTF-16LE", "UTF-8", invalid: :replace, replace: 1) }
t("struct member") { Struct.new(:a, ToStr.new("b")).members }
t("struct member int") { Struct.new(:a, 1) }
t("time zone") { [Time.new(2000, 1, 1, 0, 0, 0, ToStr.new("+09:00")).utc_offset, Time.new(2000, 1, 1, in: ToStr.new("+09:00")).utc_offset] }
t("popen") { [IO.popen(ToStr.new("echo hi"), &:read), IO.popen({ "A" => "1" }, ToStr.new("echo $A"), &:read), IO.popen([ToStr.new("echo"), "x"], &:read)] }
t("popen int") { IO.popen(1) }
t("resolve_feature_path") { [$LOAD_PATH.resolve_feature_path(ToPath.new("erb"))&.first, $LOAD_PATH.resolve_feature_path(ToPath.new("__zr_none"))] }
t("resolve_feature_path int") { $LOAD_PATH.resolve_feature_path(1) }
