# RedoNode coverage — `redo` re-runs the current iteration of the
# enclosing loop without re-evaluating the guard or advancing the
# iterator. Each loop form handles `redo` on its own, so the tests
# cover every loop form.
#
# Per-section `def t_<form>; ...; end; t_<form>` isolates the
# `attempts` / `i` / `x` locals.


def t_each_with_object
  attempts = 0
  result = [1, 2, 3].each_with_object([]) do |x, acc|
    attempts += 1
    if x == 2 && attempts < 5
      redo
    end
    acc << x * 10
  end
  puts result.inspect
  puts "total=#{attempts}"
end
t_each_with_object
