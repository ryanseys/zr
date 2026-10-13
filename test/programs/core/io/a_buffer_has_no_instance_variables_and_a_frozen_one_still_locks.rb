# An IO::Buffer keeps its state as ruby's C struct does: no instance
# variables, and freeze does not lock it, so a frozen buffer still locks.
# The methods that change a buffer refuse a frozen one, and a copy has
# state of its own.
Warning[:experimental] = false

def show(label)
  puts "#{label}: #{yield.inspect}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message.lines.first.chomp.gsub(/0x\h+/, "0xX")}"
end

storage = IO::Buffer.new(4)
slice = storage.slice(1, 2)
show("storage ivars") { storage.instance_variables }
show("slice ivars") { slice.instance_variables }
show("for ivars") { IO::Buffer.for("text").instance_variables }
show("ivar set") { storage.instance_variable_set(:@mine, 1); storage.instance_variables }

frozen = IO::Buffer.new(4).freeze
show("frozen locked") { frozen.locked { frozen.locked? } }
show("frozen after") { frozen.locked? }
show("frozen slice locks") { frozen.slice(0, 2).locked { frozen.locked? } }
show("frozen free") { frozen.free }
show("frozen resize") { frozen.resize(8) }
show("frozen transfer") { frozen.transfer }
show("frozen set") { frozen.set_value(:U8, 0, 1) }
show("frozen read") { frozen.get_value(:U8, 0) }
show("frozen size") { frozen.size }

original = IO::Buffer.new(4)
original.set_string("abcd")
copy = original.dup
copy.set_string("WXYZ")
show("dup own bytes") { [original.get_string, copy.get_string] }
copy.resize(2)
show("dup own size") { [original.size, copy.size] }
original.locked { show("dup own lock") { [original.locked?, copy.locked?] } }
view = original.slice(1, 2)
view_copy = view.dup
view_copy.resize(1)
show("slice dup own range") { [view.size, view_copy.size, view_copy.get_string] }
clone = original.clone(freeze: true)
show("frozen clone") { [clone.frozen?, clone.get_string, clone.locked { clone.locked? }] }
show("moved") { moved = original.transfer; [original.null?, moved.get_string, moved.instance_variables] }
