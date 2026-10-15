# ruby lists a class's own constants in the slot order of its ID table,
# which follows each name's symbol serial, so a name that the interpreter
# made earlier (such as :A) can come before names defined before it. zr
# lists them in the order they were defined.
class Base
  ZETA = 1
  ALPHA = 2
  SO_FAR = constants
  A = 3
end

class Sub < Base
  B = 4
end

p Base.constants
p Base::SO_FAR
p Sub.constants
