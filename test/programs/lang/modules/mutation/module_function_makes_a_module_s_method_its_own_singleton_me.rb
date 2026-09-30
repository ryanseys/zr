class Animal
  def speak
    "generic"
  end
end

module Utility
  def self.triple(x)
    x * 3
  end
end
puts Utility.triple(4)

