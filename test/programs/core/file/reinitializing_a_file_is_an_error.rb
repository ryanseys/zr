# rb_file_initialize refuses a File that is open before it counts the
# arguments, and names File whatever the class is.
File.open(__FILE__) do |f|
  [[], [__FILE__], [__FILE__, "r"]].each do |args|
    f.__send__(:initialize, *args)
  rescue RuntimeError => e
    p [args.size, e.class, e.message]
  end
end
sub = Class.new(File)
sub.open(__FILE__) do |f|
  f.__send__(:initialize, __FILE__)
rescue RuntimeError => e
  p e.message
end
begin
  File.new
rescue ArgumentError => e
  p e.message
end
begin
  File.allocate.__send__(:initialize)
rescue ArgumentError => e
  p e.message
end
p File.instance_method(:initialize).arity
