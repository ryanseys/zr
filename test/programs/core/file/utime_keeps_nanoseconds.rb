# File.utime and File.lutime set times to the nanosecond, from a Time, a
# Float, a Rational or an Integer, as ruby's utimensat call does.
require "tmpdir"

Dir.mktmpdir do |dir|
  path = File.join(dir, "f")
  link = File.join(dir, "l")
  File.write(path, "x")
  File.symlink(path, link)

  t = Time.at(1789907379, 383895094, :nanosecond)
  p File.utime(t, t, path)
  p [File.stat(path).mtime.nsec, File.stat(path).atime.nsec]

  File.utime(1700000000.25, Rational(3400000001, 2), path)
  p [File.stat(path).atime.tv_sec, File.stat(path).atime.nsec, File.stat(path).mtime.tv_sec, File.stat(path).mtime.nsec]

  p File.lutime(Time.at(1700000000, 123456789, :nanosecond), Time.at(1700000000, 123456789, :nanosecond), link)
  p File.lstat(link).mtime.nsec, File.stat(link).mtime.nsec

  File.utime(nil, nil, path)
  p (Time.now - File.stat(path).mtime).abs < 5

  begin
    File.utime(nil, 1, path)
  rescue TypeError => e
    p e.message
  end
end
