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

# --- the options Hash --------------------------------------------------------
row("external_encoding:")  { |fd| encs(IO.new(fd, external_encoding: "EUC-JP")) }
row("internal_encoding:")  { |fd| encs(IO.new(fd, external_encoding: "EUC-JP", internal_encoding: "UTF-8")) }
row("internal_encoding: -"){ |fd| encs(IO.new(fd, external_encoding: "EUC-JP", internal_encoding: "-")) }
row("internal_encoding: nil") { |fd| encs(IO.new(fd, external_encoding: "EUC-JP", internal_encoding: nil)) }
row("encoding:")           { |fd| encs(IO.new(fd, encoding: "EUC-JP")) }
row("encoding: ext:int")   { |fd| encs(IO.new(fd, encoding: "EUC-JP:UTF-8")) }
row("encoding: ext:-")     { |fd| encs(IO.new(fd, encoding: "EUC-JP:-")) }
row("binmode:")            { |fd| encs(IO.new(fd, binmode: true)) }
row("textmode:")           { |fd| encs(IO.new(fd, textmode: true)) }
row("path:")               { |fd| io = IO.new(fd, path: "labelled"); [io.path, io] }
row("autoclose: false")    { |fd| io = IO.new(fd, autoclose: false); [io.autoclose?, io] }
# An option nobody knows is ignored, not refused.
row("unknown option")      { |fd| io = IO.new(fd, no_such_option: 1); [io.class, io] }

