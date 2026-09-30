# A closure captures a local that holds a Regexp, and GC runs while the
# closure is alive. The captured Regexp keeps working.
WORDS = ["alpha", "gamma"]

def lines_of(i)
  Array.new(20) { |j| "file #{i} line #{j} mentions alpha and beta" }
end

total = 0
60.times do |i|
  matchers = WORDS.map do |text|
    re = Regexp.new("\\b#{text}\\b")
    ->(line) { !re.match(line).nil? }
  end
  matchers.push(->(line) { line.include?("beta") })
  lines_of(i).each { |line| matchers.each { |m| total += 1 if m.call(line) } }
end
p total

# the captured pattern still matches after many collections, and reassigning
# the captured cell is still visible to the closure
pat = Regexp.new("z+")
probe = ->(s) { pat.match(s).nil? ? "no" : "yes" }
100.times { Array.new(20) { |k| "junk #{k}" } }
p probe.call("azzb")
pat = Regexp.new("q+")
p probe.call("azzb")
p probe.call("aqqb")
