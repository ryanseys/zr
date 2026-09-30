# super (bare or with explicit args) gives the Child param types to
# the Parent params, so Parent gets the real values, not Integers.
class Parent
  def greet(name)
    puts "Parent: #{name}"
  end
end

class Child < Parent
  def greet(name)
    super
    puts "Child: #{name}"
  end
end

class Echo < Parent
  def greet(name)
    super(name)
    puts "Echo done"
  end
end

Child.new.greet("Alice")
Echo.new.greet("Bob")
