# A File test asks an IO, or an object whose to_io gives one, with
# fstat(2) on its descriptor, and IO#stat never stats a path.
wrapper = Object.new
wrapper.singleton_class.define_method(:to_io) { $stdin }
p [File.size?(wrapper).class, File.directory?(wrapper), File.exist?(wrapper)]
File.write("gone.txt", "abc")
f = File.open("gone.txt")
File.delete("gone.txt")
p [File.size(f), File.file?(f), f.stat.size, f.stat.nlink]
f.close
bad = Object.new
def bad.to_io = 5
begin
  File.size(bad)
rescue TypeError => e
  p e.message
end
