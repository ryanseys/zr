# A nested class or module IS a constant of the enclosing one. So `constants`
# lists the nested modules and classes as well as the value constants.
module Layout
  WIDTH = 24
  module Border
    def self.wrap(text) = "|#{text}|"
  end
  class Frame
    def initialize(n) = @n = n
    def n = @n
  end
  HEIGHT = 8
end
p Layout.constants.sort
p Layout::Border.wrap("x")
p Layout::Frame.new(2).n

module OnlyNested
  module A; end
  module B; end
end
p OnlyNested.constants.sort

module OnlyValues
  X = 1
  Y = 2
end
p OnlyValues.constants.sort

module Empty; end
p Empty.constants

class Holder
  INNER = 3
  class Deep
    DEEPER = 4
  end
end
p Holder.constants.sort
p Holder::Deep.constants.sort
