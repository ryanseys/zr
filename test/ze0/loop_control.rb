# `break` and `next` inside a loop are the LOOP's, whether the loop is
# written in a method or inside a block; only a jump with no loop around
# it is the block's.
def first_square_over(limit)
  i = 0
  while true
    i += 1
    break if i * i > limit
  end
  i
end
p first_square_over(50)

def odds_below(n)
  out = []
  i = 0
  while i < n
    i += 1
    next if i % 2 == 0
    out << i
  end
  out
end
p odds_below(7)

p [1, 2].map { |n| i = 0; while i < 10; i += 1; break if i == n + 2; end; i }
p [1].map { o = []; i = 0; while i < 5; i += 1; next if i == 2; o << i; end; o }
p [1].map { i = 0; until i > 2; i += 1; break :early; end; i }
p [1].map { i = 0; (i += 1; break :modifier if i > 1) while true; i }

# A `while` answers nil, or whatever a `break` gave it.
p(while true; break 7; end)
i = 0
p(while i < 2; i += 1; end)

# A block written inside a loop keeps its own `break`.
seen = []
n = 0
while n < 3
  n += 1
  seen << [1, 2, 3].each { |x| break x * 10 if x == 2 }
end
p seen

# Nested loops: the inner `break` leaves only the inner one.
pairs = []
i = 0
while i < 3
  i += 1
  j = 0
  while j < 9
    j += 1
    break if j == 2
  end
  pairs << [i, j]
end
p pairs

# A jump out of a `rescue` clause inside a loop pops only what it opened.
kept = []
i = 0
while i < 5
  i += 1
  begin
    raise "stop" if i == 4
    next if i == 2
    kept << i
  rescue StandardError
    break
  end
end
p kept

# `else` runs only when the body finished, and outside the clauses.
p(begin
    "a" + "b"
  rescue StandardError
    :rescued
  else
    "c" + "d"
  end)
p(begin
    raise "boom"
  rescue StandardError
    :rescued
  else
    :else_ran
  end)

# A method defined twice keeps the last one, as ruby does.
class Twice
  def answer = 1
  def answer(_x) = 2
end
p Twice.new.answer(0)
p Twice.instance_method(:answer).arity
__END__
8
[1, 3, 5, 7]
[3, 4]
[[1, 3, 4, 5]]
[1]
[2]
7
nil
[20, 20, 20]
[[1, 2], [2, 2], [3, 2]]
[1, 3]
"cd"
:rescued
2
1
