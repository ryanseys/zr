# In a method, a block that class_eval or Class.new runs has a scope of
# its own, so a bare `private` or `protected` there applies to the defs
# that follow it. A def in a plain block in a method, or in a
# define_method body, is public.
def build
  c = Class.new
  c.class_eval do
    protected
    def prot = :prot
    private
    def priv = :priv
  end
  d = Class.new do
    private
    def hidden = :hidden
  end
  [c, d]
end

c, d = build
p c.protected_instance_methods(false), c.private_instance_methods(false)
p d.private_instance_methods(false)

e = Class.new
def plain(klass)
  [1].each { klass.send(:define_method, :x) { 1 } }
  [1].each do
    klass.class_eval { def via_eval = 1 }
  end
end
plain(e)
p e.public_instance_methods(false).sort

f = Class.new do
  define_method(:maker) do
    def made = :made
  end
end
f.new.maker
p f.public_instance_methods(false).sort
