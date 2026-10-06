# The encoding option `BOM|UTF-8` strips the mark as in a mode string,
# and an internal encoding that repeats the given external one stays, so
# a UTF-16 or UTF-32 mark still converts to it.
require "tmpdir"
Dir.chdir(Dir.mktmpdir)
def try = yield rescue $!
%w[UTF-8 UTF-16BE UTF-16LE UTF-32BE UTF-32LE].each do |name|
  path = "#{name}-bom.txt"
  File.binwrite(path, "﻿Āa".encode(name))
  r = File.read(path, mode: "rb:BOM|UTF-8")
  p [name, r.encoding, r.b]
  %w[rb rt r].each do |mode|
    r = try { File.read(path, mode: "#{mode}:BOM|UTF-8:UTF-8") }
    p [mode, r.is_a?(String) ? [r.encoding, r] : r]
  end
end
File.binwrite("u.txt", "﻿a")
p File.read("u.txt", encoding: "BOM|UTF-8").b
File.binwrite("v.txt", "﻿a\xff".b)
r = File.read("v.txt", encoding: "BOM|UTF-8")
p r, r.valid_encoding?
r = File.read("v.txt", encoding: "BOM|UTF-8:UTF-8")
p r, r.valid_encoding?
$stderr = $stdout
open(IO::NULL, "r:bom|us-ascii") { |f| p f.external_encoding }
open(IO::NULL, "r", encoding: "bom|us-ascii") { |f| p f.external_encoding }
