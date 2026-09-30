class Animal
  def speak
    "generic"
  end
end

module D
  def who
    "D"
  end
end
module B
  include D
end
module C
  include D
end
class A
  include B
  include C
end
puts A.new.who
puts A.new.is_a?(D)

