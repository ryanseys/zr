# Enumerator: an iteration held as an object. One made by `to_enum`
# sends its method with the block it is given; one made with a block
# runs the block with a Yielder. External iteration (`next`, `peek`)
# runs the iteration on its own fiber, one value per resume, so an
# endless iteration is fine.
class Enumerator
  include Enumerable

  class Yielder
    def initialize(&block)
      @block = block
    end

    def <<(value)
      @block.call(value)
      self
    end

    def yield(*values)
      @block.call(*values)
    end

    alias call yield

    def to_proc
      block = @block
      proc { |*values| block.call(*values) }
    end
  end

  class Generator
    def initialize(&block)
      @block = block
    end

    def each(&block)
      @block.call(Yielder.new(&block))
    end

    def inspect = to_s
  end

  def initialize(size = nil, &block)
    raise ArgumentError, "tried to create Proc object without a block" unless block

    @generator = Generator.new(&block)
    @receiver = @generator
    @method = :each
    @args = []
    @kwargs = {}
    @size = size
  end

  # `Enumerator.produce(initial) { |prev| }`: the initial value, then
  # each block answer, until the block raises StopIteration.
  class Producer
    def initialize(initial, has_initial, block)
      @initial = initial
      @has_initial = has_initial
      @block = block
    end

    def each
      value = @initial
      if @has_initial
        yield value
      else
        value = @block.call(nil)
        yield value
      end
      loop do
        value = @block.call(value)
        yield value
      end
      self
    end
  end

  def self.produce(*initial, &block)
    raise ArgumentError, "wrong number of arguments (given #{initial.size}, expected 0..1)" if initial.size > 1
    raise ArgumentError, "no block given" unless block

    Producer.new(initial[0], !initial.empty?, block).to_enum(:each) { Float::INFINITY }
  end

  # `to_enum(:method, *args, **kwargs)`, with a size or a proc that
  # answers it.
  def self.for(receiver, method, args, kwargs, size)
    e = allocate
    e.send(:enumerate, receiver, method, args, kwargs, size)
    e
  end

  def each(*extra, &block)
    return self unless block

    @receiver.__send__(@method, *@args, *extra, **@kwargs, &block)
  end

  def size
    @size.is_a?(Proc) ? @size.call : @size
  end

  def with_index(offset = 0, &block)
    return to_enum(:with_index, offset) { size } unless block

    # nil counts from 0; anything else converts as rb_to_int does.
    indexed(offset.nil? ? 0 : implicit_integer(offset), &block)
  end

  def each_with_index(&block)
    return to_enum(:each_with_index) { size } unless block

    indexed(0, &block)
  end

  def with_object(memo)
    return to_enum(:with_object, memo) { size } unless block_given?

    each { |*values| yield(values.size <= 1 ? values[0] : values, memo) }
    memo
  end

  alias each_with_object with_object

  def next
    values = next_values
    values.size <= 1 ? values[0] : values
  end

  def peek
    values = peek_values
    values.size <= 1 ? values[0] : values
  end

  def next_values
    if @lookahead
      values = @lookahead
      @lookahead = nil
      return values
    end

    take_next
  end

  def peek_values
    @lookahead ||= take_next
    @lookahead.dup
  end

  def rewind
    @fiber = nil
    @lookahead = nil
    @stop = nil
    @feed = nil
    self
  end

  # The value the paused `yield` answers at the next `next`.
  def feed(value)
    raise TypeError, "feed value already set" if @feed

    @feed = [value]
    nil
  end

  def inspect
    parts = @args.map(&:inspect) + @kwargs.map { |k, v| "#{k}: #{v.inspect}" }
    args = parts.empty? ? "" : "(#{parts.join(', ')})"
    "#<Enumerator: #{@receiver.inspect}:#{@method}#{args}>"
  end

  private

  def indexed(offset)
    Primitive.attr! :hidden
    i = offset - 1
    each do |*values|
      i += 1
      yield(values.size <= 1 ? values[0] : values, i)
    end
  end

  # Each `next` resumes the fiber that runs the iteration; the block
  # yields every value set back as an array. When the iteration ends,
  # its answer becomes the StopIteration's result, and every later
  # `next` raises a fresh StopIteration caused by the first.
  def take_next
    Primitive.attr! :hidden
    raise_stop if @stop
    @fiber = Fiber.new { run } unless @fiber&.alive?
    fed = @feed
    @feed = nil
    values = @fiber.resume(fed&.first)
    if @stop
      @fiber = nil
      @lookahead = nil
      raise @stop
    end
    values
  end

  def run
    Primitive.attr! :hidden
    result = each { |*values| Fiber.yield(values) }
    @stop = StopIteration.new("iteration reached an end")
    Primitive.zr_hidden_set(@stop, :result, result)
    nil
  end

  def raise_stop
    Primitive.attr! :hidden
    e = StopIteration.new(@stop.message)
    Primitive.zr_hidden_set(e, :result, @stop.result)
    raise e, cause: @stop
  end

  def enumerate(receiver, method, args, kwargs, size)
    @receiver = receiver
    @method = method
    @args = args
    @kwargs = kwargs
    @size = size
  end
