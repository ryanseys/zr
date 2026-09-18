# Warnings and a Hash-corpus batch -- it needs ENV, Thread, Dir.
p((1..Float::INFINITY).size, (1..2.5).size, (1...2.0).size, (1...3.0).size, (1..-1.5).size, (1..1.0).size, (1...1.0).size, (1...(7/2r)).size, (1..(7/2r)).size, (1...(3/1r)).size, (5..1).size, (1..-Float::INFINITY).size)
p(("a".."z").size)
[(1.0..10.0), (nil..1), (0.5..Float::INFINITY)].each { |r| begin; p r.size; rescue => e; p [e.class, e.message]; end }
p nil.to_f
h = Hash.new(7); h["a"] = 1
p h.except("a")["z"], h.dup["z"], h.merge({})["z"], h.compact["z"]
begin; [1, 2].max_by(-1) { |n| n }; rescue => e; p e.message; end
p([1, 2].fetch(9, :dflt) { |i| [:blk, i] })
p({ a: 1 }.fetch(:z, :dflt) { |k| [:blk, k] })
p(ENV.fetch("ZEO_NO_SUCH_VAR", "dflt") { |k| "blk #{k}" })
p(Thread.current.fetch(:nope, :dflt) { |k| [:blk, k] })
p(Array.new(3, :fill) { |i| i })
p([1, 2].fetch(0, :dflt) { :blk })
$VERBOSE = nil
p({ a: 1 }.fetch(:z, :dflt) { :blk })
$VERBOSE = false
x = { k: 1, k: 2 }
p x
class Opts
  def to_hash = { a: 1, b: 2 }
end
def take(a:, b:) = [a, b]
p take(**Opts.new)
def collect(**o) = o
p collect(**Opts.new)
p({ **Opts.new, c: 3 })
class Bad
  def to_hash = 3
end
begin; collect(**Bad.new); rescue TypeError => e; p e.message; end
begin; collect(**Object.new); rescue TypeError => e; p e.message; end
ENV["SP_A"] = "1"
ENV.update({ "SP_A" => "2", "SP_B" => "9" }) { |k, o, n| o + n }
p ENV["SP_A"], ENV["SP_B"]
ENV.merge!({ "SP_B" => "0" }) { |k, o, n| "#{k}!" }
p ENV["SP_B"]
a = /ab/i
v = a.dup
p v == a, v.equal?(a), v.match?("AB"), v.options, v.source, a.clone.frozen?
d = [1, 2, 3].each
w = d.dup
p w.next, w.class
dir = File.join(ENV.fetch("TMPDIR", "/tmp"), "ze0_chdir_#{Process.pid}")
Dir.mkdir(dir)
begin
  before = Dir.pwd
  p(Dir.chdir(dir) { |d| [d == dir, Dir.pwd != before] })
  p Dir.pwd == before
  p Dir.chdir(dir), Dir.pwd != before
  Dir.chdir(before)
  begin; Dir.chdir("/no/such/dir"); rescue SystemCallError => e; p e.class, e.message; end
ensure
  Dir.rmdir(dir)
end
p(ENV.delete("SP_NOPE_X") { |k| "missing #{k}" })
