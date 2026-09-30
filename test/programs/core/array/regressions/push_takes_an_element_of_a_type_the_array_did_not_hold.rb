# Array#<< with elements of different types on an array that starts
# empty. The array holds all of them: the type of the first push does
# not decide the type of the array.

arr = []
arr << 1
arr << "string"
arr << :symbol
puts arr.length
puts arr[0]
puts arr[1]
puts arr[2]
puts "ok"
