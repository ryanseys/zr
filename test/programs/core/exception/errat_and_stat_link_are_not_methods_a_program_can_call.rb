# Exception.errat (`$@`) and File::Stat.link (File.lstat) are the core's
# own helpers: a program does not see them, and a call is a NoMethodError,
# while `$@`, File.lstat and File.ftype still work through them.
p Exception.respond_to?(:errat), File::Stat.respond_to?(:link)
p Exception.singleton_methods.include?(:errat), File::Stat.singleton_methods.include?(:link)

[-> { Exception.errat(nil) }, -> { File::Stat.link("/") }].each do |call|
  call.call
rescue NoMethodError => e
  p [e.class, e.name]
end

begin
  raise "x"
rescue
  p $@.class, $@.first.class
end
p $@
p File.lstat("/").class, File.ftype("/")
