# frozen_string_literal: true

# `class Foo < <expr>` mints its class while the program runs, so no row
# can carry it: the name is an ordinary constant holding what
# `Class.new` answers, and the body's `def`s install where they stand.

base = Struct.new(:a, :b)

class Pair < base
  def sum = a + b
end

p Pair.new(1, 2).sum
p Pair.name
p Pair.superclass == base
p Pair.ancestors.include?(Struct)

# A superclass NAME the program assigns is the same thing: only the run
# time knows what it holds.
Parent = Class.new do
  def hi = :hi
end

class Kid < Parent
  def kid = :kid
end

p Kid.new.hi, Kid.new.kid, Kid.name, Kid.superclass == Parent

# Nested, and the constant is what names the class.
module Wrap
  Inner = Class.new

  class Deep < Inner
    def go = :deep
  end
end

p Wrap::Deep.new.go, Wrap::Deep.name

# The hook fires, because `Class.new` fires it -- but during the mint,
# where ruby fires it after the constant has named the class, so the
# child is still anonymous there. `zeo build` desugars the same way and
# answers the same.
Watcher = Class.new do
  def self.inherited(child) = puts("inherited: #{child.equal?(child)}")
end

class Seen < Watcher; end

p Seen.superclass == Watcher, Seen.name

# A later statement REOPENS what the first one made: there is still no
# row to put the body's `def`s in, so the body runs on the constant.
class Kid
  def second = :second
end

p Kid.new.kid, Kid.new.second

# A `rescue` binds into a class variable or a scoped constant as
# readily as into a local.
class Holder
  @@last = nil

  def self.run
    raise "held"
  rescue => @@last
    @@last.message
  end
end

p Holder.run

# A subclass of a class made at run time is made at run time too: its
# parent has no row, so neither can it, however ordinary the `class`
# statement looks.
class Grand < Kid
  def grand = :grand
end

p Grand.new.grand, Grand.new.kid, Grand.superclass == Kid, Grand.name

# The shape rspec's `FailedExampleNotification` has: a `Struct.new`
# subclass with its own ivars, subclassed again.
Row = Struct.new(:value)

class Tagged < Row
  def initialize(value, tag = "t#{value}")
    @tag = tag
    super(value)
  end

  def show = [@tag, value]
end

class Retagged < Tagged
  def show2 = show + [self.class.name]
end

p Tagged.new(1).show
p Retagged.new(2).show2
p Retagged.new(3).instance_variables
__END__
3
"Pair"
true
true
:hi
:kid
"Kid"
true
:deep
"Wrap::Deep"
inherited: true
true
"Seen"
:kid
:second
"held"
:grand
:kid
true
"Grand"
["t1", 1]
["t2", 2, "Retagged"]
[:@tag]
