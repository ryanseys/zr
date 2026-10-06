# binmode drops the newline decorators: what a character read has not
# reached reads raw. An open checks its text and binary modes before
# it opens, and an encoding name that is not ASCII is an error.
require "tmpdir"
def try = yield rescue $!
Dir.chdir(Dir.mktmpdir)
File.binwrite("t.txt", "a\r\nb\r\nc\r\n")
File.open("t.txt", "rt") do |f|
  p f.getc, f.getc
  f.binmode
  p 7.times.map { f.getc }
end
File.open("t.txt", "rt:euc-jp:utf-8") do |f|
  p f.getc, f.getc
  f.binmode
  p 7.times.map { f.getc }
end
File.binwrite("u.txt", "あ\r\n")
File.open("u.txt", "rt:utf-8:euc-jp") do |f|
  f.binmode
  r = f.read
  p r, r.encoding
end
p try { open("not-exist", "r", textmode: true, binmode: true) }
p try { open("not-exist", "rt", binmode: true) }
p try { open("not-exist", "rt", binmode: false) }
p try { open("not-exist", "rb", textmode: true) }
p try { open("not-exist", "rb", textmode: false) }
p try { IO.pipe("UTF-8", "UTF-8".encode("UTF-32BE")) }
p try { IO.pipe("UTF-8".encode("UTF-32BE")) }
p try { open("t.txt", "rt") { |f| f.set_encoding("iso-2022-jp") } }
p try { open("t.txt", "r") { |f| f.binmode; f.set_encoding("iso-2022-jp"); f.external_encoding } }
p try { open("t.txt", "rt") { |f| f.binmode; f.set_encoding("iso-2022-jp"); f.external_encoding } }
p try { open("t.txt", "r", binmode: true) { |f| [f.external_encoding, f.set_encoding("iso-2022-jp")] && :ok } }
p try { open("t.txt", "rb", binmode: true) { |f| f.set_encoding("iso-2022-jp") } }
