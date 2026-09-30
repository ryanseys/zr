# Two GC bugs behind a StringIO/wrap program:
#  1. a join with no separator must give a String that the GC can mark.
#  2. the String that Array#join returns must stay valid after a GC, also
#     when the program stores it and reads it later.
def build(chars)
  buf = []
  chars.each { |c| buf << c }
  buf.join            # no separator; result stored below and re-joined later
end

lines = []
50.times do |i|
  chars = []
  10.times { |k| chars << ((97 + (i + k) % 26).chr) }
  lines << build(chars)     # force many allocations between store and use
  ("a".."z").to_a          # churn the GC (String#succ)
end
p lines.length
p lines.first.length
p lines.join("|").length
puts "ok"
