# frozen_string_literal: true
# shareable_constant_value: literal
# Under `literal`, an Array or Hash literal may hold a value that is not
# itself a literal when that value is shareable already: each such
# element is checked, and the container is frozen whole. An interpolated
# String is deduplicated first; an element that is not shareable is
# refused by the constant's name.

p Ractor.shareable?("x".b.freeze), Ractor.shareable?(["x".b.freeze])
TABLE = { "a" => "x".b.freeze, "b" => ("x" "y").b.freeze }
p TABLE, TABLE.frozen?, Ractor.shareable?(TABLE)
NESTED = [1, "s", { k: "v".b.freeze, j: [2, :z] }]
p NESTED, NESTED[2].frozen?, NESTED[2][:j].frozen?, Ractor.shareable?(NESTED)
INTERPOLATED = "a#{1}b"
p INTERPOLATED, INTERPOLATED.frozen?
held = [1]
begin
  REFUSED = [held]
rescue Ractor::IsolationError => e
  p e
end
begin
  ALSO_REFUSED = { a: held }
rescue Ractor::IsolationError => e
  p e
end
p held.frozen?

