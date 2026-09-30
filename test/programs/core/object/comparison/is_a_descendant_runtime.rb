# Static-vs-runtime class lattice for `is_a?` / `kind_of?` /
# `instance_of?` when the recv's static type is a parent class but
# the runtime instance can be any descendant. The answer comes from
# the runtime class of the instance, not from the static type.
#
# `is_a?` / `kind_of?` walk the ancestors; `instance_of?` uses exact
# equality.

class Animal
end
class Dog < Animal
end
class Cat < Animal
end
class Puppy < Dog
end

# is_a? / kind_of? — recv typed Animal, target a proper descendant.
def kind(a)
  if a.is_a?(Dog)
    "dog"
  elsif a.kind_of?(Cat)
    "cat"
  else
    "animal"
  end
end

puts kind(Dog.new)      # dog
puts kind(Cat.new)      # cat
puts kind(Animal.new)   # animal
puts kind(Puppy.new)    # dog (Puppy is_a? Dog)

# instance_of? — recv typed Animal, target a proper descendant.
def exact_is_dog(a)
  a.instance_of?(Dog)
end

puts exact_is_dog(Dog.new)      # true  — runtime class matches Dog
puts exact_is_dog(Puppy.new)    # false — Puppy is_a? Dog but not instance_of? Dog
puts exact_is_dog(Cat.new)      # false — unrelated descendant
puts exact_is_dog(Animal.new)   # false — runtime class is Animal, not Dog

# instance_of? — recv typed Animal, target IS the static type.
# A parent-typed local holding a descendant fails this.
def exact_is_animal(a)
  a.instance_of?(Animal)
end

puts exact_is_animal(Animal.new)  # true  — runtime class matches Animal
puts exact_is_animal(Dog.new)     # false — runtime class is Dog, not Animal
puts exact_is_animal(Puppy.new)   # false — runtime class is Puppy
