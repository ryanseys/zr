# Two constant-resolution rules rubygems and bundler lean on all through their
# compatibility shims.
#
# 1. `if defined?(Const)` gates a whole definition. Whether the constant exists
#    is fixed for a whole-program target, so the branch is decided at compile
#    time -- and registration and emission have to decide it the SAME way, or a
#    class reaches codegen with nothing registered behind it.
# 2. A `::`-anchored path names the top level and nothing else, including when
#    the definition it names comes LATER in the flattened program.

# A VALUE constant, not a class: `resolve_class` has nothing to say about it,
# so the const registry has to be consulted too.
class Holder
  LIMIT = 7
  def known = defined?(LIMIT)
  def unknown = defined?(NO_SUCH_LIMIT)
end
p Holder.new.known, Holder.new.unknown
module Namespaced
  SIZE = 2
  def self.known = defined?(SIZE)
end
p Namespaced.known
p defined?(Holder::LIMIT)
p defined?(Holder::MISSING)

