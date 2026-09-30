# A subclass inherits a prepended method correctly. D inherits hi
# from C; D.new.hi dispatches to C's prepended hi (M's body), and
# super walks back to C's original body.
module M
  def hi
    "M(" + super + ")"
  end
end

class C
  def hi
    "c"
  end
  prepend M
end

class D < C
end

puts D.new.hi
