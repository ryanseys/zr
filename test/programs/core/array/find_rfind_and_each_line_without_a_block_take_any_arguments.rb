# Array#find, #detect and #rfind, and String#each_line, return an
# enumerator before they check their arity, as RETURN_ENUMERATOR comes
# first in CRuby: with no block, any arguments go to the enumerator. The
# check comes when a block is given, also through the enumerator.
# Enumerable#find (Hash, Range) checks first. Found by zr-dev fuzz.
def try(label)
  puts "#{label}: #{yield.inspect}"
rescue StandardError => e
  puts "#{label}: #{e.class}: #{e.message}"
end

a = [3, 8, 5, 10]
try("find(2 args)") { a.find("%d", 1.5) }
try("detect(2 args)") { a.detect(nil, [1, 2]) }
try("rfind(2 args)") { a.rfind("%d", 2) }
try("find(nil)") { a.find(nil) }
try("find()") { a.find }
try("rfind(proc)") { a.rfind(-> { 0 }).class }
try("public_send(:rfind, 2 args)") { a.public_send(:rfind, "%d", 1.5) }

# With a block, the arity is 0..1.
try("find(2 args) {}") { a.find(1, 2) { true } }
try("detect(2 args) {}") { a.detect(1, 2) { true } }
try("enumerator with 2 args, each") { a.find(1, 2).each { true } }
try("enumerator with 2 args, size") { a.rfind(1, 2).size }

# The working forms.
try("find {}") { a.find(&:even?) }
try("detect {}") { a.detect { |x| x > 4 } }
try("rfind {}") { a.rfind(&:odd?) }
try("find(ifnone) {}") { a.find(-> { :none }) { |x| x > 99 } }
try("rfind(ifnone) {}") { a.rfind(-> { :none }) { |x| x > 99 } }
try("find(nil) {}") { a.find(nil) { |x| x > 99 } }
try("enumerator find") { a.find.with_index { |x, i| i == 2 } }
try("enumerator rfind") { a.rfind.with_index { |x, i| i == 2 } }
try("enumerator find(ifnone)") { a.find(-> { :none }).each { false } }

# Enumerable#find checks first.
try("Hash#find(2 args)") { { a: 1 }.find(1, 2) }
try("Range#find(2 args)") { (1..3).find(1, 2) }
try("Enumerator#find(2 args)") { a.each_entry.find(nil, [1, 2]) }
try("Range#detect(3 args)") { (1..3).detect(1, 2, 3) }

s = "ax0x1Fx+=-74\nsecond line\n"
try("each_line(2 args)") { s.each_line("ab", "") }
try("each_line(3 args)") { s.each_line(1, 2, 3) }
try("each_line(2 args, chomp:)") { s.each_line("x", 2, chomp: true) }
try("each_line(2 args).to_a") { s.each_line("x", 2).to_a }
try("each_line(2 args) {}") { s.each_line("x", 2) { } }
try("each_line(1 bad arg).to_a") { s.each_line(1).to_a }
try("each_line(nil).to_a") { s.each_line(nil).to_a }
try("each_line('x').to_a") { s.each_line("x").to_a }
try("each_line(chomp:).to_a") { s.each_line(chomp: true).to_a }
try("each_line('', chomp:).to_a") { "a\n\n\nb\n".each_line("", chomp: true).to_a }
try("each_line {}") { out = []; s.each_line { |l| out << l.size }; out }
try("each_line size") { s.each_line.size }
try("lines(2 args)") { s.lines("x", 2) }
