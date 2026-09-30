# frozen_string_literal: true

# A class row registers its shape before the first statement runs, so
# the MRO is static, but ruby makes the CONSTANT where the `class`
# statement stands. Until then the name is a NameError.

p defined?(Later)

class Later
  def go = :later
end

p defined?(Later)
p Later.new.go

# A nested name appears when the body that writes it runs, not when the
# enclosing class does.
module Outer
  p defined?(Inner)
  class Inner
    def go = :inner
  end
  p defined?(Inner)
end
p Outer::Inner.new.go

# A subclass names its superclass at the statement, so the order the
# file writes them is the order they appear.
class Parent; end
class Child < Parent; end
p Child.superclass
