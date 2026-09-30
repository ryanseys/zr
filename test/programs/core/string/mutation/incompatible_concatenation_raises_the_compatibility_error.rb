# Two differently-encoded NON-7-bit strings; CRuby's exact message,
# receiver's encoding first in its `inspect` form. `<<` past 255 on a
# byte-encoded receiver is the RangeError, not a promotion.

begin
  "é".b + "é"
rescue Encoding::CompatibilityError => e
  puts "plus: #{e.message}"
end
begin
  ("é".b) << "é"
rescue Encoding::CompatibilityError => e
  puts "shovel: #{e.message}"
end
begin
  "".b << 0x1F600
rescue RangeError => e
  puts "range: #{e.message}"
end
