# A user class inheriting a native type has no struct of its own: its instances
# wrap the real native value as a payload and carry their own ivars beside it.
# `Queue` has a real empty form, so `super()` builds one; nothing in the IO
# family does -- no descriptor, peer or algorithm can be conjured -- so those
# subclasses seat the real payload through `super`, which is the whole reason
# gems subclass them.
#
# actionpool's `Queue < ::Queue`, kgio's `Kgio::Pipe < IO`, dalli's
# `TCP < TCPSocket`, and the `SSLSocket < OpenSSL::SSL::SSLSocket` that bunny,
# dalli and mongo each write -- the largest single subclassing bucket in the
# gem corpus.

require "socket"
require "openssl"
require "tmpdir"

# `Fiber` is `Thread`'s shape: the block IS the body, so `super(&block)` is the
# only way to seat one. hexapdf's `FiberWithLength` records a length it knows
# before the fiber runs.
class Measured < Fiber
  def initialize(length, &block)
    super(&block)
    @length = length || -1
  end

  attr_reader :length
end

f = Measured.new(3) { Fiber.yield(:a); Fiber.yield(:b); :done }
p Measured.superclass
p f.class
p f.length
p f.resume
p f.resume
p f.resume
p f.alive?

