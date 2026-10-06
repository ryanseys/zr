# `.nil?` on a module-singleton accessor whose value type is a
# class constant: the call must check whether the slot has been
# assigned, NOT dispatch a class method `.nil?` on the resolved
# class. This is true also when only one class can be in the slot.

class A
end

module Registry
  class << self
    attr_accessor :adapter
  end
end

def configure
  Registry.adapter = A
end

# Read paths -- .nil? checks whether the slot is set. It is not a
# class method call on A.
def check_unset
  Registry.adapter.nil?
end

def check_after_set
  configure
  Registry.adapter.nil?
end

puts check_unset ? "nil" : "set"
puts check_after_set ? "nil" : "set"
