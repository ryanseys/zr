# A user-class `each` that yields Strings. The block param `k` takes
# the type of the value that the method body yields, here a String.
# The body reads ivars of its own class to build that value.

class C
  def initialize
    @keys = []
    @keys << "alpha"
    @keys << "beta"
  end

  def each
    i = 0
    while i < @keys.length
      k = @keys[i]
      yield k
      i += 1
    end
    self
  end
end

c = C.new
c.each { |k| puts k }
