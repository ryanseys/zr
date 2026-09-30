# A `class << self` body holding a CONSTANT must still let a bare
# `super` inside one of its methods resolve correctly. faker's
# `Faker::Base` is this shape.

class Parent
  def self.describe(prefix)
    "#{prefix}:parent"
  end
end

class Child < Parent
  class << self
    NOT_GIVEN = Object.new

    def describe(prefix)
      "#{super}+child"
    end
  end
end

p Child.describe("x")
p Parent.describe("x")
p Child.singleton_class.const_get(:NOT_GIVEN).class
