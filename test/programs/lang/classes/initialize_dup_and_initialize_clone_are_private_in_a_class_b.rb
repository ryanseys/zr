# initialize_dup and initialize_clone are private wherever the class
# body is, as initialize and initialize_copy are.
[1].each do
  class Copied
    def initialize_dup(other) = super
    def initialize_clone(other, freeze: nil) = super
  end
end
p [Copied.private_method_defined?(:initialize_dup), Copied.private_method_defined?(:initialize_clone)]
