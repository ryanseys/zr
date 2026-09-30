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

# --- `class Sub < <expr>` ----------------------------------------------------
class Sub < parent_of(true)
  OPEN = :visible

  def size = 2
  def wide = :wide
  def self.internal = :internal
  def self.own_retired = :own_retired
  def reads_open = OPEN
  def self.reads_open = OPEN
  def builds_inner = Inner.new.a
  SEEN_IN_BODY = OPEN

  prepend Front
  private :wide
  private_class_method :internal

  class << self
    undef own_retired
  end

  class Inner
    def a = :a
  end
end

p Sub.new.size
p [Sub.new.respond_to?(:wide), Sub.new.respond_to?(:wide, true)]
p Sub.singleton_class.private_method_defined?(:internal)
p Sub.respond_to?(:own_retired)
p Sub::OPEN
p Sub::Inner.new.a
p Sub.retired
p Sub.new.reads_open
p Sub.reads_open
p Sub.new.builds_inner
p Sub::SEEN_IN_BODY
p Object.const_defined?(:OPEN, false)

