1&.tap { 2 }
1&.then do |x| x end
[1]&.each_slice(1) { }
x = 1&.tap { }
1&.tap do break end
[1]&.each_slice(1) do |a| break end
nil&.tap { }
[2]&.map(&:succ)
[3]&.each_slice(1) do |a|
  a
end
