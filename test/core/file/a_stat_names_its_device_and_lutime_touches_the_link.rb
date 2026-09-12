# A stat holds the device it was read from as one number, and names its
# halves. A regular file has no device of its own, so both halves of
# rdev are zero. lutime touches the link rather than what it points at,
# and answers how many paths it touched.
require "tmpdir"

def t = yield rescue [$!.class, $!.message]

Dir.mktmpdir do |dir|
  path = File.join(dir, "a")
  link = File.join(dir, "l")
  File.write(path, "x")
  File.symlink(path, link)

  st = File.stat(path)
  p st.dev_major.is_a?(Integer)
  p st.dev_minor.is_a?(Integer)
  p st.dev_major >= 0 && st.dev_minor >= 0
  p st.rdev_major, st.rdev_minor

  old = File.lstat(link).mtime
  p File.lutime(Time.at(1_000_000), Time.at(1_000_000), link)
  p File.lstat(link).mtime.to_i
  p File.stat(path).mtime.to_i == old.to_i || File.stat(path).mtime.to_i != 1_000_000
  p File.lutime(Time.at(2_000_000), Time.at(2_000_000), link, path)
  p File.stat(path).mtime.to_i
  # The message names the path, which is a different one every run.
  e = t { File.lutime(Time.now, Time.now, File.join(dir, "nope")) }
  p e.first, e.last.start_with?("No such file or directory @ apply2files - "), e.last.end_with?("/nope")
end


__END__
true
true
true
0
0
1
1000000
true
2
2000000
Errno::ENOENT
true
true
