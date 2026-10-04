# IO#reopen with a stream, with an object that converts with #to_io,
# and with a path: the mode, the position, the class and close-on-exec.
require "tmpdir"

Dir.mktmpdir do |dir|
  a = File.join(dir, "a.txt")
  b = File.join(dir, "b.txt")
  File.write(b, "Line 1\nLine 2\n")

  io = IO.new(IO.sysopen(a, "w"), "w")
  other = File.open(b)
  p other.gets
  io.reopen(other)
  p io.class
  p io.gets
  p io.path == b
  p io.close_on_exec?
  io.close
  other.close

  holder = Object.new
  target = File.open(b)
  holder.define_singleton_method(:to_io) { target }
  io = IO.new(IO.sysopen(a, "w"), "w")
  p io.reopen(holder).equal?(io)
  p io.class
  io.close

  bad = Object.new
  def bad.to_io = "text"
  begin
    File.open(a).reopen(bad)
  rescue TypeError => e
    p e.message
  end

  io = File.open(a, "w")
  io.close
  io.reopen(b, "r")
  p io.closed?
  p io.gets
  io.close_on_exec = false
  io.reopen(b)
  p io.close_on_exec?
  io.close

  begin
    File.open(a).reopen(File.open(b).tap(&:close))
  rescue IOError => e
    p e.message
  end
end
