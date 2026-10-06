# Every built-in CLASS can be subclassed, `OpenSSL::X509::Certificate`
# too (eleven gems subclass it). A DENYLIST names each built-in whose
# subclass is a different native shape. Every other subclass is a payload
# wrapper.
#
# What made the default safe is that both halves it needs are generic. A
# root with no empty form keeps a `nil` payload and the subclass's own
# `initialize` seats the real one through `super` (the `File` shape), and a
# root with no constructor at all answers instead of crashing.
require "openssl"
require "digest"
require "zlib"

class Cert < OpenSSL::X509::Certificate
  def label = "cert"
end
p [Cert.new.label, Cert.superclass, Cert.new.is_a?(OpenSSL::X509::Certificate)]

class Fingerprint < Digest::MD5
  def label = "md5"
end
p [Fingerprint.new.label, Fingerprint.new.is_a?(Digest::MD5)]

class Squeezer < Zlib::Deflate
  def label = "deflate"
end
p [Squeezer.new.label, Squeezer.superclass]

# A root with no argument-free form: the definition registers, and the
# subclass's own `initialize` seats the payload through `super`.
class Signer < OpenSSL::HMAC
  def initialize(key)
    super(key, OpenSSL::Digest.new("SHA256"))
  end

  def label = "hmac"
end
signer = Signer.new("secret")
p [signer.label, signer.is_a?(OpenSSL::HMAC), signer.update("x").hexdigest.length]

# A subclass that seats its payload through `super` gets the real thing, and
# the inherited methods run against it.
class Loud < String
  def initialize(text)
    super(text.upcase)
  end

  def label = "loud"
end
loud = Loud.new("hi")
p [loud, loud.label, loud.length, loud.class, loud.is_a?(String)]

# The denylist's own shapes still behave the way each of them must.
class Point < Struct.new(:x, :y); end
p [Point.new(1, 2).x, Point.superclass.superclass]

class Tally < Integer; end
p Tally.superclass

# ...and the two superclasses ruby ITSELF refuses, refused with ruby's own
# message rather than a compile error naming zr.
begin
  class WantsClass < Class
  end
rescue TypeError => e
  p [e.class, e.message]
end
begin
  class WantsModule < Comparable
  end
rescue TypeError => e
  p [e.class, e.message]
end

