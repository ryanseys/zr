class Animal
  def speak
    "generic"
  end
end

module M1
  def label
    "m1"
  end
end
module M2
  def label
    "m2"
  end
end

class Stacked
  prepend M1
  prepend M2
  def label
    "own"
  end
end
puts Stacked.new.label

