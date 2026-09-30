# RedoNode coverage — `redo` re-runs the current iteration of the
# enclosing loop without re-evaluating the guard or advancing the
# iterator. Each loop form handles `redo` on its own, so the tests
# cover every loop form.
#
# Per-section `def t_<form>; ...; end; t_<form>` isolates the
# `attempts` / `i` / `x` locals.


def t_each_slice
  attempts = 0
  [1, 2, 3, 4, 5].each_slice(2) do |chunk|
    attempts += 1
    if chunk[0] == 3 && attempts < 5
      redo
    end
    puts "chunk=#{chunk.inspect} attempt=#{attempts}"
  end
  puts "total=#{attempts}"
end
t_each_slice
