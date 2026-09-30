# Test respond_to?, is_a?, class name, to_s

class T_introspect_Animal
  def initialize(name)
    @name = name
  end
  def name; @name; end
  def speak; "..."; end
end

class T_introspect_Dog < T_introspect_Animal
  def speak; "Woof!"; end
  def fetch; "ball"; end
end

d = T_introspect_Dog.new("Rex")

# is_a?
puts d.is_a?(T_introspect_Dog)      # true
puts d.is_a?(T_introspect_Animal)   # true

# respond_to?
puts d.respond_to?(:speak)   # true
puts d.respond_to?(:fetch)   # true
puts d.respond_to?(:fly)     # false

# nil?
puts nil.nil?          # true
puts d.nil?            # false
puts 0.nil?            # false

# Integer predicates
puts 0.zero?           # true
puts 5.positive?       # true
puts (-3).negative?    # true
