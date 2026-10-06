module RS
  refine(Integer) { def to_s = "R" }
end
def run = yield
p 5.to_s
run { using RS }
p 5.to_s
