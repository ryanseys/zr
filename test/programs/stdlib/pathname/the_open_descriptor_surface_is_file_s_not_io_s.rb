# Which CLASS owns a builtin method is part of its behaviour, not a detail of
# reflection: it decides which receivers answer it. This locks the boundaries
# the arity census proved zr had drawn in the wrong place.

require "pathname"
require "tmpdir"

def owner_of(klass, name)
  klass.instance_method(name).owner
rescue NameError
  "absent"
end

# The open-descriptor surface that needs a real file behind the fd is File's,
# so a pipe end does not answer it.
puts "-- File, not IO"
p owner_of(File, :flock)
p owner_of(File, :truncate)
r, w = IO.pipe
%i[size chmod chown flock lstat mtime truncate pipe?].each do |m|
  begin
    r.public_send(m)
    puts "IO##{m}: answered"
  rescue NoMethodError
    puts "IO##{m}: NoMethodError"
  rescue ArgumentError
    puts "IO##{m}: ArgumentError"
  end
end
r.close
w.close

Dir.mktmpdir do |d|
  path = File.join(d, "f")
  File.write(path, "hello world")
  File.open(path, "r+") do |f|
    p f.size
    p f.chmod(0o644)
    p f.flock(File::LOCK_EX)
    p f.flock(File::LOCK_UN)
    p f.lstat.class
    p f.mtime.class
    p f.truncate(5)
    p f.size
  end
  p File.read(path)
end

