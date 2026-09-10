# native only: the program carries the compiler and writes its own code
p eval("1 + 2")
p eval("[1, 2, 3].map { |x| x * x }")
p eval("'hello'.upcase")
p eval("")
p eval("a = 6; b = 7; a * b")

eval("def twice(n) = n * 2")
p twice(21)

eval(<<~MADE)
  class Made
    def initialize(n) = @n = n
    def doubled = @n * 2
    ANSWER = 42
  end
MADE
p Made.new(4).doubled, Made::ANSWER, Made.name

p eval("eval('2 ** 10')")
p eval("(1..5).select(&:even?)")
p eval("{ a: 1, b: 2 }.transform_values { |v| v + 1 }")

begin
  eval("raise ArgumentError, 'from eval'")
rescue ArgumentError => e
  p e.message, e.class
end

p eval("[1, 2, 3].sum") + eval("4")
