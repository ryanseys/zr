# Module methods take a name through to_str (rb_check_id), attr keeps its
# old boolean form, ruby2_keywords warns for a method it cannot flag,
# remove_method checks each name before the frozen module, autoload
# refuses an empty feature, and a literal autoload in a block compiles.
def t
  yield
rescue => e
  [e.class, e.message.sub(/0x\h+/, "X")]
end
n = Object.new
def n.to_str = "nm"
bad = Object.new
def bad.to_str = 123
c = Class.new
p t { c.send(:attr_accessor, n) }, t { c.instance_methods(false).sort }
p t { c.send(:attr_reader, bad) }, t { c.send(:attr, 1) }
cv = Object.new
def cv.to_str = "@@v"
p t { c.class_variable_set(cv, 1) }, t { c.class_variable_get(cv) }, t { c.class_variable_defined?(cv) }
k = Object.new
def k.to_str = "KONST"
p t { c.const_set(k, 5) }, t { c.send(:remove_const, k) }
p t { c.method_defined?(n) }, t { c.public_method_defined?(n) }, t { c.instance_method(n).name }
dm = Object.new
def dm.to_str = "dyn"
c.send(:define_method, dm) { 7 }
p t { c.new.dyn }
p t { c.send(:alias_method, Object.new, :nm) }
def t
  yield
rescue => e
  [e.class, e.message.sub(/0x\h+/, "X")]
end
$stderr = $stdout
class V
  private
  attr :a
  attr_reader :b
  attr_writer :c
  attr_accessor :d
end
p V.private_instance_methods(false).sort
c = Class.new
$VERBOSE = true
p t { c.send(:attr, :e, true) }, t { c.send(:attr, :f, false) }
$VERBOSE = false
p c.instance_methods(false).sort
p t { Module.new.autoload(:X, "") }
m = Module.new
m.module_eval { def kw(**k) = k; def post(*a, b) = a; def nosplat(a) = a; def good(*a) = a }
$VERBOSE = true
%i[kw post nosplat good].each { |n| p t { m.send(:ruby2_keywords, n) } }
p t { m.send(:ruby2_keywords, :not_existing) }
$VERBOSE = false
f = Module.new.freeze
p t { f.send(:remove_method).equal?(f) }, t { f.send(:remove_method, 1) }
