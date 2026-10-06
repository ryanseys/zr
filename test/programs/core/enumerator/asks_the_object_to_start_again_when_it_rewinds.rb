# `enumerator_rewind` calls the object's own `rewind` with
# rb_check_funcall: anything that knows how to start again is told
# to, one that does not is left alone, and a private one is reached
# all the same.
class Counted
  include Enumerable
  attr_reader :rewound
  def initialize = @rewound = 0
  def rewind = @rewound += 1
  def each = block_given? ? (yield 1) : to_enum(:each)
end

class Quietly
  include Enumerable
  attr_reader :rewound
  def initialize = @rewound = 0
  private def rewind = @rewound += 1
  def each = block_given? ? (yield 1) : to_enum(:each)
end

counted = Counted.new
e = counted.each
e.next
e.rewind
p counted.rewound
p e.next

quiet = Quietly.new
quiet.each.rewind
p quiet.rewound

p [1, 2].each.rewind.next
