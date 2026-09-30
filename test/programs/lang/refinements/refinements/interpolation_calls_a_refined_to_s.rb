module RS
  refine(Integer) { def to_s = "R" }
  refine(Symbol) { def to_s = "sym" }
end
using RS
p "#{5}"
p "a#{:b}c"
p 5.to_s
