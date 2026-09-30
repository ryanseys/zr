require "zlib"
puts Zlib.crc32("abc")
puts Zlib.adler32("abc")
puts Zlib.crc32("abc", 100)
