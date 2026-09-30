# A top-level `PATTERN = /regex/.freeze` constant is a Regexp, the
# same as the form with no `.freeze`. `gsub(PATTERN, ...)` matches
# by the pattern.

PATTERN1 = /abc/
PATTERN2 = /xy[0-9]+/.freeze
PATTERN3 = /^foo/.freeze

puts "xabcyz".gsub(PATTERN1, "Q")        # "xQyz"
puts "xy42 xy7".gsub(PATTERN2, "M")      # "M M"
puts "foobar foobaz".gsub(PATTERN3, "Y") # "Ybar foobaz"
