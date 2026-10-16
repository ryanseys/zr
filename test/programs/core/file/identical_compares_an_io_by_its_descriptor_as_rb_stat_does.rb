# File.identical? reads an IO, or an object whose to_io gives one, by
# fstat(2) on its descriptor (rb_stat), so a pipe with no path compares.
IO.pipe do |r, w|
  p File.identical?(r, r)
  p File.identical?(r, w)
  p File.identical?(r, r.dup)
  p File.identical?(r, IO.for_fd(r.fileno, autoclose: false))
  p File.identical?(r, "/nonexistent")
  holder = Object.new
  holder.define_singleton_method(:to_io) { r }
  p File.identical?(holder, r)
  File.open(__FILE__) do |f|
    p File.identical?(f, __FILE__)
    p File.identical?(__FILE__, f)
    p File.identical?(f, r)
  end
  r.close
  begin
    File.identical?(r, w)
  rescue => e
    p [e.class, e.message]
  end
end
require "socket"
UNIXSocket.pair do |a, b|
  p File.identical?(a, a)
  p File.identical?(a, b)
end
