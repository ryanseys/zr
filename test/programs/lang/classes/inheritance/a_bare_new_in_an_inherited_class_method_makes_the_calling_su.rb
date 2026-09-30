# A bare `new` in an inherited class method makes an instance of the
# subclass that calls it, not of the parent class that defines the
# method. `Article.create` runs the body of `Base.create`, and its
# `new` calls the constructor of Article.

# Basic: bare `new`, no args.
class Base
  def self.create
    new
  end
end

class Article < Base
  def initialize
    @x = "hello"
  end
  def x; @x; end
end

puts Article.create.x                  # hello

# Variant: a bare `new(attrs)` gives the Hash argument to the
# `initialize` of Article2.
class Base2
  def self.create(attrs)
    instance = new(attrs)
    instance
  end
end

class Article2 < Base2
  def initialize(attrs)
    @title = attrs[:title]
  end
  def title; @title; end
end

puts Article2.create({title: "hello"}).title     # hello

# Multi-level: bare `new` resolves to the leaf class.
class Mid < Base; end
class Deep < Mid
  def initialize
    @x = "deep"
  end
  def x; @x; end
end
puts Deep.create.x                     # deep

# A second call runs the body of Base2.create again.
puts Article2.create({title: "world"}).title     # world
