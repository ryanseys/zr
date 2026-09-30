# Dynamic is_a?(klass), where the klass argument is a Class value in a
# local variable, not a constant. The hierarchy check runs at run time
# against the class that the variable holds.
#
# Coverage:
#   - A Dog receiver with a superclass held in a local.
#   - The same receiver with an unrelated class.
#   - The same receiver with a module held in a local.

module Trainable
end

class Animal
end

class Dog < Animal
  include Trainable
end

class Cat < Animal
end

d = Dog.new
animal_klass = Animal
cat_klass = Cat
trainable_klass = Trainable

puts d.is_a?(animal_klass)     ? "dog-is-animal" : "dog-not-animal"
puts d.is_a?(cat_klass)        ? "dog-is-cat"    : "dog-not-cat"
puts d.is_a?(trainable_klass)  ? "dog-trainable" : "dog-not-trainable"

c = Cat.new
puts c.is_a?(animal_klass)     ? "cat-is-animal" : "cat-not-animal"
puts c.is_a?(trainable_klass)  ? "cat-trainable" : "cat-not-trainable"
