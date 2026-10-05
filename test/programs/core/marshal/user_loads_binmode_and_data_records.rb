require "stringio"

# freeze: true gives one interned String for equal Strings.
o = Marshal.load(Marshal.dump(["foo" + "bar", "foobar"]), freeze: true)
p o[0].equal?(o[1]), o[0].frozen?

# A class's own _load runs once, and the bytes after the value are left
# unread.
class U
  attr_accessor :f1, :f2
end

def U._load(s)
  p [:load, s]
  U.new
end
r = Marshal.load("\004\bu:\x06U\a:\f@field2i\f:\f@field1i\v")
p r.class, r.f1, r.f2
p Marshal.load("\x04\bi\x06junk"), Marshal.load("\x04\b[\x06i\x06\x00\x01")

# A stream is put in binmode first.
io = StringIO.new("\004\b:\vsymbol")
def io.binmode = raise("binmode")
p((Marshal.load(io) rescue $!))
p Marshal.load(StringIO.new("\004\b:\vsymbol"))

# `d`: a T_DATA object with _dump_data and _load_data.
class DumpableDir < Dir
  def _dump_data = path
  def _load_data(path) = initialize(path)
end
d = DumpableDir.new(".")
p Marshal.dump(d)
d.close
d = Marshal.load("\x04\bd:\x10DumpableDirI\"\x06.\x06:\x06ET")
p d.class, d.path
d.close

class UnloadableDumpableDir < Dir
  def _dump_data = path
end
p((Marshal.load("\x04\bd:\x1AUnloadableDumpableDirI\"\x06.\x06:\x06ET") rescue $!))

class UserDefined; end
p((Marshal.load("\004\bd:\020UserDefined\0") rescue $!))
p((Marshal.load("\x04\bd:\tTimeI\"\x06.\x06:\x06ET") rescue $!))
p((Marshal.load("\x04\bd:\nMutexi\x06") rescue $!))
p((Marshal.load("\x04\bd:\x0EMatchDatai\x06") rescue $!))
p((Marshal.load("\x04\bd:\tProci\x06") rescue $!))
p((Marshal.dump(/a/.match("a")) rescue $!))
p((Marshal.dump(Thread::Mutex.new) rescue $!))
p((Marshal.dump(Encoding::Converter.new("UTF-8", "UTF-16")) rescue $!))
