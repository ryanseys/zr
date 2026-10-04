# A singleton class's own class is the singleton class of the object's
# class, and a metaclass's is the metaclass of Class at its level, so
# each answers the methods ruby finds there.
class A; end
class K; def self.example_class_method = 1; def example_instance_method = 2; end
class Class
  def example_instance_method_of_class = 3
  def self.example_class_method_of_class = 4
end
class << Class
  def example_instance_method_of_singleton_class = 5
  def self.example_class_method_of_singleton_class = 6
end
ec = A.singleton_class
p ec.kind_of?(Class.singleton_class)
ecec = ec.singleton_class
p ecec.kind_of?(Class.singleton_class.singleton_class), ecec.kind_of?(Class.singleton_class)
p K.new.singleton_class.respond_to?(:example_class_method)
a_c_sc = A.singleton_class
p a_c_sc.respond_to?(:example_class_method_of_class)
p a_c_sc.respond_to?(:example_instance_method_of_singleton_class)
p a_c_sc.singleton_class.respond_to?(:example_instance_method_of_singleton_class)
p a_c_sc.singleton_class.respond_to?(:example_class_method_of_singleton_class)
p K.new.singleton_class.example_class_method rescue p $!
class D
  class << self
    class << self
      def ham = "iberico"
    end
  end
end
p (D.singleton_class.ham rescue $!)
o = Object.new
class << o; CONST = 1; end
o2 = o.clone
class << o2; p CONST; end
p ec.ancestors.first(4)
p ecec.superclass, ec.superclass, ecec.class
