# frozen_string_literal: true

# `case/in`, `expr in pattern` and `expr => pattern`. A pattern is a
# chain of sub-checks over one shared failure block: it matches when it
# reaches the end without jumping, and what it bound on the way survives
# a later check's failure, as ruby's does.

def kind(v)
  case v
  in Integer then :int
  in String then :str
  in nil then :nil
  in [1, 2] then :pair
  else :other
  end
end

p kind(1), kind("a"), kind(nil), kind([1, 2]), kind(:z)

def shape(v)
  case v
  in [] then :empty
  in [Integer => n] then [:one, n]
  in [1, *rest, 9] then [:bracketed, rest]
  in [*, :mid, *] then :found
  in [a, [b, c]] then [:nested, a, b, c]
  in { name: String => nm, age: Integer } then [:person, nm]
  in { only: } then [:only, only]
  in { a: 1, **r } then [:rest, r]
  in {} then :empty_hash
  in 1..5 then :small
  in 10 | 20 | 30 then :round
  in Integer | Float => num then [:number, num]
  else :none
  end
end

[
  [], [7], [1, 2, 3, 9], [:x, :mid, :y], [1, [2, 3]],
  { name: "n", age: 3 }, { only: 5 }, { a: 1, b: 2 },
  {}, 3, 20, 4.5, :zz,
].each { |v| p shape(v) }

# A class with the two protocols answers both an array and a hash
# pattern. `**rest` hands `deconstruct_keys` nil, which is what tells it
# the pattern will take everything.
class Pair
  def initialize(a, b) = (@a, @b = a, b)
  def deconstruct = [@a, @b]
  def deconstruct_keys(keys) = { a: @a, b: @b, keys: keys }
end

pair = Pair.new("x", "y")

case pair
in [one, two] then p [:arr, one, two]
end

case pair
in { a:, keys: } then p [:keys, a, keys]
end

case pair
in { **all } then p [:all, all]
end

# A Struct, and one named through a scope.
Point = Struct.new(:x, :y)
p(case Point.new(1, 2)
  in Point[x, y] then [:brackets, x, y]
  end)
p(case Point.new(3, 4)
  in Point(x:, y:) then [:parens, x, y]
  end)

module Geo
  Line = Struct.new(:a, :b)
end

case Geo::Line.new(5, 6)
in Geo::Line[a, b] then p [:scoped, a, b]
end

# A pin matches a value the pattern cannot spell, and any object whose
# `===` answers.
expected = 5
case 5
in ^expected then p :pinned
end

case 3
in ^(1 + 2) then p :pinned_expression
end

over_three = ->(v) { v > 3 }
case 5
in ^over_three then p :pinned_proc
end

# A guard is its own reason: the pattern matched and the condition did
# not.
case [1, 2, 3]
in [Integer => first, *] if first.positive? then p [:guard, first]
end

case [4]
in [only] unless only.zero? then p [:unless, only]
end

p((1 in Integer))
p(([1, 2] in [_, _]))
p(({ a: 1 } in { a: Integer }))
p((:z in Integer))

held = { a: 1, b: 2 }
held => { a: }
p a

# The bindings reach the scope around the `case`.
case { name: "zeo", version: [0, 1, 0] }
in { name: String => found, version: [major, minor, *] }
  nil
end
p found, major, minor

# An arm with no body answers nil.
p(case 1
  in Integer
  end)

def first_string(list)
  case list
  in [*, String => s, *] then return s
  in [] then :empty
  else :none
  end
end

p first_string([1, "hit", 2]), first_string([]), first_string([1])

# Every refusal names the same reason the runtime's own raise does.
def refused
  yield
rescue NoMatchingPatternKeyError => e
  [e.class, e.message, e.key, e.matchee]
rescue NoMatchingPatternError => e
  [e.class, e.message]
rescue TypeError, ArgumentError => e
  [e.class, e.message]
end

p refused { 5 => String }
p refused { { a: 1 } => { b: } }

p refused {
  case 9
  in String then 1
  in Float then 2
  end
}

p refused {
  case 9
  in String then 1
  end
}

p refused {
  case [1, 2]
  in [1] then :no
  end
}

p refused {
  case [1, 2, 3]
  in [*, 9, *] then :no
  end
}

p refused {
  case { a: 1, b: 2 }
  in { a:, **nil } then :no
  end
}

p refused {
  case({ a: 1 })
  in {} then :no
  end
}

p refused {
  case 1
  in Integer if false then :no
  end
}

class NotAnArray
  def deconstruct = :nope
end

class NotAHash
  def deconstruct_keys(_keys) = :nope
end

class Angry
  def ===(_other) = raise(ArgumentError, "from ===")
end

p refused {
  case NotAnArray.new
  in [x] then x
  end
}

p refused {
  case NotAHash.new
  in { a: } then a
  end
}

p refused {
  case 1
  in ^(Angry.new) then :no
  end
}
__END__
:int
:str
:nil
:pair
:other
:empty
[:one, 7]
[:bracketed, [2, 3]]
:found
[:nested, 1, 2, 3]
[:person, "n"]
[:only, 5]
[:rest, {b: 2}]
:empty_hash
:small
:round
:small
:none
[:arr, "x", "y"]
[:keys, "x", [:a, :keys]]
[:all, {a: "x", b: "y", keys: nil}]
[:brackets, 1, 2]
[:parens, 3, 4]
[:scoped, 5, 6]
:pinned
:pinned_expression
:pinned_proc
[:guard, 1]
[:unless, 4]
true
true
true
false
1
"zeo"
0
1
nil
"hit"
:empty
:none
[NoMatchingPatternError, "5: String === 5 does not return true"]
[NoMatchingPatternKeyError, "{a: 1}: key not found: :b", :b, {a: 1}]
[NoMatchingPatternError, "9"]
[NoMatchingPatternError, "9: String === 9 does not return true"]
[NoMatchingPatternError, "[1, 2]: [1, 2] length mismatch (given 2, expected 1)"]
[NoMatchingPatternError, "[1, 2, 3]: [1, 2, 3] does not match to find pattern"]
[NoMatchingPatternError, "{a: 1, b: 2}: rest of {b: 2} is not empty"]
[NoMatchingPatternError, "{a: 1}: {a: 1} is not empty"]
[NoMatchingPatternError, "1: guard clause does not return true"]
[TypeError, "deconstruct must return Array"]
[TypeError, "deconstruct_keys must return Hash"]
[ArgumentError, "from ==="]
