# frozen_string_literal: true

# `class << self` opens the class's SINGLETON, which is a class in its own
# right: a constant written there belongs to it and not to the class, the
# class methods beside it read the constant through the cref, and
# `Module.nesting` reports it. So the body gets a row of its own, named
# `#<Class:Owner>` -- a name no Ruby constant can collide with. Only the
# runtime mints a singleton, so the row names the class it is the
# singleton of and the backend ties the two.

class Config
  class << self
    PREFIX = "cfg:"
    LIMIT = 3

    def key(n) = "#{PREFIX}#{n}"
    def capped(n) = n > LIMIT ? LIMIT : n
    def nesting = Module.nesting.map(&:to_s)
  end
end

p Config.key("host")
p Config.capped(9)
p Config.nesting
p Config.const_defined?(:PREFIX, false)
p Config.singleton_class.const_defined?(:PREFIX, false)
p Config.singleton_class.constants(false).sort

# A second body reopens the SAME singleton, so its constants join the
# first body's, and a class method written OUTSIDE cannot reach them by
# bare name.
class Config
  class << self
    SUFFIX = "!"

    def both = [PREFIX, SUFFIX]
  end

  def self.blind
    PREFIX
  rescue NameError
    :name_error
  end
end

p Config.both
p Config.blind

# The surrogate sits in the full lexical chain, so a body in `A::B` reads
# A's constants -- and the enclosing scope's are shadowed by its own.
module A
  ROOT = :a_const
  SHADOWED = :from_module

  module B
    class << self
      INNER = :inner
      SHADOWED = :from_singleton

      def chain = [INNER, ROOT, SHADOWED]
      def nest = Module.nesting.map(&:to_s)
    end
  end
end

p A::B.chain
p A::B.nest

# The surrogate is the body's DEFINEE too, so a `def` written in a block
# here installs on the singleton, which is where ruby installs it.
class Late
  class << self
    def install
      [1].each { def inner = :inner }
      :installed
    end
  end
end

p Late.install
p Late.singleton_methods(false).sort
p Late.inner

# A `class` written here belongs to the singleton too -- `class X` IS a
# constant write with a body -- and a `class << self` beside it opens the
# surrogate's own singleton, the same construct one level deeper.
module Color
  class << self
    class Visitor
      def initialize(name) = @name = name
      def render = "<#{@name}>"
    end

    class << self
      SUFFIX = "!"
      def shout(s) = s + SUFFIX
    end

    def paint(name) = Visitor.new(name).render
  end
end

p Color.paint("red")
p Color.singleton_class.shout("hi")
p Color.singleton_class.const_defined?(:Visitor)
p Color.constants
p Color.singleton_class.singleton_class.const_defined?(:SUFFIX)

# `def self.x` here defines on the singleton's OWN singleton, one level
# further up than a bare `def`.
class MetaHost
  class << self
    def plain = "plain"
    def self.meta = "meta"
  end
end

p MetaHost.plain
p(begin; MetaHost.meta; rescue NoMethodError; :no_such_method; end)
p MetaHost.singleton_class.meta

# The body has a backtrace frame of its own, labelled `singleton class`,
# and its own locals, shared across the whole of it.
begin
  class Walked
    class << self
      step = 1
      total = step + 1
      raise "at #{total}"
    end
  end
rescue RuntimeError => e
  p [e.message, e.backtrace.first[/:\d+:in '.*'/]]
end

# A `class << obj` on any other receiver keeps the per-object road: its
# `def`s are singleton methods of that object.
target = Object.new
class << target
  def only_mine = :mine
end
p target.only_mine
p target.singleton_methods
