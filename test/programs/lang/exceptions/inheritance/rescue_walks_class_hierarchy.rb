# `rescue ParentClass => e` should catch a raised subclass
# instance, and `e.is_a?(AncestorClass)` should walk the class
# hierarchy. So a `raise C` where `C < B < A < StandardError` is
# caught by `rescue B`, `rescue A` and `rescue StandardError`,
# and `e.is_a?(X)` is true for each ancestor X.

class A < StandardError; end
class B < A; end
class C < B; end

# `rescue B` catches a raised C
begin
  raise C, "boom"
rescue B => e
  puts "caught B: " + e.message
end

# is_a? walks the chain
begin
  raise C, "x"
rescue => e
  puts "is_a A? " + (e.is_a?(A) ? "yes" : "no")
  puts "is_a B? " + (e.is_a?(B) ? "yes" : "no")
  puts "is_a C? " + (e.is_a?(C) ? "yes" : "no")
  puts "is_a StandardError? " + (e.is_a?(StandardError) ? "yes" : "no")
  puts "is_a String? " + (e.is_a?(String) ? "yes" : "no")
end

# Standard library exception hierarchy: ArgumentError < StandardError.
# `rescue StandardError` should catch ArgumentError.
begin
  raise ArgumentError, "bad"
rescue StandardError => e
  puts "caught StandardError via ArgumentError: " + e.message
end
