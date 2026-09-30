# String#valid_encoding? — true for ASCII / well-formed UTF-8,
# false for invalid byte sequences.
puts "hello".valid_encoding?
puts "".valid_encoding?
puts "日本語".valid_encoding?
puts "\xff\xff".valid_encoding?
puts "abc\xc3\x28".valid_encoding?
