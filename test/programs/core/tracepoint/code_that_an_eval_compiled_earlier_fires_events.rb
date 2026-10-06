# Code that an eval compiled before a TracePoint is enabled fires its
# events once one is, as the program's own code does.
parent = Class.new { def read = @values.shift }
child = Class.new(parent) { def initialize = (@values = ["chunk", nil]) }
start = __LINE__ + 2
child.class_eval <<~RUBY, __FILE__, start
  def read
    return if @finished
    while chunk = super
      chunk.upcase
    end
  end
RUBY
lines = []
TracePoint.new(:line) { |tp| lines << tp.lineno - start }.enable { child.new.read }
p lines
eval("def later(x)\n  y = x\n  y + 1\nend", nil, "later.rb", 1)
ev = []
TracePoint.new(:line, :call, :return) { |tp| ev << [tp.event, tp.lineno] if tp.path == "later.rb" }.enable { later(1) }
p ev
3.times { eval("1 + 1") }
