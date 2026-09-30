# gsub with a zero-width match (anchors, empty pattern, word boundary,
# zero-repeat quantifier) must insert the replacement at each match
# position, keep the source character there, and advance by one. It must
# not drop the character, loop forever, or copy a tail of negative length.
p "abc".gsub(/$/, "!")
p "x\ny".gsub(/$/, "!")
p "x\ny\nz".gsub(/$/, "!")
p "a\nb".gsub(/^/, ">")
p "hello".gsub(//, "-")
p "abc".gsub(/b*/, "X")
p "hello world".gsub(/\b/, "|")
p "abc".sub(/$/, "!")

# The each_line + $-anchored capture build, which surfaced the bug.
table = {}
"Name Ada\nLang Ruby\nYear 1995".each_line do |line|
  if (m = line.match(/^(\w+) (.+)$/))
    table[m[1]] = m[2]
  end
end
p table.keys
p table["Lang"]

# Lengths are correct (metadata, not just strlen).
p "x\ny".gsub(/$/, "!").length
p "hello".gsub(//, "-").length
