# Enumerator: an iteration held as an object. One made by `to_enum`
# sends its method with the block it is given; one made with a block
# runs the block with a Yielder. External iteration (`next`, `peek`)
# reads a buffer the whole iteration fills, so it does not suit an
# endless one.
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
    @size = size
  end

  # `to_enum(:method, *args)`, with a size or a proc that answers it.
  def self.for(receiver, method, args, size)
    e = allocate
    e.send(:enumerate, receiver, method, args, size)
    e
  end

  def each(*extra, &block)
    return self unless block

    @receiver.__send__(@method, *@args, *extra, &block)
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
    buffer = @buffer ||= to_a
    @position ||= 0
    raise StopIteration, "iteration reached an end" if @position >= buffer.size

    value = buffer[@position]
    @position += 1
    value
  end

  def peek
    buffer = @buffer ||= to_a
    @position ||= 0
    raise StopIteration, "iteration reached an end" if @position >= buffer.size

    buffer[@position]
  end

  def rewind
    @buffer = nil
    @position = 0
    self
  end

  def inspect
    args = @args.empty? ? "" : "(#{@args.map(&:inspect).join(', ')})"
    "#<Enumerator: #{@receiver.inspect}:#{@method}#{args}>"
  end

  alias to_s inspect

  private

  def enumerate(receiver, method, args, size)
    @receiver = receiver
    @method = method
    @args = args
    @size = size
  end
end

module Kernel
  def to_enum(method = :each, *args, &size)
    Enumerator.for(self, method, args, size)
  end

  alias enum_for to_enum

  # What a builtin iterator answers without a block: its count comes
  # last.
  private def enum_with_size(method, *args, size)
    Enumerator.for(self, method, args, size)
  end
end
