# A forked child draws from a seed of its own: its default generator
# reseeds, also after the parent's srand, while a Random the program made
# keeps its stream. A new seed has 128 bits, and a frozen generator takes
# no seed.
def child_value
  r, w = IO.pipe
  pid = fork { r.close; w.puts(yield.to_s); w.close }
  w.close
  v = r.read.strip
  Process.wait(pid)
  [v, $?.success?]
end
rand
a = child_value { Random.rand }
b = child_value { Random.rand }
p a[0] != b[0], a[1], b[1]
c = child_value { rand }
d = child_value { rand }
p c[0] != d[0]
p child_value { (1..10).to_a.shuffle; srand != 0 }
p Array.new(8) { Random.new_seed.size }.sum / 8.0 > 15
r = Random.new(0).freeze
p((r.__send__(:initialize, r) rescue $!.class))
s = Random.new(42)
p child_value { s.rand(100) }[0] == s.rand(100).to_s
srand(7)
x = child_value { rand(1000) }
p x[0] == rand(1000).to_s
