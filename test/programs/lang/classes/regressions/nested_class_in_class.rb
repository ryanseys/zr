# Nested class definition inside another class.
# `T_nested_class_in_class_A::B` names the inner class, and a bare `B`
# inside the outer class finds it too.

class T_nested_class_in_class_A
  class B
    def initialize(x)
      @x = x
    end
    attr_reader :x
  end

  def make_b(x)
    B.new(x)
  end
end

# Direct construction via the path
b = T_nested_class_in_class_A::B.new(7)
puts b.x

# Construction via the outer class
b2 = T_nested_class_in_class_A.new.make_b(42)
puts b2.x

# T_nested_class_in_class_A nested class with its own nested class
class T_nested_class_in_class_Outer
  class Mid
    class Inner
      def hello
        "hi"
      end
    end
  end
end

puts T_nested_class_in_class_Outer::Mid::Inner.new.hello
