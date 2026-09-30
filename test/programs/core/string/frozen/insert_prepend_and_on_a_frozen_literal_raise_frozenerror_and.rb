# frozen_string_literal: true
# Mutating methods on a frozen string literal raise FrozenError, as in
# MRI. Mutable strings (String.new("...")) keep working.
begin
  "hello".insert(0, "X")
  puts "BUG: insert no raise"
rescue FrozenError => e
  puts "insert: " + e.message
end
begin
  "hello".prepend("X")
  puts "BUG: prepend no raise"
rescue FrozenError => e
  puts "prepend: " + e.message
end
begin
  "hello" << "Y"
  puts "BUG: << no raise"
rescue FrozenError => e
  puts "<<: " + e.message
end

# Mutable strings still work.
s = String.new("hi")
s << "!"
puts s
