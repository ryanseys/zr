# `self.class.<cmeth>` in a parent-defined instance method calls the
# class method of the receiver's real class. This is true also when
# the base and subclass methods return different types -- the
# canonical Rails "abstract base raises, subclass returns concrete
# value" pattern. The base method runs only when the receiver is
# an instance of the base class.
#
# Coverage:
#   - Variant 1: Base.label raises, Article.label returns
#     String. Article.new.describe should print the String.
#   - Variant 2: IntBase.foo returns int, StrChild.foo returns
#     String. StrChild gets the String and IntBase gets the int.
#     puts shows both correctly.

class Base
  def self.label
    raise "subclass must override"
  end

  def describe
    self.class.label
  end
end

class Article < Base
  def self.label
    "articles"
  end
end

puts Article.new.describe

class IntBase
  def self.foo; 42; end
  def show; self.class.foo; end
end
class StrChild < IntBase
  def self.foo; "child"; end
end

puts StrChild.new.show
puts IntBase.new.show