end

module Kernel
  def to_enum(method = :each, *args, **kwargs, &size)
    Enumerator.for(self, method, args, kwargs, size)
  end

  alias enum_for to_enum

  # What a builtin iterator answers without a block: its count comes
  # last.
  private def enum_with_size(method, *args, size)
    Enumerator.for(self, method, args, {}, size)
  end
end

# `1.step(10, 3)` and `(1..10).step(3)` without a block: an Enumerator
# that also answers its bounds and step.
class Enumerator::ArithmeticSequence < Enumerator
  attr_reader :begin, :end, :step

  def self.for(first, last, step, exclude_end, range = nil)
    seq = allocate
    seq.send(:sequence, first, last, step, exclude_end, range)
    seq
  end

  def exclude_end? = @exclude_end

  def each(&block)
    return self unless block
    return float_each(&block) if float?

    i = @begin
    if @step > 0
      while @end.nil? || (@exclude_end ? i < @end : i <= @end)
        yield i
        i += @step
      end
    else
      while @end.nil? || (@exclude_end ? i > @end : i >= @end)
        yield i
        i += @step
      end
    end
    self
  end

  def size
    return Float::INFINITY if @end.nil?
    return float_size if float?

    span = @end - @begin
    n = span / @step
    n -= 1 if @exclude_end && span % @step == 0
    n < 0 ? 0 : n + 1
  end

  def first(n = (none = true))
    return take(n) unless none

    each { |v| return v }
    nil
  end

  def last(n = (none = true))
    all = to_a
    none ? all.last : all.last(n)
  end

  def ==(other)
    other.is_a?(Enumerator::ArithmeticSequence) && @begin == other.begin && @end == other.end && @step == other.step && @exclude_end == other.exclude_end?
  end
  alias eql? ==
  alias === ==

  def hash = [@begin, @end, @step, @exclude_end].hash

  def inspect
    return "((#{@range.inspect}).step(#{@step}))" if @range

    "(#{@begin.inspect}.step(#{@end.inspect}#{@step == 1 ? '' : ", #{@step.inspect}"}))"
  end
  alias to_s inspect

  private

  def float?
    Primitive.attr! :hidden
    @begin.is_a?(Float) || @end.is_a?(Float) || @step.is_a?(Float)
  end

  # CRuby's float step: the count allows for rounding in the last
  # value, and each value is `begin + i * step`, held to `end`.
  def float_size
    Primitive.attr! :hidden
    count = float_count
    count.infinite? ? count : count.to_i
  end

  # The count as a Float, the way CRuby's ruby_float_step_size keeps
  # it: NaN and infinity travel through, so the walk reads them as
  # nothing to do and forever, and `size` reports them as ruby does.
  def float_count
    Primitive.attr! :hidden
    first = @begin.to_f
    last = @end.to_f
    unit = @step.to_f
    return Float::INFINITY if unit == 0
    return (unit > 0 ? first <= last : first >= last) ? 1 : 0 if unit.infinite?

    n = (last - first) / unit
    return n if n.nan? || n.infinite? == 1

    err = (first.abs + last.abs + (last - first).abs) / unit.abs * Float::EPSILON
    err = 0.5 if err > 0.5
    if @exclude_end
      return 0.0 if n <= 0

      n = n < 1 ? 0 : (n - err).floor
      d = (n + 1) * unit + first
      n += 1 if first < last ? d < last : (first > last && d > last)
    else
      return 0.0 if n < 0

      n = (n + err).floor
    end
    (n + 1).to_f
  end

  def float_each
    Primitive.attr! :hidden
    first = @begin.to_f
    unit = @step.to_f
    if @end.nil?
      i = 0
      while true
        yield first + i * unit
        i += 1
      end
    end
    last = @end.to_f
    count = float_count
    i = 0
    while i < count
      d = i * unit + first
      d = last if unit >= 0 ? last < d : d < last
      yield d
      i += 1
    end
    self
  end

  def sequence(first, last, step, exclude_end, range)
    @begin = first
    @end = last
    @step = step
    @exclude_end = exclude_end
    @range = range
    @receiver = self
    @method = :each
    @args = []
    @kwargs = {}
    @size = nil
  end
