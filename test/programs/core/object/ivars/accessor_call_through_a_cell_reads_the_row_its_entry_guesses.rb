# An accessor whose receiver's class this body does not know: the call goes
# through the site's cell to the runtime's own reader and writer, which read
# and write the row the entry guesses.
class A
  attr_accessor :x
  def initialize = (@p = 1; @x = 2)
end

class B
  attr_accessor :x
  def initialize = (@q = 1; @r = 2; @x = 3)
end

def read(o) = o.x
def write(o, v) = (o.x = v)

a = A.new
b = B.new
# One site, two classes, and `x` sits at a different row in each, so the
# guess is right for one receiver and wrong for the other, every call.
p [read(a), read(b), read(a), read(b)]
p [write(a, 10), write(b, 20)]
p [read(a), read(b)]

# A reader whose ivar was never set.
class N
  attr_reader :n
end
p N.new.n

# A writer that makes the row it writes.
class M
  attr_writer :m
  def peek = @m
end
m = M.new
p(m.m = 5)
p m.peek

# A class object as the receiver: its ivars are the class's own, not a plain
# object's table.
class S
  class << self
    attr_accessor :s
  end
end
def read_s(o) = o.s
S.s = 7
p [read_s(S), read_s(S)]

# A frozen receiver refuses the write at the caller's line, and still reads.
f = A.new.freeze
begin
  write(f, 1)
rescue FrozenError => e
  puts e.message.sub(/0x[0-9a-f]+/, "0xADDR")
end
p read(f)

# A row removed leaves the guess naming a row that no longer holds the name.
a.send(:remove_instance_variable, :@x)
p [read(a), read(b)]

# A String subclass is not a plain object, so the runtime's own read answers.
class Str < String
  attr_accessor :tag
end
def read_tag(o) = o.tag
def write_tag(o, v) = (o.tag = v)
s = Str.new("hi")
p [write_tag(s, :ok), read_tag(s), s.length]

# Through send, and through a Method object.
p [b.send(:x), b.method(:x).call]

# The arity an accessor does not take, and a redefinition the cell must see.
def read1(o) = o.x(1)
p(begin; read1(b); rescue ArgumentError => e; e.message; end)
class A
  def x = "redefined"
end
p [read(a), read(b)]
