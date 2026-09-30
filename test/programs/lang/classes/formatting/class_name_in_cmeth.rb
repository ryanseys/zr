# `Class#name` (and `self.name`) inside a `def self.X` body answers
# the name of the class, a String. ActiveRecord uses it in its
# `"#{name}.table_name must be overridden"` raise pattern.

class Foo
  def self.who
    "I am #{name}"
  end
  def self.who_self
    "I am #{self.name}"
  end
end

class Bar
  def self.greet
    name + " says hi"
  end
end

puts Foo.who
puts Foo.who_self
puts Bar.greet
