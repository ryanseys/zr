# IO#seek takes any offset that fits an off_t, and #pos reads the
# position back, also where it is past 2**62. A read there finds the end.
path = "seek_far_#{Process.pid}.txt"
File.write(path, "HELLOWORLDABCDEF")
File.open(path) do |f|
  [[2**62 - 1, IO::SEEK_END], [2**62, IO::SEEK_SET], [2**63 - 1, IO::SEEK_SET], [2**62 - 17, IO::SEEK_CUR],
   [-(2**62), IO::SEEK_CUR], [2**63 - 1, IO::SEEK_END]].each do |offset, whence|
    f.rewind
    f.seek(offset, whence)
    p [offset, whence, f.pos, f.read(3), f.eof?]
  rescue SystemCallError, RangeError => e
    p [offset, whence, e.class, e.message.sub(path, "PATH")]
  end
  f.pos = 2**62 + 5
  p f.pos
  p f.tell
  begin
    f.seek(2**63)
  rescue RangeError => e
    p e
  end
  f.rewind
  p f.read(5)
end
File.delete(path)
