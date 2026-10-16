def a1 = raise(ArgumentError, "boom")
def a2 = a1
begin
  a2
rescue => e
  puts e.full_message(highlight: false)
  puts e.backtrace_locations.map { |l| [l.label, l.base_label, l.lineno].inspect }
  puts e.detailed_message
end
begin
  [1].fetch(5)
rescue IndexError => e
  puts e.full_message(highlight: false, order: :top)
end
begin
  {a: 1}.fetch(:b)
rescue KeyError => e
  p [e.message, e.key, e.receiver]
end
begin
  Integer("zz")
rescue => e
  p e
end
class Foo
  def bar = baz
end
begin
  Foo.new.bar
rescue NameError => e
  puts e.full_message(highlight: false)
  p e.name, e.receiver.class
end
begin
  nil.upcase
rescue => e
  puts e.full_message(highlight: false)
end
e = RuntimeError.new("x")
p e.backtrace, e.cause
begin
  begin
    raise "inner"
  rescue
    raise TypeError, "outer"
  end
rescue => e
  p e.cause
  puts e.full_message(highlight: false)
end
p Exception.new.message, StandardError.new(nil).message rescue p $!
def deep(n) = n == 0 ? raise("d") : deep(n - 1)
begin
  deep(30)
rescue => e
  puts e.full_message(highlight: false).lines.size
end
x = Class.new(StandardError) { def message = "custom" }
begin
  raise x
rescue => e
  puts e.full_message(highlight: false)
end
warn "w1", uplevel: 0
warn "w2", category: :deprecated
Warning[:deprecated] = true
warn "w3", category: :deprecated
$stderr.puts [1, 2].sum { |x| x }.inspect
def kw(a:) = a
kw(a: 1, **{})
puts caller(0).inspect
at_exit { puts "bye" }
raise SystemExit.new(3, "leaving") if false
exit! 0 if false
raise "final"
