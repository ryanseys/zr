# Inflate#add_dictionary keeps a dictionary by its Adler-32 checksum, and
# an inflate that needs one finds it there, as rb_inflate_add_dictionary
# and zstream_run_try do. A stream that has none raises Zlib::NeedDict.
require "zlib"

deflate = Zlib::Deflate.new
deflate.set_dictionary "foo"
compressed = deflate.deflate "foofoofoo", Zlib::FINISH
deflate.close

inflate = Zlib::Inflate.new
p inflate.instance_variables
p inflate.add_dictionary("foo").equal?(inflate)
p inflate.add_dictionary("bar").instance_variable_get(:@dictionaries).keys.sort
p inflate.inflate(compressed)
begin
  Zlib::Inflate.new.inflate(compressed)
rescue Zlib::NeedDict => e
  p e
end
other = Zlib::Inflate.new
other.add_dictionary("bar")
p((other.inflate(compressed) rescue $!))
