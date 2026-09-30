# String#gsub with empty pattern inserts the
# replacement between every character (and at the start/end).
puts "hello".gsub("", "x")
puts "abc".gsub("", "-")
