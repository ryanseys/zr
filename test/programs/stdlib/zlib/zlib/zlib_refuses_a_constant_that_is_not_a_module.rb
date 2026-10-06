# rb_define_module("Zlib") names the class of what the constant holds.
Zlib = 42
begin
  require "zlib"
rescue TypeError => e
  p e.message
end
Zlib = nil
begin
  require "zlib"
rescue TypeError => e
  p e.message
end
