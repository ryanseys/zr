# A `def self.x` on an exception subclass can call a bare `new`. It makes an
# instance of the subclass, with the message it gets.

class D < StandardError
  def self.build(n)
    new("built-#{n}")
  end
end
e = D.build(3)
puts e.message
puts e.class
puts e.is_a?(StandardError)
