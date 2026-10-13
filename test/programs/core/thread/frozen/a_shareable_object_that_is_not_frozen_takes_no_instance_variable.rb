# A Ractor, ENV and a Proc that a ractor isolated are shareable but not
# frozen. None of them takes an instance variable, from any ractor, so
# every ractor can read theirs (nil). Isolation refuses a block that
# reaches an outer local, uses `yield`, or has instance variables. A
# frozen Method is shareable when its receiver is. No IO is shareable.
Warning[:experimental] = false
Thread.report_on_exception = false
def try(label)
  print label, ": "
  p yield
rescue Exception => e
  puts "#{e.class}: #{e.message}#{" (cause #{e.cause.class}: #{e.cause.message})" if e.cause}"
end

class Ractor
  def setup = @foo = ""
  def peek = @foo
end

try("ractor ivar set") { Ractor.current.instance_variable_set(:@a, 1) }
try("ractor ivar set by @") { Ractor.current.setup }
try("ractor ivar get") { Ractor.current.instance_variable_get(:@a) }
try("ractor ivars") { Ractor.current.instance_variables }
try("ractor ivar defined") { Ractor.current.instance_variable_defined?(:@a) }
try("env ivar") { ENV.instance_variable_set(:@a, 1) }
try("env ivar by @") { ENV.instance_eval { @a = 1 } }
try("env ivar read") { ENV.instance_eval { @a } }
try("env ivars") { ENV.instance_variables }
try("env shareable") { [Ractor.shareable?(ENV), ENV.frozen?] }
try("ractor shareable") { [Ractor.shareable?(Ractor.current), Ractor.current.frozen?] }
try("port ivar") { Ractor::Port.new.instance_variable_set(:@a, 1) rescue $!.class }
r = Ractor.new { Ractor.current.peek }
try("peek inside") { r.value }
r = Ractor.new(Ractor.current) { |main| [main.instance_variable_get(:@a), main.peek] }
try("read main from a ractor") { r.value }
r = Ractor.new(Ractor.current) { |main| main.setup }
try("write main from a ractor") { r.value }
r = Ractor.new { ENV.instance_eval { @b = 1 } }
try("env write from a ractor") { r.value }
try("proc with ivar") { q = proc { 1 }; q.instance_variable_set(:@x, 1); Ractor.new(&q) }
try("frozen proc with ivar") { q = proc { 1 }; q.instance_variable_set(:@x, 1); q.freeze; Ractor.new(&q) }
pr = proc { 1 }
try("isolated proc") { Ractor.new(&pr).join; [Ractor.shareable?(pr), pr.frozen?] }
try("isolated proc ivar") { pr.instance_variable_set(:@y, 1) }
try("isolated proc read") { pr.instance_variable_get(:@y) }
try("isolated proc make_shareable") { Ractor.make_shareable(pr).equal?(pr) }
lam = -> {}
Ractor.new(&lam).join
r = Ractor.new(lam) { |l| l.instance_variable_get(:@foo) }
try("isolated lambda read from a ractor") { r.value }
def m_yield = Ractor.new { yield }
try("yield") { m_yield {} }
def m_nested_yield = Ractor.new { [1].each { yield } }
try("nested yield") { m_nested_yield {} }
def m_yield_outer(x) = Ractor.new { [x, yield] }
try("yield and outer") { m_yield_outer(1) {} }
def m_sp_yield = Ractor.shareable_proc { yield }
try("shareable_proc yield") { m_sp_yield {} }
def m_sp_yield_write
  v = 1
  Ractor.shareable_proc { v = 2; yield }
end
try("shareable_proc yield and write") { m_sp_yield_write {} }
o = 2
try("outer") { Ractor.new { o } }
try("frozen method shareable") { Ractor.shareable?(1.method(:+).freeze) }
try("frozen method, unshareable receiver") { Ractor.shareable?((+"a").method(:size).freeze) }
try("unfrozen method") { Ractor.shareable?(1.method(:+)) }
try("io shareable") { [Ractor.shareable?($stdout), Ractor.shareable?(File.open(__FILE__).freeze)] }
try("make io shareable") { Ractor.make_shareable(File.open(__FILE__)) }
try("make an array of io shareable") { Ractor.make_shareable([$stderr]) }
try("at_exit in a ractor") { Ractor.new { at_exit {}; 1 }.value }
try("at_exit in main") { at_exit {}; :ok }
