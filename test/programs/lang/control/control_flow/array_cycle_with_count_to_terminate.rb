# RedoNode coverage — `redo` re-runs the current iteration of the
# enclosing loop without re-evaluating the guard or advancing the
# iterator. Each loop form handles `redo` on its own, so the tests
# cover every loop form.
#
# Per-section `def t_<form>; ...; end; t_<form>` isolates the
# `attempts` / `i` / `x` locals.


def t_cycle
  attempts = 0
  [1, 2].cycle(2) do |x|
    attempts += 1
    if x == 1 && attempts < 3
      redo
    end
    puts "x=#{x} attempt=#{attempts}"
  end
  puts "total=#{attempts}"
end
t_cycle
