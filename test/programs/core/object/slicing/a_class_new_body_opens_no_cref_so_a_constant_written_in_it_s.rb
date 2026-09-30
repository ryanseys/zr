# A class built at runtime runs its body as a block, and its directives
# become self-sends. `tests/runtime_class_body_directives.rb` shows that for
# `Class.new do ... end`.
#
# A class with a runtime SUPERCLASS must also do these five things, in both
# spellings:
#
#   CLASS METHODS are inherited: `Class.new(Base).retired` finds the
#   `def self.retired` of Base.
#
#   PREPEND puts the module first in `ancestors`, and the module's method
#   also takes over dispatch.
#
#   `private :m` that names a method of the same body makes that method
#   private. The same is true for `private_class_method`, on the singleton.
#
#   `class << self; undef x; end` removes the class method `x`.
#
#   A CONSTANT written in a `class Sub < expr` body belongs to the new class,
#   also in a nested `class Inner`. A bare READ of it finds it both in the
#   body and in a `def` of the class.
#
# Only the `class` KEYWORD spelling opens a cref. `Class.new do NAME = v end`
# is a plain block whose cref is the enclosing one, so ruby writes the constant
# on `Object` there -- checked at the bottom.

class Base
  def size = 1
  def self.retired = :retired
end

module Front
  def size = "front(#{super})"
end

def parent_of(x) = x ? Base : Object

# --- `Class.new do ... end` opens NO cref -------------------------------------
Blocky = Class.new do
  BLOCK_LEVEL = :block_level
  def reads_it = BLOCK_LEVEL
end
p Blocky.new.reads_it
p Object.const_defined?(:BLOCK_LEVEL, false)
p Blocky.const_defined?(:BLOCK_LEVEL, false)
