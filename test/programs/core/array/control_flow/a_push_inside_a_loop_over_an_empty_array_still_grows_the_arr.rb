# An empty array literal followed by a `<<` push inside a loop,
# where the pushed value goes through an intermediate variable.
# The array holds the pushed objects:
#
#   def make
#     results = []
#     i = 0
#     while i < 3
#       instance = Foo.new
#       results << instance        # ← intermediate var
#       i += 1
#     end
#     results
#   end
#
# Three combinations:
#
#   - direct push (`results << Foo.new`)
#   - intermediate var, no loop
#   - intermediate var INSIDE loop
#
# Coverage:
#   - the Rails-style `_adapter_all` shape,
#   - a String-array variant,
#   - a baseline direct-push variant.

class Foo
  attr_accessor :v
  def initialize
    @v = 0
  end
end

def make_with_intermediate
  results = []
  i = 0
  while i < 3
    instance = Foo.new
    results << instance
    i += 1
  end
  results
end

a = make_with_intermediate
puts a.length                   # 3

