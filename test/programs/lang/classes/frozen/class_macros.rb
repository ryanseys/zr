# frozen_string_literal: true

# The `Module` verbs a class body calls to change what the class is.
# zr answers `module_function` at compile time, because the rows it
# writes exist before the body runs; the rest are ordinary sends to the
# class the body is opening.

module Sums
  module_function

  def double(n) = n * 2

  def quadruple(n) = double(double(n))
end

p Sums.double(3), Sums.quadruple(3)
p Sums.singleton_methods.sort
p Sums.private_instance_methods(false).sort

# The mixin half: an includer gets the same methods, privately.
class Adder
  include Sums

  def twice(n) = double(n)
end

p Adder.new.twice(5)

begin
  Adder.new.double(1)
rescue NoMethodError => e
  p e.message
end

# The positional form names `def`s already written above it, and answers
# the names it took.
module Mixed
  def kept = :kept
  def moved = :moved
  def also = :also

  module_function :moved
  module_function :also, :kept
end

p Mixed.moved, Mixed.also, Mixed.kept
p Mixed.public_instance_methods(false)

# `private_class_method` and its twin retag a class method where they
# stand.
class Vault
  def self.open = :open

  def self.combination = :s3cret
  private_class_method :combination

  def self.peek = combination
end

p Vault.open, Vault.peek

begin
  Vault.combination
rescue NoMethodError => e
  p e.message
end

p Vault.singleton_class.private_instance_methods(false)
p Vault.private_instance_methods(false)

class Vault
  public_class_method :combination
end
p Vault.combination

# `define_method` installs a block as a method, and the block still
# reads the names around it.
class Greeter
  %w[morning evening].each do |part|
    define_method("good_#{part}") { "good #{part}" }
  end

  define_method(:shape) { |a, b = 2, *rest| [a, b, rest] }
end

p Greeter.new.good_morning, Greeter.new.good_evening
p Greeter.new.shape(1), Greeter.new.shape(1, 5, 6)
p Greeter.instance_method(:shape).parameters
p Greeter.instance_methods(false).sort

# The rest are plain sends: the runtime does the work, at the position
# the statement stands.
class Trimmed
  def gone = :gone
  def kept = :kept
  remove_method :gone
  const_set(:LIMIT, 7)
end

p Trimmed.new.kept, Trimmed::LIMIT

begin
  Trimmed.new.gone
rescue NoMethodError => e
  p e.message
end

class Base
  def shadowed = :base
end

class Blank < Base
  undef_method :shadowed
end

p Base.new.shadowed

begin
  Blank.new.shadowed
rescue NoMethodError => e
  p e.message
end

# `class_eval` and `instance_eval` take a block, whose `def` lands on
# whatever the receiver opens.
class Late
  def already = :already
end

Late.class_eval do
  def added = :added
  def reaches = already
end

p Late.new.added, Late.new.reaches

one = Object.new
one.instance_eval do
  @held = 9

  def mine = :mine
end

p one.mine, one.singleton_methods, one.instance_variable_get(:@held)
p [1, 2, 3].instance_eval { size }
