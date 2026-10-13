# A block in eval'd code takes its label from the code that calls eval:
# its level counts the blocks around the eval too, as
# `block (2 levels) in <main>` for a block in an eval in a block.
def t = yield
t { begin; eval("proc { raise 'x' }").call; rescue => e; p e.backtrace_locations.first.label; end }
t { begin; eval("proc { proc { raise 'x' }.call }").call; rescue => e; p e.backtrace_locations.first.label; end }
begin; eval("proc { raise 'x' }").call; rescue => e; p e.backtrace_locations.first.label; end
t { t { begin; eval("raise 'y'"); rescue => e; p e.backtrace_locations.first.label; end } }
t { begin; eval("[1].each { raise 'z' }"); rescue => e; p e.backtrace_locations.map(&:label).first(2); end }
def mm = eval("proc { raise 'w' }").call
begin; mm; rescue => e; p e.backtrace_locations.first.label; end
class K; def k = [1].map { eval("[2].map { raise 'v' }") }; end
begin; K.new.k; rescue => e; p e.backtrace_locations.map(&:label).first(4); end
begin; Class.new.class_eval("[1].each { raise 'u' }"); rescue => e; p e.backtrace_locations.first.label; end
begin; Object.new.instance_eval("[1].each { [2].each { raise 'u' } }"); rescue => e; p e.backtrace_locations.first.label; end
t { begin; binding.eval("[1].each { raise 'b' }"); rescue => e; p e.backtrace_locations.first.label; end }
