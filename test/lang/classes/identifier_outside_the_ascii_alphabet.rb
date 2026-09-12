# Ruby treats every byte above ASCII as an identifier byte, so this ivar is
# legal (fastimage ships one). A generated identifier takes a narrower
# alphabet, so such a name must be mangled rather than passed through.

@width, @height´ = nil
@height´ = 7
p [@width, @height´]

# A class-level ivar named after a compiler keyword takes an escaped
# spelling, which then has to survive being upper-cased into a global's name.
class Shape
  def self.type = @type
  def self.type=(v)
    @type = v
  end
end
Shape.type = "circle"
p Shape.type
__END__
[nil, 7]
"circle"
