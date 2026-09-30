# `inspect` on the fixed-size arrays that Integer#divmod,
# Array#minmax, String#partition and similar methods return.

puts [1, 2, 3].minmax.inspect              # tuple:int,int
puts 17.divmod(5).inspect                   # tuple:int,int
puts "hello world".partition(" ").inspect  # tuple:string,string,string
puts "abc".rpartition("b").inspect         # tuple:string,string,string
