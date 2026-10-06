# `CONST = <fallible expr>` in a class body and `def m(a = <fallible>)`
# both work: each expression is a method call that can raise.

def source
  41
end
class Config
  LIMIT = [1, 2, 3].sum
end
def bump(a = source + 1)
  a
end
puts Config::LIMIT
puts bump
puts bump(5)
