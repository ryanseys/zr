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

