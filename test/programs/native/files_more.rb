# Links, times, modes and Dir objects, all over libSystem.
dir = "#{ENV["TMPDIR"] || "/tmp"}/zr-files-more"
if Dir.exist?(dir)
  Dir.each_child(dir) { |name| File.delete("#{dir}/#{name}") }
  Dir.rmdir(dir)
end
Dir.mkdir(dir)
path = "#{dir}/a.txt"
File.write(path, "hello")

p File.identical?(path, path), File.identical?(path, dir)
p File.pipe?(path), File.socket?(path), File.blockdev?(path), File.chardev?(path)
p File.owned?(path), File.grpowned?(path) == (File.stat(path).gid == Process.gid)
p File.setuid?(path), File.setgid?(path), File.sticky?(path)
p File.readable_real?(path), File.writable_real?(path), File.executable_real?(path)
p File.world_readable?(path).is_a?(Integer) || File.world_readable?(path).nil?
p File.path(path), File.umask.is_a?(Integer)

link = "#{dir}/link"
File.symlink(path, link)
p File.readlink(link), File.symlink?(link), File.symlink?(path), File.ftype(link)
hard = "#{dir}/hard"
File.link(path, hard)
p File.identical?(path, hard), File.size(hard)

File.truncate(path, 3)
p File.read(path), File.size(path)
File.utime(Time.at(1_000_000), Time.at(2_000_000), path)
p File.atime(path).to_i, File.mtime(path).to_i
File.chmod(0o640, path)
p format("%o", File.stat(path).mode & 0o777)
File.open(path, "r+") do |f|
  p f.to_path == path, f.stat.size, f.mtime.to_i, f.pid, f.autoclose?, f.close_on_exec?
  p f.pread(2, 1), f.pos
  p f.flock(File::LOCK_EX), f.flock(File::LOCK_UN)
  f.truncate(1)
end
p File.size(path)

d = Dir.new(dir)
p d.path, d.to_path, d.pos, d.inspect
names = []
d.each { |name| names << name }
p names.sort, d.children.sort
d.rewind
p d.read.is_a?(String)
d.close
begin
  d.read
rescue IOError => e
  puts e.message
end
p Dir.open(dir) { |x| x.children.size }

p test(?e, path), test(?e, "#{dir}/nope"), test(?d, dir), test(?f, path), test(?s, path)
p test(?-, path, hard), test(?=, path, path)
begin
  test(?q, path)
rescue ArgumentError => e
  puts e.message
end

begin
  File.readlink(path)
rescue SystemCallError => e
  puts e.message.sub(path, "<path>")
end
begin
  File.truncate("#{dir}/nope", 0)
rescue SystemCallError => e
  puts e.message.sub(dir, "<dir>")
end

Dir.each_child(dir) { |name| File.delete("#{dir}/#{name}") }
Dir.rmdir(dir)
p Dir.exist?(dir)
