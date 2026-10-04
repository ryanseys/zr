# Kernel#autoload in a method whose self is not a module declares the
# name on the module that the method is in, as rb_f_autoload reads the
# lexical class.
module M
  def setup = autoload(:Later, "/no/such/later.rb")
end
class C
  include M
end
p C.new.setup
p M.autoload?(:Later), M.const_defined?(:Later), C.autoload?(:Later)
