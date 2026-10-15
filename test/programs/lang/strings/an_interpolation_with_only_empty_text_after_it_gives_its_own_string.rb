# An interpolated String whose first part is the one embedded value and
# whose other parts are only empty text gives that value's String itself,
# not a new String: ruby's compiler drops the empty text and the join of
# one part. Text before the value, two values, or text that is not empty
# make a new String.
s = +"ab"
cases = {
  "line continuation" => "#{s}\
",
  "empty braces" => "#{s}#{""}",
  "two empty parts" => "#{s}#{""}#{''}",
  "adjacent empty literal" => "#{s}" "",
  "alone" => "#{s}",
  "empty text first" => "#{""}#{s}#{""}",
  "text after" => "#{s}#{"x"}",
  "two values" => "#{s}#{s}#{""}",
}
cases.each { |label, str| puts "#{label}: #{str.equal?(s)} #{str.frozen?}" }

held = "#{s}#{""}"
held << "c"
p s

class Word
  def initialize(text) = @text = text
  def to_s = @text
end
text = +"word"
p "#{Word.new(text)}#{""}".equal?(text)
p "#{Word.new(text)}".equal?(text)
p "#{:sym}#{""}", "#{12}#{""}", "#{nil}#{""}".frozen?

class Silent
  def to_s = 5
  def inspect = "silent"
end
p "#{Silent.new}#{""}".start_with?("#<Silent")

p eval(%q("#{s}#{""}")).equal?(s), eval(%q("#{s}")).equal?(s)
