# sort_by on an array of strings, with an explicit block and with the
# `&:length` / `&:bytesize` / `&:to_i` symbol-to-proc shortcuts.
puts ["bb", "a", "ccc"].sort_by(&:length).inspect
puts ["bb", "a", "ccc"].sort_by { |s| s.length }.inspect
puts ["10", "1", "100"].sort_by(&:to_i).inspect
puts ["zzz", "a", "bb"].sort_by { |s| s.length }.inspect
# Equal-key elements keep their original order (bubble sort is stable).
puts ["bb", "a", "cc"].sort_by(&:length).inspect