end

# A lazy enumerator is a chain of nodes. Each node reads its receiver,
# shows the method and arguments it was made with, and streams what
# it produces through the Yielder `each` is given; a node that stops
# early breaks out of its receiver's `each`. What a node yields keeps
# the receiver's value packing unless CRuby's node passes one value.
class Enumerator::Lazy < Enumerator
  def self.from(receiver)
    lazy = allocate
    lazy.send(:node, receiver, nil, [], :run_each, nil) { receiver.respond_to?(:size) ? receiver.size : nil }
    lazy
  end

  def initialize(receiver, size = nil, &block)
    raise ArgumentError, "tried to call lazy new without a block" unless block

    node(receiver, :each, [], :run_new, block) { size }
  end

  def each(&block)
    return self unless block

    __send__(@runner, Yielder.new(&block))
  end

  def size = @size.call

  def lazy = self

  def force(*) = to_a

  def eager
    Enumerator.for(self, :each, [], {}, proc { size })
  end

  def to_enum(method = :each, *args, **kwargs, &size)
    lazy = Enumerator::Lazy.allocate
    lazy.send(:node, self, method, args, :run_send, nil, kwargs) { size&.call }
    lazy
  end

  alias enum_for to_enum

  def map(&block)
    step(:map, :run_map, block, sized: true)
  end

  alias collect map

  def flat_map(&block)
    step(:flat_map, :run_flat_map, block)
  end

  alias collect_concat flat_map

  def select(&block)
    step(:select, :run_select, block)
  end

  alias filter select
  alias find_all select

  def filter_map(&block)
    step(:filter_map, :run_filter_map, block)
  end

  def reject(&block)
    step(:reject, :run_reject, block)
  end

  def take_while(&block)
    step(:take_while, :run_take_while, block)
  end

  def drop_while(&block)
    step(:drop_while, :run_drop_while, block)
  end

  def take(n)
    n = implicit_integer(n)
    raise ArgumentError, "attempt to take negative size" if n < 0

    step(:take, :run_take, nil, [n], check: false) do
      s = @receiver.size
      s.nil? ? nil : (s > n ? n : s)
    end
  end

  def drop(n)
    n = implicit_integer(n)
    raise ArgumentError, "attempt to drop negative size" if n < 0

    step(:drop, :run_drop, nil, [n], check: false) do
      s = @receiver.size
      s.nil? ? nil : (s > n ? s - n : 0)
    end
  end

  def grep(pattern, &block)
    step(:grep, block ? :run_grep_map : :run_grep, block, [pattern], check: false)
  end

  def grep_v(pattern, &block)
    step(:grep_v, block ? :run_grep_v_map : :run_grep_v, block, [pattern], check: false)
  end

  def zip(*others, &block)
    return super if block

    others.each do |other|
      next if other.is_a?(Array) || other.respond_to?(:each)

      raise TypeError, "wrong argument type #{other.class} (must respond to :each)"
    end
    step(:zip, :run_zip, nil, others, check: false, sized: true)
  end

  def uniq(&block)
    step(:uniq, :run_uniq, block, check: false)
  end

  def compact
    step(:compact, :run_compact, nil, check: false)
  end

  def with_index(offset = 0, &block)
    offset = 0 if offset.nil?
    step(:with_index, block ? :run_with_index_each : :run_with_index, block, [offset], check: false, sized: true)
  end

  # The chunking methods stay Enumerable's, their enumerator made lazy.
  def chunk(&block) = Enumerator::Lazy.from(super)

  def chunk_while(&block) = Enumerator::Lazy.from(super)

  def slice_when(&block) = Enumerator::Lazy.from(super)

  def slice_before(*, &block) = Enumerator::Lazy.from(super)

  def slice_after(*, &block) = Enumerator::Lazy.from(super)

  def inspect
    parts = @args.map(&:inspect)
    args = parts.empty? ? "" : "(#{parts.join(', ')})"
    method = @method ? ":#{@method}" : ""
    "#<Enumerator::Lazy: #{@receiver.inspect}#{method}#{args}>"
  end

  # The eager forms, under the names CRuby keeps them by.
  %i[map collect flat_map collect_concat select filter find_all filter_map reject grep grep_v zip take take_while drop drop_while uniq].each do |name|
    define_method(:"_enumerable_#{name}", Enumerable.instance_method(name))
    private :"_enumerable_#{name}"
  end
  define_method(:_enumerable_with_index, Enumerator.instance_method(:with_index))
  private :_enumerable_with_index

  private

  def node(receiver, method, args, runner, block, kwargs = {}, &size)
    @receiver = receiver
    @method = method
    @args = args
    @kwargs = kwargs
    @runner = runner
    @block = block
    @size = size
  end

  # The node one lazy method adds: named after that method, sized
  # like its receiver when `sized`, and refused without a block when
  # `check`.
  def step(method, runner, block, args = [], check: true, sized: false, &size)
    Primitive.attr! :hidden
    raise ArgumentError, "tried to call lazy #{method} without a block" if check && block.nil?

    size ||= sized ? proc { @receiver.size } : proc { nil }
    lazy = Enumerator::Lazy.allocate
    lazy.send(:node, self, method, args, runner, block, &size)
    lazy
  end

  def run_each(y)
    Primitive.attr! :hidden
    @receiver.each { |*values| y.yield(*values) }
  end

  def run_new(y)
    Primitive.attr! :hidden
    block = @block
    @receiver.each { |*values| block.call(y, *values); nil }
    nil
  end

  def run_send(y)
    Primitive.attr! :hidden
    @receiver.__send__(@method, *@args, **@kwargs) { |*values| y.yield(*values); nil }
  end

  def run_map(y)
    Primitive.attr! :hidden
    block = @block
    @receiver.each { |*values| y << block.call(*values); nil }
    nil
  end

  def run_flat_map(y)
    Primitive.attr! :hidden
    block = @block
    @receiver.each do |*values|
      result = block.call(*values)
      if result.is_a?(Array) || (result.respond_to?(:force) && result.respond_to?(:each))
        result.each { |v| y << v }
      else
        y << result
      end
      nil
    end
    nil
  end

  def run_select(y)
    Primitive.attr! :hidden
    block = @block
    @receiver.each { |*values| y.yield(*values) if block.call(*values); nil }
    nil
  end

  def run_filter_map(y)
    Primitive.attr! :hidden
    block = @block
    @receiver.each do |*values|
      result = block.call(*values)
      y << result if result
      nil
    end
    nil
  end

  def run_reject(y)
    Primitive.attr! :hidden
    block = @block
    @receiver.each { |*values| y.yield(*values) unless block.call(*values); nil }
    nil
  end

  def run_take_while(y)
    Primitive.attr! :hidden
    block = @block
    @receiver.each do |*values|
      break unless block.call(*values)

      y.yield(*values)
      nil
    end
    nil
  end

  def run_drop_while(y)
    Primitive.attr! :hidden
    block = @block
    dropping = true
    @receiver.each do |*values|
      dropping = false if dropping && !block.call(*values)
      y.yield(*values) unless dropping
      nil
    end
    nil
  end

  def run_take(y)
    Primitive.attr! :hidden
    n = @args[0]
    return nil if n == 0

    taken = 0
    @receiver.each do |*values|
      y.yield(*values)
      taken += 1
      break if taken == n

      nil
    end
    nil
  end

  def run_drop(y)
    Primitive.attr! :hidden
    n = @args[0]
    seen = 0
    @receiver.each do |*values|
      y.yield(*values) if seen >= n
      seen += 1
      nil
    end
    nil
  end

  def run_grep(y)
    Primitive.attr! :hidden
    pattern = @args[0]
    @receiver.each { |*values| y.yield(*values) if pattern === Primitive.zr_enum_value(values); nil }
    nil
  end

  def run_grep_map(y)
    Primitive.attr! :hidden
    pattern = @args[0]
    block = @block
    @receiver.each do |*values|
      x = Primitive.zr_enum_value(values)
      y << block.call(x) if pattern === x
      nil
    end
    nil
  end

  def run_grep_v(y)
    Primitive.attr! :hidden
    pattern = @args[0]
    @receiver.each { |*values| y.yield(*values) unless pattern === Primitive.zr_enum_value(values); nil }
    nil
  end

  def run_grep_v_map(y)
    Primitive.attr! :hidden
    pattern = @args[0]
    block = @block
    @receiver.each do |*values|
      x = Primitive.zr_enum_value(values)
      y << block.call(x) unless pattern === x
      nil
    end
    nil
  end

  # Arrays are read by index; anything else is read with `next`, and
  # answers nil once it stops.
  def run_zip(y)
    Primitive.attr! :hidden
    cursors = @args.map { |other| other.is_a?(Array) ? other : other.to_enum }
    i = 0
    @receiver.each do |*values|
      row = [Primitive.zr_enum_value(values)]
      cursors.each do |cursor|
        row << if cursor.is_a?(Array)
                 cursor[i]
               else
                 begin
                   cursor.next
                 rescue StopIteration
                   nil
                 end
               end
      end
      y << row
      i += 1
      nil
    end
    nil
  end

  def run_uniq(y)
    Primitive.attr! :hidden
    block = @block
    seen = {}
    @receiver.each do |*values|
      key = block ? block.call(*values) : Primitive.zr_enum_value(values)
      unless seen.key?(key)
        seen[key] = true
        y.yield(*values)
      end
      nil
    end
    nil
  end

  def run_compact(y)
    Primitive.attr! :hidden
    @receiver.each { |*values| y.yield(*values) unless Primitive.zr_enum_value(values).nil?; nil }
    nil
  end

  def run_with_index(y)
    Primitive.attr! :hidden
    i = @args[0]
    @receiver.each do |*values|
      y << [Primitive.zr_enum_value(values), i]
      i = implicit_integer(i) + 1
      nil
    end
    nil
  end

  def run_with_index_each(y)
    Primitive.attr! :hidden
    block = @block
    i = @args[0]
    @receiver.each do |*values|
      x = Primitive.zr_enum_value(values)
      block.call(x, i)
      y << x
      i = implicit_integer(i) + 1
      nil
    end
    nil
  end
