# CRuby's C checks an argument's type with no send (rb_obj_is_kind_of,
# NIL_P, CLASS_OF), so a BasicObject that only converts (to_str, to_int,
# to_ary) works as an argument of core methods, as rbs's tests pass them.
class ToStr < BasicObject
  def initialize(s) = @s = s
  def to_str = @s
end
class ToInt < BasicObject
  def initialize(i) = @i = i
  def to_int = @i
end
class ToAry < BasicObject
  def initialize(a) = @a = a
  def to_ary = @a
end
class Blank < BasicObject
end
class Answers < BasicObject
  def respond_to?(name, all = false) = name == :to_path
  def to_path = "/"
end

def t(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue ::Exception => e
  puts "#{label}: !#{e.class}: #{e.message[0, 90]}"
end

here = __FILE__
t(:exist) { File.exist?(ToStr.new(here)) }
t(:file_new) { File.new(ToStr.new(here)).class }
t(:open) { File.open(ToStr.new(here)) { |f| f.class } }
t(:dir_exist) { Dir.exist?(ToStr.new("/")) }
t(:basename) { File.basename(ToStr.new("/a/b.rb"), ToStr.new(".rb")) }
t(:start_with) { "abc".start_with?(ToStr.new("a")) }
t(:sub) { "abc".sub(ToStr.new("b"), ToStr.new("x")) }
t(:plus) { "a" + ToStr.new("b") }
t(:slice) { "abc".slice(ToInt.new(1)) }
t(:values_at) { [1, 2].values_at(ToInt.new(0)) }
t(:ary_plus) { [1] + ToAry.new([2]) }
t(:ary_fetch) { [5, 6].fetch(ToInt.new(1)) }
t(:integer) { Integer(ToStr.new("3")) }
t(:join) { [1, 2].join(ToStr.new("-")) }
t(:mkdir_p) { require "fileutils"; FileUtils.mkdir_p(ToStr.new("/tmp")) }
t(:blank_str) { "a" + Blank.new }
t(:blank_int) { [1].fetch(Blank.new) }
t(:own_respond_to) { Dir.exist?(Answers.new) }
