# String#insert steps a negative index one up, so -1 appends, and an index
# out of range names that stepped index in its IndexError.
[-1, -2, -3, -4, -5, -9, 0, 2, 3, 7].each do |i|
  s = +"ab"
  begin
    s.insert(i, "X")
    puts "#{i}: #{s}"
  rescue IndexError => e
    puts "#{i}: #{e.message}"
  end
end
s = +"héllo"
p s.insert(-3, "·"), (s.insert(-9, "x") rescue $!.message)
