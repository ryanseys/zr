# Two constant-resolution rules rubygems and bundler lean on all through their
# compatibility shims.
#
# 1. `if defined?(Const)` gates a whole definition. Whether the constant exists
#    is fixed for a whole-program target, so the branch is decided at compile
#    time -- and registration and emission have to decide it the SAME way, or a
#    class reaches codegen with nothing registered behind it.
# 2. A `::`-anchored path names the top level and nothing else, including when
#    the definition it names comes LATER in the flattened program.

# A `::`-anchored name that shadows a same-named constant in scope.
COLOUR = :top_level
module Shadow
  COLOUR = :nested
  def self.here = COLOUR
  def self.rooted = ::COLOUR
end
p Shadow.here, Shadow.rooted
