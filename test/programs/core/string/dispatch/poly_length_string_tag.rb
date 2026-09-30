# `.length` / `.size` on a receiver of unknown type that holds a String
# at run time gives the String's length. This matters when an
# is_a?(String) guard appears alongside a length check:
#   if v.is_a?(String) && v.length > 0; ... end

class C; def x; 1; end; end

arr = ["hello", C.new]
v = arr[0]
if v.is_a?(String) && v.length > 0
  puts v
end
if v.is_a?(String)
  puts v.size.to_s
end
puts "done"
