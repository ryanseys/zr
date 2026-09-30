# RedoNode coverage — `redo` re-runs the current iteration of the
# enclosing loop without re-evaluating the guard or advancing the
# iterator. Each loop form handles `redo` on its own, so the tests
# cover every loop form.
#
# Per-section `def t_<form>; ...; end; t_<form>` isolates the
# `attempts` / `i` / `x` locals.


def t_nested
  inner_attempts = 0
  outer_done = 0
  i = 0
  while i < 2
    outer_done += 1
    3.times do |j|
      inner_attempts += 1
      if i == 0 && j == 1 && inner_attempts < 4
        redo
      end
      puts "i=#{i} j=#{j} attempt=#{inner_attempts}"
    end
    i += 1
  end
  puts "outer_done=#{outer_done}"
  puts "inner_attempts=#{inner_attempts}"
end
t_nested
