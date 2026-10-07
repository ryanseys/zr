# An external enumeration (Enumerator#next) runs the iteration in a fiber
# whose base is the C frame Enumerator#each. A backtrace shows it with the
# program's name and no line, and its Location has no path.

def foo
  return to_enum(__method__) unless block_given?
  raise
  yield 1
end
begin
  foo.next
rescue => e
  p e.backtrace
  l = e.backtrace_locations.last
  p [l.path, l.lineno, l.label, l.base_label, l.to_s, l.absolute_path]
end

def gen
  return to_enum(__method__) unless block_given?
  yield 1
  p caller(0)
  p caller_locations(0).map { |l| [l.path, l.lineno, l.label] }
  yield 2
end
e = gen
p e.next
p e.next

en = [1, 2].each
p en.next
begin
  en.next; en.next
rescue StopIteration => s
  p s.backtrace.size
end

o = Object.new
def o.each
  yield 1
  raise "inside each"
end
x = o.to_enum
x.next
begin
  x.next
rescue => err
  p err.backtrace
end

t = Thread.new(&method(:p))
t.join
th = Thread.new { Thread.current.backtrace }
p th.value.size
