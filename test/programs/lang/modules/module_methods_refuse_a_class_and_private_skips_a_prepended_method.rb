# Methods of Module that only a module runs refuse a Class they were bound
# to. A singleton method does not move to another class. private and
# public search from the origin, so a prepended module's method stays.
%i[append_features prepend_features extend_object].each do |m|
  p((Module.instance_method(m).bind(Class.new).call(Module.new) rescue $!.message))
end
p((Module.instance_method(:module_function).bind(Class.new).call rescue $!.message))
c = Class.new { class << self; def foo = 1; end }
p((Class.new { define_method :bar, c.method(:foo) } rescue $!.message))
p((Class.new { define_method :bar, c.method(:foo).unbind } rescue $!.message))
wrapper = Module.new { def wrapped = super + 1 }
klass = Class.new do
  prepend wrapper
  def wrapped = 1
  private :wrapped
end
p klass.new.wrapped, klass.private_instance_methods(false).include?(:wrapped)
