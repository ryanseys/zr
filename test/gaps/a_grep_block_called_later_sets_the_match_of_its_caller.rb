# A block that Enumerable#grep gives to each, called after grep returned,
# sets $~ in the frame that called grep, as an ifunc's svar does. zr
# keeps that match in the block's own frame, so the caller's $1 is nil.
c = Class.new do
  include Enumerable
  def each(&b) = @b = b
  def run = @b.call("foo")
end
obj = c.new
result = nil
obj.grep(/(f..)/) { result = $1 }
obj.run
p result, $1
