# `IO.new(fd, mode, **opts)` -- the same mode and the same options `File.open`
# takes, and they mean the same things.
#
# zr's row was `(fd, mode?)`: the mode was READ and then dropped, no option was
# ever looked at, and a third argument was `wrong number of arguments (given 3,
# expected 1..2)`. So a handle over a descriptor always reported UTF-8 whatever
# it was asked for, and irb's
#
#   IO.open(STDOUT.to_i, 'w', external_encoding: enc, internal_encoding: "-")
#
# could not be built at all -- which is where `IRB.start` died.
require "tmpdir"
require "fileutils"

DIR = Dir.mktmpdir("zr_io_open_opts")
SRC = File.join(DIR, "src.txt")
File.binwrite(SRC, "hello\nworld\n")

# Every row gets a descriptor of its own, and whatever the row builds owns it:
# closing one fd twice is a real error, not a test detail.
def row(name, mode = "r")
  fd = IO.sysopen(SRC, mode)
  made = nil
  begin
    value, made = yield fd
    puts "#{name}\t#{value.inspect}"
  rescue StandardError => e
    puts "#{name}\t#{e.class}: #{e.message}"
  ensure
    if made
      made.close
    else
      begin
        IO.for_fd(fd).close
      rescue SystemCallError
        nil
      end
    end
  end
end

def encs(io)
  [[io.external_encoding&.name, io.internal_encoding&.name], io]
end

# --- the mode argument -------------------------------------------------------
row("no mode")            { |fd| encs(IO.new(fd)) }
row("mode r")             { |fd| encs(IO.new(fd, "r")) }
row("mode rb")            { |fd| encs(IO.new(fd, "rb")) }
row("mode r:enc")         { |fd| encs(IO.new(fd, "r:EUC-JP")) }
row("mode r:ext:int")     { |fd| encs(IO.new(fd, "r:EUC-JP:UTF-8")) }
# A `-` where the internal encoding goes asks for NO transcoding. There is no
# encoding by that name, so looking one up would warn about correct spelling.
row("mode r:ext:-")       { |fd| encs(IO.new(fd, "r:EUC-JP:-")) }
row("mode: keyword")      { |fd| encs(IO.new(fd, mode: "r:EUC-JP")) }
row("mode as O_ flags")   { |fd| encs(IO.new(fd, File::RDONLY)) }
# `b` claims the external slot only when nothing NAMED an encoding.
row("mode rb:enc")        { |fd| io = IO.new(fd, "rb:UTF-8"); [[io.external_encoding.name, io.binmode?], io] }

