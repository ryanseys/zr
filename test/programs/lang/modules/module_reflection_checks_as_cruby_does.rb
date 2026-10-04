# Module: attr methods take the visibility of a Class.new block, the
# boolean form of attr warns, an alias named initialize is private,
# set_temporary_name refuses only a real constant path, a refinement
# cannot be included, and undef_method on a metaclass names the class.
def show
  p yield
rescue => e
  p [e.class, e.message]
end

c = Class.new do
  protected

  attr_reader :foo
  private

  attr_writer :bar
  attr_accessor :baz
end
show { c.new.foo }
show { c.new.bar = 1 }
show { c.new.baz }
p c.protected_instance_methods.sort, c.private_instance_methods(false).sort

Warning[:deprecated] = true
$VERBOSE = true
Class.new { attr :flag, true }
$VERBOSE = false

k = Class.new do
  def public_one = :one
  alias_method :initialize, :public_one
  alias_method :respond_to_missing?, :public_one
end
p k.private_instance_methods(false).sort

%w[name Template['foo.rb'] a::B A::b A::B:: A::::B A=].each do |name|
  m = Module.new
  m.set_temporary_name(name)
  p m.name
end
%w[Object A::B ::A ::A::B].each { |name| show { Module.new.set_temporary_name(name) } }

refinement = nil
Module.new { refine(String) { refinement = self } }
show { Module.new { include refinement } }
show { Module.new { prepend refinement } }

show { String.singleton_class.send(:undef_method, :not_exist) }
show { (+"a").singleton_class.send(:undef_method, :not_exist).class }
