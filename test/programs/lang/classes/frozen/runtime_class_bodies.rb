# frozen_string_literal: true

# A class made at run time has no row, so nothing written in its body can
# be keyed by a compile-time id: a constant, a nested class, a class
# variable and the reads of each go through the class VALUE instead.
# `self` IS that class inside the body; a `def` reaches it through the
# constant that names it, which is bound by the time any method can run.

def base = Object

class Foo < base
  VAL = 7

  include Comparable

  class Inner
    def deep = "deep"
  end

  @@count = 0

  def initialize = @@count += 1
  def a = VAL
  def use_inner = Inner.new.deep
  def self.count = @@count
end

p Foo::VAL
p Foo.new.a
p Foo.new.use_inner
p Foo::Inner.new.deep
p Foo.count
p Foo.ancestors.take(3)

# `< self` from inside a subclass body names THAT subclass, all the way
# down, and each nested class belongs to the class the body is building.
class Base
  def kind = :base

  class Middle < self
    def kind = :middle

    class Leaf < self
      def kind = :leaf
    end
  end
end

p Base::Middle::Leaf.ancestors.take(3)
p [Base.new.kind, Base::Middle.new.kind, Base::Middle::Leaf.new.kind]

# A NAMESPACE the run time decides: `class self::Task` writes onto
# whichever object `self` is, so no scope this compile can name is
# involved at all.
module Holder
  def self.build(&blk) = class_eval(&blk)
end

Holder.build do
  class self::Task
    def run = "ran"
  end

  module self::Helpers
    def self.tag = :helper
  end

  class self::Timed < self::Task
    def run = "timed " + super
  end
end
p Holder::Task.new.run
p Holder::Helpers.tag
p Holder::Timed.new.run
p Holder::Timed.superclass == Holder::Task

# A reopened builtin is the same shape: its row is the runtime's, so the
# body's constants and class variables take the same road.
class Array
  LIMIT = 3
  @@made = 0

  def self.note = @@made += 1
  def capped = size > LIMIT ? LIMIT : size
end

p Array::LIMIT
p [1, 2, 3, 4].capped
p Array.note
p defined?(Array::LIMIT)
