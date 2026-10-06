# The digest extension links: the hash is computed by native code in the
# binary.
require "digest"
puts Digest::SHA256.hexdigest("zr")
puts Digest::MD5.hexdigest("")
d = Digest::SHA1.new
d << "a"
d << "b"
puts d.hexdigest
