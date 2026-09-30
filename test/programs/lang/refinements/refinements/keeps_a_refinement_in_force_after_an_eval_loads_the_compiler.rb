# A program that evals carries the compiler, and the compiler loads
# on the first eval, running each of its own files. Several of them
# activate a refinement as they load -- the prism port reaches its
# node writers through one. A `using` fills a row the compiler
# numbered, so the rows a program holds and the rows its road holds
# must not be the same rows, or the first eval takes this
# program's refinement back off.
module Tripler
  refine Integer do
    def trip = self * 3
  end
end

using Tripler
p 7.trip

n = ARGV.size + 1
p eval("#{n} + 1")
p 7.trip
p [1, 2].map { |x| x.trip }
