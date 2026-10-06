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

# Deeper in the same family: the payload root is the NEAREST native ancestor,
# so a `TCPSocket` subclass is a TCPSocket, not the `IO` four links above it.
class Named < TCPSocket
  def initialize(host, port, name)
    super(host, port)
    @name = name
  end

  attr_reader :name
end

p Named.superclass
p Named.ancestors.include?(IO)
p Named.instance_method(:name).owner

