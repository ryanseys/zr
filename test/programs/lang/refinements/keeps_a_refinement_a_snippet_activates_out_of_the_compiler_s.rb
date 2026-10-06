# The other way round: a snippet numbers rows too, and it is
# compiled while the program runs, so its rows have to start after
# every row the program already holds. One that started from zero
# took the compiler's, and the next parse stopped inside it --
# "undefined method 'value=' for an instance of Prism::IntegerNode".
module Tripler
  refine Integer do
    def trip = self * 3
  end
end

n = ARGV.size + 1
p eval("using Tripler\n#{n}.trip")
p eval("#{n} + 2")
