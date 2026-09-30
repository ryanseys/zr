# A partial read takes what one read(2) gives rather than waiting for
# the whole length, which is why a reader of a pipe does not stop until
# the writer closes it. Beside it: ungetc of an Integer puts that
# codepoint back, absolute_path leaves a leading tilde where
# expand_path spells it out, and dirname refuses a negative level.
require "tmpdir"

def t = yield rescue [$!.class, $!.message]

r, w = IO.pipe
w.write "x"
p r.readpartial(100)
w.write "yz"
p r.sysread(100)
p r.readpartial(0)
w.close
p t { r.readpartial(10) }
r.close

Dir.mktmpdir do |dir|
  path = File.join(dir, "note.txt")
  File.write(path, "hello\n")
  File.open(path) do |f|
    p f.getc
    p f.ungetc(65)
    p f.read
  end
  File.open(path) do |f|
    f.getc
    f.ungetbyte(66)
    p f.read
  end
end

p File.absolute_path("~").end_with?("/~")
p File.absolute_path?("~")
p File.expand_path("~").start_with?("/")
p t { File.dirname("a/b", -1) }
p File.dirname("a/b/c", 2)
p File.dirname("a/b/c", 0)
p File.dirname("/a/b", 5)

