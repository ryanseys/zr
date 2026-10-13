# tell and flush on a stream that reads text drop the characters that
# ungetc put back, so getbyte goes on from the bytes after them. An
# allocated IO that has no descriptor raises IOError "uninitialized stream"
# for print, its encodings and reopen.
require "tmpdir"

def try(label)
  p [label, yield]
rescue => e
  p [label, e.class, e.message]
end

Dir.mktmpdir do |dir|
  path = File.join(dir, "text.txt")
  File.write(path, "foo\nbar\n")
  %i[tell pos flush].each do |m|
    File.open(path, "rt") do |f|
      f.getc
      f.ungetc("a")
      f.send(m)
      try(m) { [f.getbyte, f.getbyte, f.read] }
    end
  end
  File.open(path, "rt") do |f|
    f.getc
    f.ungetc("xyz")
    try(:getc_without_tell) { [f.getc, f.read(2)] }
  end
  File.open(path, "rt") do |f|
    f.ungetc("ab")
    p f.tell
    try(:after_tell) { [f.getc, f.getbyte] }
  end
  File.open(path, "rb") do |f|
    f.getc
    f.ungetc("a")
    f.tell
    try(:binary_keeps) { [f.getbyte, f.getbyte] }
  end
end

try(:print) { IO.allocate.print "" }
try(:external) { IO.allocate.external_encoding }
try(:internal) { IO.allocate.internal_encoding }
try(:reopen_path) { IO.allocate.reopen(__FILE__) }
try(:reopen_null) { IO.allocate.reopen(IO::NULL) }
try(:reopen_io) { IO.allocate.reopen($stdin) }
try(:closed) { IO.allocate.closed? }
