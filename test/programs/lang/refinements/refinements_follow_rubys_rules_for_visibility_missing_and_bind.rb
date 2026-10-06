# A refinement's `public :m` finds the refined class's private m; refine
# refuses a Proc passed with &; a refined method_missing answers no
# miss; a refined protected method may be called on another instance;
# a refinement's method binds only to an instance of the refined class.
def t(name)
  puts "#{name}: #{yield.inspect}"
rescue Exception => e
  puts "#{name}: #{e.class}: #{e.message.gsub(/0x\h+/, "0xADDR")}"
end
class Cow
  private
  def moo = "Moo"
end
module PublicCows
  refine(Cow) { public :moo }
end
using PublicCows
t("public in refine") { Cow.new.moo }
t("refine with proc") { Module.new { refine(String, &Proc.new {}) } }
class Foo; end
module Bar
  refine(Foo) { def method_missing(*) = "refined" }
end
using Bar
t("refined method_missing") { Foo.new.foo }
class CC; end
module R
  refine CC do
    protected
    def foo = :foo
  end
end
class CC
  using R
  def call_foo_on(other) = other.foo
end
t("refined protected") { CC.new.call_foo_on(CC.new) }
a = Class.new { def foo = self.class }
holder = Module.new
r = nil
holder.module_eval { r = refine(a) { def foo = super } }
t("bind other class") { r.instance_method(:foo).bind(Object.new) }
t("bind refined class") { r.instance_method(:foo).bind(a.new).call == a }
t("bound owner") { r.instance_method(:foo).bind(a.new).owner == r }
