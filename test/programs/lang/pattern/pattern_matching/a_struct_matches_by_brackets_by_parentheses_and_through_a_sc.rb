# frozen_string_literal: true

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

