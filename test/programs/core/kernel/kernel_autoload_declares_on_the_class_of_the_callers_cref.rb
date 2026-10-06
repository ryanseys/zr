# Kernel#autoload and Kernel#autoload? use the class of the caller's
# cref, as rb_f_autoload reads rb_vm_cbase. A cref that class_eval,
# Class.new or instance_eval pushed counts, and for instance_eval the
# class is the object's own class. No file is read here.
def where(name)
  [Object, A, B, C].select { |m| m.autoload?(name, false) }.map { |m| m.name || :anon }
end
class A; end
class B; end
class C; end
A.class_eval { autoload :K1, "k1" }
p [:class_eval_block, where(:K1)]
A.class_eval("autoload :K2, 'k2'")
p [:class_eval_string, where(:K2)]
B.new.instance_eval { autoload :K3, "k3" }
p [:instance_eval_block, where(:K3)]
o = C.new
o.singleton_class
o.instance_eval { autoload :K4, "k4" }
p [:instance_eval_with_singleton, where(:K4)]
anon = Class.new { autoload :K5, "k5" }
p [:class_new_block, where(:K5), anon.autoload?(:K5, false)]
m = Module.new do
  def self.go = autoload(:K6, "k6")
end
m.go
p [:module_singleton_method, where(:K6), m.autoload?(:K6, false)]
class A
  def go = autoload(:K7, "k7")
end
A.new.go
p [:method_in_class, where(:K7)]
A.define_method(:dm) { autoload(:K8, "k8") }
A.new.dm
p [:define_method, where(:K8)]
class A
  def ask = [autoload?(:K7), autoload?(:K1), autoload?(:K3)]
end
p A.new.ask
p B.new.instance_eval { [autoload?(:K3), autoload?(:K7)] }
p autoload?(:K8)
p Class.new { def go = (autoload :Object, "bogus"; autoload?(:Object)) }.then { |c| [c.new.go, c.autoload?(:Object)] }
