# Test inheritance and super

class T_inherit_Animal
  def initialize(name)
    @name = name
  end

  def name
    @name
  end

  def speak
    "..."
  end

  def describe
    name
  end
end

class T_inherit_Dog < T_inherit_Animal
  def initialize(name, breed)
    super(name)
    @breed = breed
  end

  def breed
    @breed
  end

  def speak
    "Woof!"
  end
end

class T_inherit_Cat < T_inherit_Animal
  def speak
    "Meow!"
  end
end

# Basic inheritance
dog = T_inherit_Dog.new("Rex", "Labrador")
puts dog.name       # Rex (inherited)
puts dog.breed      # Labrador
puts dog.speak      # Woof! (overridden)
puts dog.describe   # Rex (inherited, calls name)

cat = T_inherit_Cat.new("Whiskers")
puts cat.name       # Whiskers (inherited)
puts cat.speak      # Meow! (overridden)
puts cat.describe   # Whiskers (inherited)
