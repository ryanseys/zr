# A spawn that fails names what failed, as ruby's child reports it: the
# chdir: directory, or the redirect file with no "@ rb_sysopen". A
# redirect that fails closes the files that opened before it.
require "tmpdir"

def fds = Dir.children("/dev/fd").size

Dir.mktmpdir do |dir|
  try = lambda do |&blk|
    blk.call
    puts "no raise"
  rescue SystemCallError => e
    puts "#{e.class}: #{e.message.sub(dir, "DIR")}"
  end

  try.() { Process.spawn("true", chdir: "/no-such-directory-here") }
  try.() { Process.spawn("/bin/cat", in: File.join(dir, "absent")) }
  try.() { Process.spawn("/bin/cat", out: File.join(dir, "nodir", "x")) }

  input = File.join(dir, "in")
  File.write(input, "x")
  before = fds
  10.times do
    Process.spawn("/bin/cat", in: input, out: File.join(dir, "nodir", "x"))
  rescue Errno::ENOENT
  end
  p fds - before
end
