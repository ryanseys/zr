# A bare `super` written inside a BLOCK forwards the enclosing method's block
# to the parent, exactly as one written directly in the method body does.
# The method's parameters also go to the parent.
#
# CRuby yields the block through both `super`s and prints the collected
# values.
class Base
  def each_thing
    yield 1
    yield 2
    :base_done
  end
end

class Nested < Base
  def each_thing
    [1].map { super }.first
  end
end

acc = []
p Nested.new.each_thing { |v| acc << v }
p acc

# The same through two closures, as a real gem does it.
class Deeper < Base
  def each_thing
    [1].map { [2].map { super }.first }.first
  end
end

acc2 = []
p Deeper.new.each_thing { |v| acc2 << v * 10 }
p acc2
