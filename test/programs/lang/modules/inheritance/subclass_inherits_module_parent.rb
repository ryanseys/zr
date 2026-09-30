# `class Sub < Base` inside `module M` has `M::Base` as its parent,
# so Sub keeps every field it inherits from Base.

module M
  class Base
    def initialize(x)
      @x = x
    end
  end

  class Sub < Base
    def double
      @x * 2
    end
    def x_plus(n)
      @x + n
    end
  end

  class Plain
    def initialize
      @y = 99
    end
  end

  class PlainSub < Plain
    def boost
      @y + 1
    end
  end
end

s = M::Sub.new(7)
puts s.double
puts s.x_plus(100)

ps = M::PlainSub.new
puts ps.boost
