# `super` inside a prepended method calls the original
# (overridden) method body of the class.
module M
  def hi
    "prepend-" + super
  end
end

class C
  def hi
    "base"
  end
  prepend M
end

puts C.new.hi
