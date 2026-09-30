# RedoNode coverage — `redo` re-runs the current iteration of the
# enclosing loop without re-evaluating the guard or advancing the
# iterator. Each loop form handles `redo` on its own, so the tests
# cover every loop form.
#
# Per-section `def t_<form>; ...; end; t_<form>` isolates the
# `attempts` / `i` / `x` locals.


def t_zip
  attempts = 0
  [1, 2, 3].zip([10, 20, 30]) do |a, b|
    attempts += 1
    if a == 2 && attempts < 5
      redo
    end
    puts "a=#{a} b=#{b} attempt=#{attempts}"
  end
  puts "total=#{attempts}"
end
t_zip
