# Process::Status#== is true for the same status, else it compares the
# status word with the other value as Integer#== does: a Float, another
# Status with the same word, or any value whose `==` agrees.
system("exit 3")
first = $?
system("exit 3")
second = $?
system("true")
third = $?

class Word
  def initialize(n) = @n = n
  def ==(other) = other == @n
end

p first == first, first == second, first.equal?(second), first == third, first != third
p first == 768, first == 768.0, first == 768r, first == 2.5, first != 768
p first == "x", first == nil, first == :sym, first != "x"
p first == Word.new(768), first == Word.new(0)
p third == 0, third == 0.0, third == second
