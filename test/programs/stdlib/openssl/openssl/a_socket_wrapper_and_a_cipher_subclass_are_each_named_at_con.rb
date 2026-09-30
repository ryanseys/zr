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

# A socket wrapper, and a cipher: both named at construction, both the same
# shape.
class Wrapped < OpenSSL::SSL::SSLSocket
  def wrapped? = true
end

p Wrapped.superclass
p Wrapped.new.wrapped? rescue p :needs_a_socket

class Loud < OpenSSL::Cipher
  def shout = "LOUD"
end

p Loud.superclass
c = Loud.new("aes-256-cbc")
p c.class
p c.shout
p c.name
p c.is_a?(OpenSSL::Cipher)

class Named2 < OpenSSL::Digest
  def label = "#{name} digest"
end

d = Named2.new("SHA256")
p Named2.superclass
p d.class
p d.label
p d.hexdigest("abc")

