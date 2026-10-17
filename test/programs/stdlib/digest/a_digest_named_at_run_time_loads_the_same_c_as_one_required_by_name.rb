# Digest() and Digest::X require their library by a name built at run
# time. With digest's own C linked, every algorithm is that C, whether a
# literal require or a computed one loads it, and the compiler that a
# computed require starts uses it too.
require "digest"
require "digest/sha1"

p Digest::SHA1.hexdigest("abc")
p Digest(:SHA256).hexdigest("abc")[0, 16], Digest(:SHA384).new.update("a").hexdigest[0, 16]
p Digest::MD5.base64digest("x"), Digest::RMD160.hexdigest("")[0, 16]
p Digest::SHA256.new.block_length, Digest::SHA512.new.digest_length
d = Digest::SHA256.new
d << "ab"
e = d.dup
e << "c"
p d.hexdigest == Digest::SHA256.hexdigest("ab"), e == Digest::SHA256.new.update("abc")
p Digest::SHA1.file(__FILE__).hexdigest == Digest::SHA1.hexdigest(File.binread(__FILE__))
p eval("Digest::SHA256.hexdigest('z')")[0, 8]
p $LOADED_FEATURES.grep(/digest/).map { |path| File.basename(path) }.sort
