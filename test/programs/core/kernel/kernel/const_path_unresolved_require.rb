# An unresolved qualified constant (`Mylib::VERSION`, Mylib undefined) raises a
# rescuable runtime NameError. It is not a compile error. In a real program the
# constant can come from a `require "mylib/version"`; this program only reads
# the constant, because the rescuable NameError is what matters here.
begin
  puts Mylib::VERSION
rescue NameError => e
  puts "rescued: #{e.message}"
end
puts "after"
