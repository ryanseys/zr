# A `case` on symbol arms, as a tokenizer or a state machine does: 15
# symbols in 12 arms, some arms with more than one symbol, and a loop
# over a mixed list of symbols. Some symbols match no arm and go to `else`.

def weight(kind)
  case kind
  when :int then 1
  when :float then 2
  when :string then 3
  when :symbol then 4
  when :ident, :const then 5
  when :lparen, :rparen then 6
  when :lbrace, :rbrace then 7
  when :comma then 8
  when :dot then 9
  when :plus then 10
  when :minus then 11
  when :eof then 12
  else 0
  end
end

kinds = %i[
  int float string symbol ident const lparen rparen lbrace rbrace
  comma dot plus minus eof space newline comment
]
tokens = []
i = 0
while i < 1000
  tokens << kinds[(i * 7) % kinds.size]
  i += 1
end

total = 0
n = 0
while n < 10_000
  tokens.each { |k| total += weight(k) }
  n += 1
end
puts total
puts "done"
