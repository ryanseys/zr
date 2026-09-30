# `module_function` in a REOPENED module body. A module first named by a
# version file and then filled in (the shape every gem has) gets module
# functions, so `M.helper(x)` works.
module M
  VERSION = "1"
end
module M
  module_function
  def valid?(x)
    !x.nil?
  end
  def twice(x)
    x * 2
  end
end
module M
  def named(x)
    "n#{x}"
  end
  module_function :named
end
p M.valid?("a")
p M.twice(3)
p M.named(1)
p M::VERSION

module N
  def self.direct = 1
end
module N
  module_function
  def mf = 2
end
p [N.direct, N.mf]

class Includer
  include M
  def call_it = valid?("z")
end
p Includer.new.call_it
