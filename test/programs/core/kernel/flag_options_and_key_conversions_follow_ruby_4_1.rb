# Flag options take true, false or nil and refuse anything else before
# they act: system's exception: and Process.daemon's two flags (noclose is
# checked first, and the process does not fork). Kernel#inspect shows all
# instance variables of an object that has no instance_variables_to_inspect,
# as a BasicObject. Data's keys convert with to_str.
$stdout.sync = true
def try(label)
  p [label, yield]
rescue => e
  p [label, e.class, e.message]
end

try(:system_one) { system("true", exception: 1) }
try(:system_string) { system("true", exception: "true") }
try(:system_nil) { system("true", exception: nil) }
try(:daemon_first) { Process.daemon(1) }
try(:daemon_first_string) { Process.daemon("true") }
try(:daemon_second) { Process.daemon(true, 1) }
try(:daemon_both) { Process.daemon(:x, "y") }
p Process.pid == $$

o = BasicObject.new
o.instance_eval do
  @host = "localhost"
  @port = 80
end
p Kernel.instance_method(:inspect).bind_call(o).sub(/0x\h+/, "0x00")
shown = Class.new(BasicObject) do
  private

  def instance_variables_to_inspect = [:@port]
end.new
shown.instance_eval { @host = "h"; @port = 1 }
p Kernel.instance_method(:inspect).bind_call(shown).sub(/#<#<Class:0x\h+>:0x\h+/, "#<C")

class Key
  def initialize(text) = @text = text
  def to_str = @text
end
Point = Data.define(:x, :y)
pt = Point.new(1, 2)
try(:keys_converted) { pt.deconstruct_keys([Key.new("y"), :x]) }
try(:key_not_string) { pt.deconstruct_keys([Key.new(0)]) }
try(:key_none) { pt.deconstruct_keys([Class.new { def inspect = "#<thing>" }.new]) }
try(:new_converted) { Point.new(Key.new("x") => 1, y: 2) }
try(:new_unknown) { Point.new(x: 1, y: 2, Key.new("z") => 3) }
try(:new_not_string) { Point.new(Key.new(5) => 1) }
try(:new_symbol_and_string) { Point.new(x: 1, "y" => 2) }
