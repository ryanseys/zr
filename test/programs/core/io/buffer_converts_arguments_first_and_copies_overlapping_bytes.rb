# IO::Buffer converts an argument before it checks the buffer, copies
# bytes that overlap as memmove does, and refuses a write to a frozen
# String. A write of no bytes to a null buffer does nothing.
$VERBOSE = nil

def show
  p yield
rescue StandardError => e
  p [e.class, e.message]
end

show { IO::Buffer.map("foobar") }
show { IO::Buffer.for(Object.new) }

buffer = IO::Buffer.new(128)
show { buffer.get_string(0, 129) }
show { buffer.get_string(129) }
show { buffer.get_string(-1) }

freeing = Struct.new(:buffer) do
  def to_int
    buffer.free
    0x41
  end

  def to_str
    buffer.free
    "BINARY"
  end
end
slice = buffer.slice(0, 8)
show { slice.set_value(:U8, 0, freeing.new(buffer)) }
other = IO::Buffer.new(16)
show { other.slice(0, 8).get_string(0, 8, freeing.new(other)) }

text = +"0123456789"
IO::Buffer.for(text) { |window| window.set_string(text, 3, 7) }
p text

null = IO::Buffer.new(0)
show { null.copy(IO::Buffer.for("a"), 0, 0) }
show { null.set_string("a", 0, 0) }
show { null.set_string("a", 0, 1) }

hello = %w[Hello World].join(" ")
moved = IO::Buffer.for(hello, &:transfer)
moved.set_string("Ciao!")
p hello
hello.freeze
show { moved.set_string("Hola") }
