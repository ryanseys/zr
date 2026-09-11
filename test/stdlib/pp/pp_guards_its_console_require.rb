# pp asks io/console for the width under a `rescue LoadError`, so a
# wide structure prints whether or not a console library is present.
require "pp"
pp({alpha: "x" * 60, beta: (1..30).to_a, gamma: {delta: "y" * 40, epsilon: [:a, :b, :c]}})
__END__
{alpha: "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
 beta:
  [1,
   2,
   3,
   4,
   5,
   6,
   7,
   8,
   9,
   10,
   11,
   12,
   13,
   14,
   15,
   16,
   17,
   18,
   19,
   20,
   21,
   22,
   23,
   24,
   25,
   26,
   27,
   28,
   29,
   30],
 gamma:
  {delta: "yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy", epsilon: [:a, :b, :c]}}
