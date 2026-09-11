# What a pattern and a numeric literal build on is the core's own Array,
# Hash, TypeError and Kernel, not whatever the program's scope names so,
# and a class with no Kernel still makes `3r` and `2i`.
module Shadows
  class Array; end
  class Hash; end
  class TypeError < StandardError; end
  class NoMatchingPatternError < StandardError; end

  case [1]
  in [x] then p x
  end

  case {a: 1}
  in {a:} then p a
  end

  begin
    case 5
    in [_] then p :no
    end
  rescue ::NoMatchingPatternError => e
    p e.class
  end

  odd = Object.new
  def odd.deconstruct = :nope
  begin
    case odd
    in [_] then p :no
    end
  rescue ::TypeError => e
    p [e.class, e.message]
  end
end

class Bare < BasicObject
  def values = [3r, 2i]
end
p Bare.new.values

__END__
1
1
NoMatchingPatternError
[TypeError, "deconstruct must return Array"]
[(3/1), (0+2i)]