end

# `a.chain(b, c)`: the enumerables one after another.
class Enumerator::Chain < Enumerator
  def initialize(*enums)
    @enums = enums
  end

  # Without a block, CRuby wraps the chain twice.
  def each(*args, &block)
    return to_enum(:each, *args).to_enum(:each) unless block

    @enums.each { |e| e.each(*args, &block) }
    self
  end

  # The sizes added; nil when one is unknown, Infinity when one is.
  def size
    total = 0
    @enums.each do |e|
      n = e.respond_to?(:size) ? e.size : nil
      return nil if n.nil?
      return n if n.is_a?(Float) && n.infinite?

      total += n
    end
    total
  end

  def rewind
    @enums.reverse_each { |e| e.rewind if e.respond_to?(:rewind) }
    self
  end

  def +(other) = Enumerator::Chain.new(self, other)

  def inspect = "#<Enumerator::Chain: #{@enums.inspect}>"

  alias to_s inspect

  undef_method :next, :peek, :next_values, :peek_values, :with_object
end

class Enumerator
  def +(other) = Enumerator::Chain.new(self, other)
end

# `Enumerator.product(a, b)`: every combination, the last enumerable
# varying fastest.
class Enumerator::Product < Enumerator
  def initialize(*enums)
    @enums = enums
  end

  def each(&block)
    return to_enum(:each) unless block

    walk(0, [], &block)
    self
  end

  def size
    total = 1
    @enums.each do |e|
      n = e.respond_to?(:size) ? e.size : nil
      return nil if n.nil?
      return n if n.is_a?(Float) && n.infinite?

      total *= n
    end
    total
  end

  def rewind
    @enums.reverse_each { |e| e.rewind if e.respond_to?(:rewind) }
    self
  end

  def inspect = "#<Enumerator::Product: #{@enums.inspect}>"

  alias to_s inspect

  private

  def walk(depth, picked, &block)
    return yield(picked.dup) if depth == @enums.size

    @enums[depth].each_entry do |x|
      picked << x
      walk(depth + 1, picked, &block)
      picked.pop
    end
  end
end

class Enumerator
  def self.product(*enums, **nothing, &block)
    raise ArgumentError, "unknown keywords: #{nothing.keys.map(&:inspect).join(', ')}" unless nothing.empty?

    product = Enumerator::Product.new(*enums)
    return product unless block

    product.each(&block)
    nil
  end
end
