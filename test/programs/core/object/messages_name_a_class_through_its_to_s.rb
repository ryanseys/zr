# A FrozenError and clone's freeze: error name the object's class through
# the class's own to_s, as a C format's %PRIsVALUE writes it.
labeled = Class.new do
  singleton_class.class_eval do
    define_method(:to_s) { "C\u{30c6 30b9 30c8}" }
    alias_method :inspect, :to_s
    alias_method :name, :to_s
  end
  attr_accessor :foo
end
begin
  labeled.new.freeze.foo = 1
rescue FrozenError => e
  p e.message.gsub(/0x\h+/, "0xADDR")
end
begin
  Object.new.clone(freeze: labeled.new)
rescue ArgumentError => e
  p e.message
end
o = Object.new
def o.x = nil
o.freeze
begin
  o.instance_variable_set(:@a, 1)
rescue FrozenError => e
  p e.message.gsub(/0x\h+/, "0xADDR")
end
