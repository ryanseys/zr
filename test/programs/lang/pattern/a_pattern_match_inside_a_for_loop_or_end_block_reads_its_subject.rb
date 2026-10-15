# A `for` body and an END block run as blocks of the scope around them.
# A case/in, a one-line `=>` and an `in` test inside them keep reading the
# subject that the match holds, for every kind of pattern.
Point = Struct.new(:x, :y)
limit = 2
for value in [1, [2, 3], { a: 4 }, Point.new(5, 6), "s", [7, 8, 9], nil]
  case value
  in Integer => n if n < limit then puts "small #{n}"
  in Integer | Float => n then puts "number #{n}"
  in [first, *rest] if rest.size > 1 then puts "list #{first} #{rest}"
  in [a, b] then puts "pair #{a} #{b}"
  in { a: } then puts "hash #{a}"
  in Point[x:, y:] then puts "point #{x} #{y}"
  in ^limit then puts "pinned"
  in String => s then puts "string #{s}"
  else puts "other #{value.inspect}"
  end
end

def nested
  out = []
  for row in [[1, 2], [3, 4]]
    for cell in row
      cell => Integer => c
      out << c if cell in 1 | 4
    end
  end
  out
end
p nested

[1].each do |n|
  for item in [{ k: n }]
    case item
    in { k: Integer => k } then p [:block, k]
    end
  end
end

END {
  case [1, 2]
  in [one, two] then p [:end, one, two]
  end
}
