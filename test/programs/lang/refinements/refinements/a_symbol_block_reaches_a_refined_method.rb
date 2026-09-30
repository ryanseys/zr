module RS
  refine(String) { def shout = upcase + "!" }
  refine(Integer) { def to_s = "R" }
end
using RS
p %w[a b].map(&:shout)
p [1, 2].map(&:to_s)
pr = :shout.to_proc
p pr.call("c")
