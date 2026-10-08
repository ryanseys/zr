# The encoding of each error message that the core makes, as ruby's C
# makes it: rb_raise's format is binary while the text is ASCII, a
# NameError's message is US-ASCII, a message that Ruby code raises is
# the source's, and a non-ASCII part makes it UTF-8.
def enc
  yield
  :no_error
rescue Exception => e
  [e.class, e.message.encoding.to_s]
end

p enc { [].fetch(5) }
p enc { Integer("zz") }
p enc { nil.foo }
p enc { raise "x" }
p enc { 1 / 0 }
p enc { {}.fetch(:a) }
p enc { Float("q") }
p enc { "a".encode("bogus") }
p enc { [1].first(-1) }
p enc { :a.unknown }
p enc { Struct.new(:a).new(1, 2) }
p enc { raise ArgumentError }
p enc { [3, "a"].sort }
p enc { File.read("/nonexistent") }
p enc { Object.new.instance_variable_get("bad") }
p enc { [1, 2].pack("z") }
p enc { "abc".center }
p enc { Hash.new(1) { } }
p enc { "x" * -1 }
p enc { Comparable.instance_method(:clamp).bind_call(3, 5, 1) }
p enc { "é".encode("US-ASCII") }
p enc { Integer.sqrt(-1) }
p enc { [].sample(-1) }
p enc { 3.round(1, half: :bogus) }
p enc { Rational(1, 0) }
p enc { Object.new.freeze.instance_variable_set(:@a, 1) }
p enc { BasicObject.new.inspect }
p enc { raise TypeError }
p enc { Kernel.Integer(nil) }
p enc { [1, 2, 3].each_slice(0) }
p enc { NoSuchConstant }
p enc { Object.const_get(:lowercase) }
p enc { require "no/such/feature" }
p enc { "abc".freeze << "d" }
p enc { [].freeze << 1 }
p enc { undefined_local_or_method }
p enc { Object.new.method(:nope) }
p enc { Class.new.instance_method(:nope) }
p enc { raise NameError, "é" }
p enc { 1.foo }
p enc { BasicObject.new.foo }
p enc { Object.new.public_send(:initialize) }
p enc { Module.new.module_function(:nope) }
p enc { Object.send(:remove_const, :Nope) }
p enc { {}.fetch("long" * 30) }
p enc { { é: 1 }.fetch(:ü) }
p enc { "é".freeze << "x" }
p enc { ["é"].fetch(9) }
p enc { raise ArgumentError, "plain" }
p enc { raise IndexError.new("made") }
# The messages still compare and print as their text.
begin
  {}.fetch(:a)
rescue KeyError => e
  p e.message == "key not found: :a", e.message + " — é", e.full_message(highlight: false).lines.first.include?("key not found")
end
