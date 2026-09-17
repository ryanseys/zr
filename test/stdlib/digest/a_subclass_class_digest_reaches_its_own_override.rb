# Digest::Class.hexdigest sends `digest` to the class it was called on,
# so a subclass that redefines the class method `digest` is reached,
# as OpenSSL::Digest.hexdigest("SHA1", data) needs. A class method the
# core library sends by name went to the core's own row whenever the
# receiver was a class's singleton class.
require "digest"

class Tagged < Digest::Class
  def initialize(tag = "none")
    super()
    @tag = tag
  end

  def digest(data) = "#{@tag}:#{data}"

  def self.digest(tag, data)
    super(data, tag)
  end
end

p Tagged.digest("sha", "abc")
p Tagged.hexdigest("sha", "abc")
p Digest::SHA256.hexdigest("abc")[0, 16]

class Plain < Digest::Class
  def digest(data) = data.reverse
end
p Plain.hexdigest("abc")

__END__
"sha:abc"
"7368613a616263"
"ba7816bf8f01cfea"
"636261"
