# downcase(:fold) maps each character through Onigmo's case fold, and
# inspect escapes each character above ASCII outside its Print class.
folded = 0
fold_sum = 0
escaped = 0
escape_sum = 0
(0..0x10FFFF).each do |code|
  next if (0xD800..0xDFFF).cover?(code)

  char = code.chr(Encoding::UTF_8)
  fold = char.downcase(:fold)
  if fold != char
    folded += 1
    fold_sum += code * fold.codepoints.sum
  end
  next if code < 128 || !char.inspect.start_with?("\"\\u")

  escaped += 1
  escape_sum += code
end
p folded, fold_sum, escaped, escape_sum
p "Straße ǅ ΣΑΣ ﬃ İ".downcase(:fold), "ǅ".casecmp?("ǆ"), "ß".casecmp?("SS")
