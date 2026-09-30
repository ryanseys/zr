# RedoNode coverage — `redo` re-runs the current iteration of the
# enclosing loop without re-evaluating the guard or advancing the
# iterator. Each loop form handles `redo` on its own, so the tests
# cover every loop form.
#
# Per-section `def t_<form>; ...; end; t_<form>` isolates the
# `attempts` / `i` / `x` locals.


def t_each
  attempts = 0
  [10, 20, 30].each do |x|
    attempts += 1
    if x == 20 && attempts < 5
      redo
    end
    puts "x=#{x} attempt=#{attempts}"
  end
  puts "total=#{attempts}"
end
t_each
