# ruby loads bundled_gems before the first line, and its
# LoadError#message reads the path with String#tr: for a path with a byte
# that is no character, #message raises ArgumentError, and an uncaught
# LoadError shows only its class.
begin
  require "\xff"
rescue LoadError => e
  p((e.message rescue $!))
  p e.path.valid_encoding?
end
p LoadError.new("no path").message
begin
  require "no/such/file"
rescue LoadError => e
  p e.message
end
require "\xff"
