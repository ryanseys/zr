# The code in a compiled string, as ruby's iseqs give it: each def,
# block, class body, rescue and ensure clause is a child with its type
# and label ("block (2 levels) in bar"), whose trace points open and
# close with :call/:return, :b_call/:b_return or :class/:end (none for
# a singleton class), and a rescue clause fires :rescue. A literal or
# a read whose value no one uses compiles to nothing, so it has no
# :line event; an empty begin's event is its rescue clause's line.
ISeq = RubyVM::InstructionSequence

tree = lambda do |iseq|
  kids = []
  iseq.each_child { |child| kids << tree.(child) }
  [["#{iseq.label}@#{iseq.first_lineno}", iseq.to_a[9], iseq.trace_points], *kids.sort_by { |k, *| k }]
end

pp tree.(ISeq.compile(<<~RUBY))
  class C
    def foo
      begin
      rescue
        p :rescue
      ensure
        p :ensure
      end
    end
    def bar
      1.times{
        2.times{
        }
      }
    end
  end
  class D < C
  end
RUBY

pp tree.(ISeq.compile(<<~RUBY))
  module M
  end
  class << self
    1
  end
  x = ->(a) {
    a
  }
  for i in [1]
    p i
  end
  def a
    begin
    rescue
      p 1
      p 2
    end
  end
  def b
    p 0
  rescue
    p 1
  ensure
    p 3
  end
RUBY

pp ISeq.compile(<<~RUBY).trace_points
  1
  :a
  'a'
  "\#{1}"
  nil
  true
  self
  1.0
  /a/
  []
  [1]
  {a: 1}
  1..2
  __FILE__
  __LINE__
  x = 1
  x
  @a
  $a
  Comparable
  [x, foo]
  2
RUBY

pp tree.(ISeq.compile(<<~RUBY))
  def m
    1
    2
  end
  1.times do
    1
    2
  end
RUBY

iseq = ISeq.compile("# 1\n# 2\ndef foo   # line 3\nend\n1.time do\nend\nclass C\nend\n")
rows = []
iseq.each_child { |child| rows << child.to_a.values_at(9, 5).push(child.to_a[13].first(2)) }
p rows
