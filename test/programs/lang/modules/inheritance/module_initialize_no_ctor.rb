# A module's `def initialize` runs when an includer is constructed, and the
# module itself has no `new`: `M.new` is a NoMethodError in Ruby.
module Outer
  module Buffering
    def initialize
      @eof = false
      @rbuffer = "".dup
      @sync = false
    end

    def eof?
      @eof
    end

    def buf
      @rbuffer
    end
  end
end

class Sock
  include Outer::Buffering

  def initialize
    super
    @extra = 1
  end

  def extra
    @extra
  end
end

class Plain
  include Outer::Buffering
end

s = Sock.new
p s.eof?
p s.buf
p s.extra

q = Plain.new
p q.eof?
p q.buf

begin
  Outer::Buffering.new
rescue NoMethodError
  puts "NoMethodError"
end
