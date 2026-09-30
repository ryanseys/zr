# The empty symbol literal `:""` is a real Symbol whose name is "".

s = :""
puts s.to_s.length          #=> 0
puts(s == :"")              #=> true
puts(:"" == :"")           #=> true
puts(:"" == :a)            #=> false

# In a symbol array and as a value.
arr = [:"", :a, :""]
puts arr.length             #=> 3
puts arr[0].to_s.length     #=> 0
puts arr[1].to_s            #=> a

# Round-trips through to_s/to_sym.
t = "".to_sym
puts(t == :"")             #=> true
puts "done"
