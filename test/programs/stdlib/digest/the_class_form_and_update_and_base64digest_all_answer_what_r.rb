require "digest"
puts Digest::SHA256.hexdigest("abc")
puts Digest::MD5.hexdigest("")
d = Digest::SHA256.new
d << "a"; d.update("bc")
puts d.hexdigest
puts Digest::SHA256.base64digest("abc")
