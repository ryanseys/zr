# String#insert converts its argument with to_str once, as rb_str_insert
# does, then checks the encodings and the index.
class Text
  attr_reader :calls

  def initialize(text)
    @text = text
    @calls = 0
  end

  def to_str
    @calls += 1
    @text
  end
end

text = Text.new("XY")
s = +"abc"
p s.insert(1, text), text.calls
bang = Text.new("!")
p s.insert(-1, bang), bang.calls
p (+"ab").insert(0, ""), (+"ab").insert(2, "c"), (+"ab").insert(-3, "c")

late = Text.new("x")
begin
  (+"ab").insert(5, late)
rescue IndexError => e
  p e.message, late.calls
end

begin
  (+"ab").insert(0, 1)
rescue TypeError => e
  p e.message
end
