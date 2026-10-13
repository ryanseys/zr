# ruby 4.1: String#lines on a UTF-32 or UTF-16 string whose last
# character is cut gives the lines it can find, with no piece past the end.
p "AB".force_encoding("UTF-32LE").lines("B".force_encoding("UTF-32LE")).to_a
p "AB".force_encoding("UTF-32LE").lines("B".force_encoding("UTF-32LE"), chomp: true).to_a
p "ABC".force_encoding("UTF-16LE").lines("C".force_encoding("UTF-16LE")).map(&:bytes)
p "A\0\n\0B".force_encoding("UTF-16LE").lines.map(&:bytes)
