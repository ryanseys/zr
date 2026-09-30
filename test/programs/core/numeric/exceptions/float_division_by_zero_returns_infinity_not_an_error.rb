# `ZeroDivisionError` is only for Integer division. In Ruby, a
# Float divided by 0 gives `Infinity`/`-Infinity`/`NaN` (IEEE
# semantics), and never raises an exception.

puts(1.0 / 0.0); puts(-1.0 / 0.0)
