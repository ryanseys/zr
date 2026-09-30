# rescue of a namespaced exception class (rescue M::Err) must match a
# raised M::Err. Both the raise and the rescue clause use the full
# path M::Err, not only the leaf name Err.
module M
  class Err < StandardError; end
end

begin
  raise M::Err, "boom"
rescue M::Err => e
  puts "caught: " + e.message
end

# Control: bare base class still matches a namespaced raise.
begin
  raise M::Err, "again"
rescue StandardError => e
  puts "base: " + e.message
end

# Control: top-level class name still matches.
class TopErr < StandardError; end
begin
  raise TopErr, "top"
rescue TopErr => e
  puts "top: " + e.message
end

puts "after"
