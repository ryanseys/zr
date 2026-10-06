require "objspace"
string = "abc"
file = ObjectSpace.dump_all(output: :file)
file.flush
file.rewind
puts file.class, file.read.include?('"value":"abc"')
file.close
File.unlink file.path
o = Object.new
before = ObjectSpace.memsize_of(o)
100.times { |i| o.instance_variable_set(:"@a#{i}", nil) }
p ObjectSpace.memsize_of(o) > before
