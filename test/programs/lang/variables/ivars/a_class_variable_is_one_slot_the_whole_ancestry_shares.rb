# A class variable belongs to the class its source is written in, and the
# storage is ONE slot the whole ancestry shares.
class Counter
  @@total = 0
  @@names = []

  def self.total = @@total

  def initialize(name)
    @@total += 1
    @@names << name
  end

  def seen = @@names.dup
end

Counter.new("a")
Counter.new("b")
p Counter.total
p Counter.new("c").seen
p Counter.class_variables.sort
p Counter.class_variable_get(:@@total)

# A method written in a SUBCLASS reaches the superclass's slot, because
# that is where ruby's own lookup stops.
class Sub < Counter
  def self.bump = @@total += 10
  def self.peek = @@total
end

Sub.bump
p Counter.total
p Sub.peek
p Sub.class_variables.sort

# `||=` is the one read that tolerates a name nobody assigned.
class Lazy
  def self.memo = @@memo ||= :made
  def self.again = @@memo
end
p Lazy.memo
p Lazy.memo
p Lazy.again

# Every other read of one raises.
class Missing
  def self.peek = @@never

  def self.bumped
    @@nope += 1
  end
end

[-> { Missing.peek }, -> { Missing.bumped }].each do |go|
  go.call
rescue NameError => e
  p e.message
end

# A module's class variables are its own.
module Tally
  @@hits = 0

  def self.hit = @@hits += 1
  def self.hits = @@hits
end

Tally.hit
Tally.hit
p Tally.hits
p Tally.class_variables

# A write answers the value assigned, and reaches the same slot from a
# class body as from a method.
class Direct
  @@here = :body

  def self.set(v)
    @@here = v
  end

  def self.here = @@here
end
p Direct.here
p Direct.set(:method)
p Direct.here
