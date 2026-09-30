# RedoNode coverage — `redo` re-runs the current iteration of the
# enclosing loop without re-evaluating the guard or advancing the
# iterator. Each loop form handles `redo` on its own, so the tests
# cover every loop form.
#
# Per-section `def t_<form>; ...; end; t_<form>` isolates the
# `attempts` / `i` / `x` locals.


def t_each_cons
  attempts = 0
  [1, 2, 3, 4].each_cons(2) do |pair|
    attempts += 1
    if pair[0] == 2 && attempts < 5
      redo
    end
    puts "pair=#{pair.inspect} attempt=#{attempts}"
  end
  puts "total=#{attempts}"
end
t_each_cons
