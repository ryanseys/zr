# Unicode case folding and inspect: downcase(:fold) and casecmp? map each
# character through the fold table, and inspect asks which characters
# are printable.
words = ["Straße", "ΣΊΣΥΦΟΣ", "Ǆemal", "ﬃ", "ПРИВЕТ", "Ꭰꭰ", "ǅ", "İstanbul", "ẞ", "\u{1E900}x", "Ⓐⓑ", "\u{10400}"]
text = words.join(" ") * 20
sum = 0
i = 0
while i < 4_000
  folded = text.downcase(:fold)
  sum += folded.bytesize
  sum += 1 if words[i % words.size].casecmp?(words[(i + 3) % words.size].swapcase)
  sum += text.inspect.bytesize
  i += 1
end
puts sum
