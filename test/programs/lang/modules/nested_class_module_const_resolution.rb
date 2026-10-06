# When a class lives inside a module and another class in the same
# module is referenced via a bare name from one of its method bodies,
# the bare name resolves in the module's lexical scope. `Inner.new`
# inside `Outer#initialize` makes an `M::Inner`, and the ivar that
# holds it has that class.

module M
  class Inner
    def initialize(x)
      @x = x
    end
    attr_reader :x
  end

  class Outer
    def initialize
      @inner = Inner.new(10)
    end
    def via_ivar
      @inner.x
    end
    def via_local
      tmp = Inner.new(20)
      tmp.x
    end
  end
end

puts M::Outer.new.via_ivar
puts M::Outer.new.via_local
