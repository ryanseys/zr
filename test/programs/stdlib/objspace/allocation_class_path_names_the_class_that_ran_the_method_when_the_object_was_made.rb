# ObjectSpace.allocation_class_path names the class of the method that
# made the object, as that class was named then: one def that runs under
# two classes gives each class, a class that is named or frozen later
# keeps what it was, and each call gives a new binary String.
require "objspace"

class P1; def m = "P1"; end
class P2; def m = "P2"; end

# One def site, defined on two classes.
children = [P1, P2].map do |parent|
  Class.new(parent) do
    def make = Object.new
    def make_in_block = [1].map { Object.new }.first

    def m
      [super, defined?(super), caller_locations(0, 1)[0].label]
    end

    def traced
      events = []
      tp = TracePoint.new(:call) { |t| events << [t.defined_class, t.method_id] }
      tp.enable { helper }
      events
    end

    def helper = :h
  end
end
C1, C2 = children

module Maker
  def made = Object.new
end

class WithModule
  include Maker
  def self.make = Object.new
end

anonymous = Class.new { def make = Object.new }
FrozenLater = Class.new { def make = Object.new }
FrozenAtOnce = Class.new { def make = Object.new }

ObjectSpace.trace_object_allocations_start
objects = {
  "C1#make" => C1.new.make,
  "C2#make" => C2.new.make,
  "C1 block" => C1.new.make_in_block,
  "C2 block" => C2.new.make_in_block,
  "module method" => WithModule.new.made,
  "singleton method" => WithModule.make,
  "anonymous, named later" => anonymous.new.make,
  "frozen later" => FrozenLater.new.make
}
FrozenAtOnce.freeze
objects["frozen at once"] = FrozenAtOnce.new.make
top_level = Object.new
ObjectSpace.trace_object_allocations_stop

NamedLater = anonymous
FrozenLater.freeze

objects.each do |label, object|
  puts "#{label}: #{ObjectSpace.allocation_class_path(object).inspect} #{ObjectSpace.allocation_method_id(object).inspect}"
end
puts "top level: #{ObjectSpace.allocation_class_path(top_level).inspect} #{ObjectSpace.allocation_method_id(top_level).inspect}"

path = ObjectSpace.allocation_class_path(objects["C2#make"])
again = ObjectSpace.allocation_class_path(objects["C2#make"])
puts "path: #{path.encoding} frozen=#{path.frozen?} new each time=#{!path.equal?(again)} name kept=#{!path.equal?(C2.name)}"

# The path outlives a collection.
GC.start
puts "after GC: #{ObjectSpace.allocation_class_path(objects["C1#make"]).inspect}"

# The other readers of the method's class.
[C1, C2].each do |c|
  puts "#{c}: #{c.new.m.inspect} #{c.new.traced.inspect}"
end
