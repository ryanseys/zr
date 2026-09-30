# frozen_string_literal: true
class String
  def freeze = raise("String#freeze called")
end
a = "lit"
b = "lét"
c = "#{1}x"
p a, a.frozen?, a.equal?("lit"), b, b.frozen?, c.frozen?
p [1, 2].inspect, :sym.to_s, "x" * 2
puts "done"
begin
  "lit".dup.freeze
rescue => e
  p e.message
end
