# pp asks io/console for the width under a `rescue LoadError`, so a
# wide structure prints whether or not a console library is present.
require "pp"
pp({alpha: "x" * 60, beta: (1..30).to_a, gamma: {delta: "y" * 40, epsilon: [:a, :b, :c]}})
