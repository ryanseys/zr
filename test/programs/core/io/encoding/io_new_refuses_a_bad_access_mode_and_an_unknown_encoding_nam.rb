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

# --- what is refused ---------------------------------------------------------
# An access mode naming nothing is refused at the call, not on the first read.
row("bad access mode")     { |fd| encs(IO.new(fd, "zz")) }
# The read/write bits asked for must be a subset of the descriptor's own.
row("mode the fd cannot serve") { |fd| encs(IO.new(fd, "w")) }
row("O_RDWR over a read-only fd") { |fd| encs(IO.new(fd, File::RDWR)) }
row("encoding named twice"){ |fd| encs(IO.new(fd, "r:EUC-JP", encoding: "UTF-8")) }
row("mode is not a String"){ |fd| encs(IO.new(fd, Object.new)) }
begin
  IO.new("/etc/hosts")
rescue TypeError => e
  puts "fd is not an Integer\t#{e.message}"
end

