# IO's init provides io/wait before the program starts, so it is in
# $LOADED_FEATURES and every require of it returns false. Its methods are
# IO's own.
p $LOADED_FEATURES.include?("io/wait.rb")
p $LOADED_FEATURES.include?("io/wait.so")
p $LOADED_FEATURES.index("io/wait.rb") < $LOADED_FEATURES.index("io/wait.so")
p require("io/wait")
p require("io/wait.rb")
p require("io/wait.so")
p $LOADED_FEATURES.count { |f| f.end_with?("io/wait.rb", "io/wait.so") }

%i[wait wait_readable wait_writable wait_priority].each do |name|
  p [name, IO.instance_method(name).owner]
end
p IO.method_defined?(:ready?)
p IO.method_defined?(:nread)

r, w = IO.pipe
p r.wait_readable(0)
w.write("x")
p r.wait_readable(1).equal?(r)
p w.wait_writable(1).equal?(w)
r.close
w.close
