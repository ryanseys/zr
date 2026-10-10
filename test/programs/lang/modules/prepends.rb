module Loud
  def speak = "LOUD " + super
  def only_loud = :loud
end
module Polite
  def speak = "please, " + super
end
class Animal
  def speak = "..."
  def name = "animal"
end
class Dog < Animal
  prepend Loud
  def speak = "woof"
  def name = "dog"
end
p Dog.new.speak, Dog.ancestors.first(3), Dog.new.name, Dog.new.only_loud
p Dog.instance_methods(false).sort, Dog.instance_method(:speak).owner, Dog.new.method(:speak).owner
class Dog
  prepend Polite
end
p Dog.new.speak, Dog.ancestors.first(4)
class Dog
  def speak = "WOOF"
end
p Dog.new.speak, Dog.superclass, Dog.instance_method(:only_loud).owner
p Dog.include?(Loud), Dog.new.is_a?(Loud), Loud === Dog.new, Dog < Loud
module Tracked
  def self.prepended(base) = puts "prepended to #{base}"
end
class Dog; prepend Tracked; end
p Dog.ancestors.first(5)
class Cat < Dog
  def speak = "meow " + super
end
p Cat.new.speak, Cat.ancestors.first(5)
module Twice
  def speak = super + super
end
Cat.prepend(Twice)
p Cat.new.speak
def (o = Dog.new).speak = "solo"
p o.speak, o.singleton_class.ancestors.first(2).map(&:to_s).last
begin
  raise "x"
rescue => e
  p e.backtrace.size
end
module Raiser
  def boom = raise("from prepended")
end
class Dog; prepend Raiser; end
begin
  Dog.new.boom
rescue => e
  puts e.backtrace
end
class Dog
  private def secret = 1
  alias_method :speak2, :speak
end
p Dog.private_instance_methods(false), Dog.new.speak2, Dog.new.respond_to?(:secret)
