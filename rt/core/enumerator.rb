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

  def with_index(offset = 0)
    return to_enum(:with_index, offset) { size } unless block_given?

    i = offset - 1
    each do |*values|
      i += 1
      yield(values.size <= 1 ? values[0] : values, i)
    end
  end

  def each_with_index(&block)
    return to_enum(:each_with_index) { size } unless block

    with_index(0, &block)
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
    self
  end

  def inspect
    parts = @args.map(&:inspect) + @kwargs.map { |k, v| "#{k}: #{v.inspect}" }
    args = parts.empty? ? "" : "(#{parts.join(', ')})"
    "#<Enumerator: #{@receiver.inspect}:#{@method}#{args}>"
  end

  alias to_s inspect

  private

  # Each `next` resumes the fiber that runs the iteration; the block
  # yields every value set back as an array. When the iteration ends,
  # its answer becomes the StopIteration's result, and every later
  # `next` raises a fresh StopIteration caused by the first.
  def take_next
    Primitive.attr! :hidden
    raise_stop if @stop
    @fiber = Fiber.new { run } unless @fiber&.alive?
    values = @fiber.resume
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

  def each
    return self unless block_given?

    i = @begin
    return self if @range && @step < 0
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
    return Primitive.zr_unimplemented("an endless ArithmeticSequence's size, which is Infinity") if @end.nil?
    return 0 if @range && @step < 0

    span = @end - @begin
    n = span / @step
    n -= 1 if @exclude_end && span % @step == 0
    n < 0 ? 0 : n + 1
  end

  def first(n = nil)
    return take(n) unless n.nil?

    each { |v| return v }
    nil
  end

  def last(n = nil)
    all = to_a
    n.nil? ? all.last : all.last(n)
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
