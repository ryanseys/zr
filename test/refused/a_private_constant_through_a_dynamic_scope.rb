# a private constant read through a scope this program cannot name
class C
  X = 1
  private_constant :X
end
k = C
p k::X
