# singleton_method finds the singleton class's own methods and those of
# the modules it prepends or that extend the object, not a superclass's
# singleton methods. super_method of a class with a prepended module is
# the parent's method. define_singleton_method makes a public method even
# under `private`.
def t(name)
  puts "#{name}: #{yield.inspect}"
rescue NameError => e
  puts "#{name}: #{e.class}: #{e.message.gsub(/0x\h+/, "0xADDR")}"
end
sc = Class.new { def t = :t }
c = Class.new(sc) do
  singleton_class.prepend(Module.new { def bar = :bar })
  extend(Module.new { def quux = :quux })
  def self.baz = :baz
end
%i[bar baz quux t].each { |name| t(name) { c.singleton_method(name).call } }
c2 = Class.new(c)
%i[bar baz quux].each { |name| t("subclass #{name}") { c2.singleton_method(name) } }
m = Module.new do
  extend self
  def foo = :foo
end
t("extend self") { m.singleton_method(:foo).call }
c1 = Class.new { def m; end }
c3 = Class.new(c1) { def m; end }
c3.prepend(Module.new)
sup = c3.instance_method(:m).super_method
t("super_method") { [sup == c1.instance_method(:m), sup.owner == c1] }
O = Object.new
class << O
  private
  O.define_singleton_method(:dsm) { :dsm }
  def O.d = :d
end
t("define_singleton_method") { O.dsm }
t("def O.d") { O.d }
