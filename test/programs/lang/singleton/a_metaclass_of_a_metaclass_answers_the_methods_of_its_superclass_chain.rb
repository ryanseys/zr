# The singleton class of a singleton class has the singleton classes of
# Class's chain as ancestors, so it answers their methods.
class Foo; end
class Bar < Foo; end

class << Object
  class << self
    def metaclass_method_o = :o
  end
end

class << Module.singleton_class
  def metaclass_method_m = :m
end

meta = Class.singleton_class.singleton_class
p meta.superclass.equal?(Module.singleton_class.singleton_class)

metameta = Bar.singleton_class.singleton_class
p metameta.metaclass_method_o
p metameta.metaclass_method_m
p Class.singleton_class.metaclass_method_o
p metameta.singleton_class.ancestors.take(8)
