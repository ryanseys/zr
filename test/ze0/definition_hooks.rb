# frozen_string_literal: true

# ruby announces every definition to the class it landed on, at the
# definition's own position. ze0 installs a declared `def` before the
# program runs, so the announcement is made where the statement stands
# instead -- through a probe, which is one atomic load when nothing
# hooks it.

class Watched
  def self.method_added(name) = puts("added #{name}")

  def one = 1
  def two = 2
end

# A reopen announces to the same hook.
class Watched
  def three = 3
end

# The hook sees a HALF-built class: the methods below the definition are
# still in the future.
class Ordered
  def self.method_added(name)
    puts "#{name} sees #{instance_methods(false).sort.inspect}"
  end

  def a = 1
  def b = 2
  def c = 3
end

# A `def self.x` announces through the singleton hook instead.
class Singly
  def self.singleton_method_added(name) = puts("singleton #{name}")

  def self.made = :made
  def plain = :plain
end

# The other two definition hooks a class body can carry.
module Mixin
  def self.included(base) = puts("included in #{base}")
  def self.extended(base) = puts("extended #{base.class}")
end

class User
  include Mixin
end

Object.new.extend(Mixin)

class Parent
  def self.inherited(child) = puts("inherited by #{child}")
end

class Child < Parent; end

p Watched.instance_methods(false).sort
__END__
added one
added two
added three
a sees [:a]
b sees [:a, :b]
c sees [:a, :b, :c]
singleton singleton_method_added
singleton made
included in User
extended Object
inherited by Child
[:one, :three, :two]
