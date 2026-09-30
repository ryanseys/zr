# `U` (marshal_dump/marshal_load) and `u` (_dump/self._load) drive
# serialization through user methods; both round-trip through allocate +
# the hook.

def wire(x) = Marshal.dump(x).bytes.join(",")
def rt(x) = Marshal.load(Marshal.dump(x))
class UBox
  def initialize(v = nil) = (@v = v)
  attr_reader :v
  def marshal_dump = [@v, 7]
  def marshal_load(a) = (@v = a[0])
end
puts wire(UBox.new(5))
p rt(UBox.new("payload")).v
class LilEndian
  def initialize(n = 0) = (@n = n)
  attr_reader :n
  def _dump(depth) = [@n].pack("N")
  def self._load(s) = new(s.unpack1("N"))
end
puts wire(LilEndian.new(258))
p rt(LilEndian.new(65535)).n
