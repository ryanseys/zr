# `super(name)` binds the parent's own parameter names. Here parent and
# child deliberately use different names (`name` vs. `name, breed`), so
# the test passes only when `super(name)` binds Animal's own `name`.

class Animal
  def initialize(name)
    @name = name
  end
  def name
    @name
  end
end

class Dog < Animal
  def initialize(name, breed)
    super(name)
    @breed = breed
  end
  def breed
    @breed
  end
end

d = Dog.new("Rex", "Lab")
puts d.name
puts d.breed
