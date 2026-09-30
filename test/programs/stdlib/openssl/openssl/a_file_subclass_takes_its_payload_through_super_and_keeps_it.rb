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

# The `File` shape: the payload arrives through `super`, and every inherited
# method reads it. `IO.sysopen` hands over a descriptor nobody else owns.
class Tagged < IO
  def initialize(fd, tag)
    super(fd)
    @tag = tag
  end

  attr_reader :tag

  def first_line = "#{@tag}: #{gets}"
end

Dir.mktmpdir do |dir|
  path = File.join(dir, "log")
  File.write(path, "alpha\nbeta\n")
  io = Tagged.new(IO.sysopen(path), :note)
  p io.class
  p io.tag
  p io.is_a?(IO)
  p io.first_line
  p io.read
  io.close
  p io.closed?
end

p Tagged.superclass

