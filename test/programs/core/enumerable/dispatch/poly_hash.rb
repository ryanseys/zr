# Test heterogeneous Hash

h = {name: "Alice", age: 30, active: true}
puts h[:name]     # Alice
puts h[:age]      # 30
puts h[:active]   # true
puts h.length     # 3

# Iteration
h.each do |k, v|
  puts k
end
# name, age, active

puts "done"
