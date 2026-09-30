# `\b` inside a `[...]` character class means U+0008 (backspace),
# not the letter `b`. Outside `[...]`, `\b` is a word-boundary
# anchor. So `gsub(/[\b]/, ...)` does not remove the letter b.

puts "Ruby".gsub(/[\b]/, "X")
puts "a\bc".gsub(/[\b]/, "X")
puts "no backspace here".gsub(/[\b]/, "X")
puts "back\bspace".gsub(/[\b]/, "X")

# `\b` outside a character class stays a word boundary.
puts "hello world".gsub(/\bworld\b/, "earth")
puts "hello worldwide".gsub(/\bworld\b/, "earth")

# Combined char class with `\b` plus other escapes.
puts "a\tb\nc\bd".gsub(/[\t\n\b]/, "_")
