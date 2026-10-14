# A FrozenError names the receiver's real class, never an overridden
# `class`, and carries the receiver, as rb_error_frozen_object does.
class MyRandom < Random
  def class = String
end

class MyEnumerator < Enumerator
  def class = String
end

def show(target)
  yield
rescue FrozenError => e
  puts e.message.gsub(/0x\h+/, "0x")
  p e.receiver.equal?(target)
end

r = MyRandom.new(1).freeze
show(r) { r.send(:initialize, 2) }

e = MyEnumerator.new { |y| y << 1 }.freeze
show(e) { e.send(:initialize) { |y| y << 2 } }

buffer = "x".freeze
show(buffer) { [65].pack("C", buffer: buffer) }

out = "".freeze
show(out) { Encoding::Converter.new("UTF-8", "UTF-16LE").primitive_convert(+"a", out) }

require "date"
class MyDate < Date; end
d = MyDate.new(2026, 1, 2).freeze
show(d) { d.send(:initialize_copy, Date.new(2001, 2, 3)) }
show(d) { d.marshal_load(Date.new(2001, 2, 3).marshal_dump) }
