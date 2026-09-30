# Unicode case mapping and normalization tables reach the binary's data.
puts "straße".upcase
puts "İSTANBUL".downcase
puts "ǆ".upcase, "ǆ".capitalize
puts "ABC".swapcase
puts "é" == "é".unicode_normalize(:nfc)
