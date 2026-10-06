# copy_stream hands a destination that is not an IO its chunks as binary
# Strings, and a copy that the destination keeps stays as it was.
require "tempfile"
dst = Class.new do
  def initialize(&block) = @block = block
  def write(data)
    @block.call(data.dup)
    data.bytesize
  end
end
body = Tempfile.new("copy", binmode: true)
body.write(Random.new(42).bytes(16_385))
body.rewind
payload = []
IO.copy_stream(body, dst.new { payload << it })
body.rewind
all = body.read
p payload.map(&:bytesize)
p payload.map(&:encoding).uniq
p all == payload.join
body.close!

r, w = IO.pipe
w.write("héllo")
w.close
got = []
IO.copy_stream(r, dst.new { got << it })
p got, got.map(&:encoding)
