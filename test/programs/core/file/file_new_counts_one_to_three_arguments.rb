# File#initialize takes 1 to 3 arguments and counts them as
# rb_file_initialize does, after it refuses a File that is open.
require "tmpdir"
name = File.join(Dir.tmpdir, "file_new_counts_#{$$}")
def try = (yield rescue p([$!.class, $!.message]))
f = open(name, "w", 0644, flags: File::CREAT)
p f.class
f.close
try { open(name, "r", 0666, {flags: File::CREAT}) }
try { File.new }
try { File.new(name, "r", 0666, 1) }
File.open(name) { |io| p io.path == name }
File.open(name, "r") { |io| p io.read }
File.open(name, mode: "a") { |io| io.write("x") }
p File.read(name)
f = File.new(name)
try { f.send(:initialize, name) }
f.close
fd = IO.sysopen(name)
p File.new(fd).read
p File.instance_method(:initialize).arity
File.delete(name)
