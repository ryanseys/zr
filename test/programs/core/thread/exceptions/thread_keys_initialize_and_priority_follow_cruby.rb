# Thread locals and thread variables take a key through to_str, a frozen
# thread refuses writes to them, Thread.new runs a subclass's initialize
# (which can give super its block), Thread.start runs none, and
# priority clamps to -3..3.
def t
  yield
rescue => e
  [e.class, e.message.sub(/0x\h+/, "X")]
end
k = Object.new
def k.to_str = "kk"
th = Thread.current
th[k] = 1
p th[k], th[:kk], th.key?(k), t { th[1] }
th.thread_variable_set(k, 49)
p th.thread_variable_get(k), th.thread_variable?(k), t { th.thread_variable_get(123) }, t { th.thread_variable_set(123, 1) }
p th.thread_variables.include?(:kk)
f = Thread.new { sleep }
Thread.pass until f.stop?
f.freeze
p t { f[:a] = 1 }, t { f.thread_variable_set(:a, 1) }, f.thread_variable_get(:a), f[:a]
f.kill rescue nil
c = Class.new(Thread) do
  def initialize
    $rec = [:good]
    super { $rec << :in_thread }
  end
end
c.new.join
p $rec
d = Class.new(Thread) { def initialize = nil }
p t { d.new }.first
s = Class.new(Thread) { def initialize(*) = raise("called") }
p s.start { 1 }.value, t { Thread.start }, t { Thread.new }
x = Thread.new { }
x.priority = 42
p x.priority, (x.priority = -9; x.priority), t { x.priority = "a" }
x.join
