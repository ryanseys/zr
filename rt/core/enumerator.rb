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

    def to_proc
      block = @block
      proc { |*values| block.call(*values) }
    end
  end

  # The block an `Enumerator.new` runs, which is an Enumerable of its own
  # and holds the block where no program sees it.
  class Generator
    include Enumerable

    def initialize(&block)
      raise LocalJumpError, "no block given" unless block

      Primitive.zr_hidden_set(self, :__block__, block)
      self
    end

    # Any arguments a caller adds are the yielder's to ignore, as CRuby's
    # own row takes them and answers an arity of -1.
    def each(*, &block)
      Primitive.zr_hidden_get(self, :__block__).call(Yielder.new(&block))
    end

    private

    def initialize_copy(other)
      super
      Primitive.zr_hidden_set(self, :__block__, Primitive.zr_hidden_get(other, :__block__))
      self
    end
  end

  def initialize(size = nil, &block)
    raise ArgumentError, "tried to create Proc object without a block" unless block

    @generator = Generator.new(&block)
    @receiver = @generator
    @method = :each
    @args = []
    @kwargs = {}
    @size = size
    self
  end

  # `Enumerator.produce(initial) { |prev| }`: the initial value, then
  # each block answer, until the block raises StopIteration.
  class Producer
    def initialize(initial, has_initial, block)
      Primitive.zr_hidden_set(self, :__initial__, initial)
      Primitive.zr_hidden_set(self, :__has_initial__, has_initial)
      Primitive.zr_hidden_set(self, :__block__, block)
    end

    def each
      block = Primitive.zr_hidden_get(self, :__block__)
      value = Primitive.zr_hidden_get(self, :__initial__)
      if Primitive.zr_hidden_get(self, :__has_initial__)
        yield value
      else
        value = block.call(nil)
        yield value
      end
      loop do
        value = block.call(value)
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
    Primitive.attr! :hidden
    e = allocate
    e.send(:enumerate, receiver, method, args, kwargs, size)
    e
  end

  def each(*extra, &block)
    initialized!
    return self unless block

    @receiver.__send__(@method, *@args, *extra, **@kwargs, &block)
  end

  def size
    initialized!
    @size.is_a?(Proc) ? @size.call : @size
  end

  # Without a block, the enumerator shows the offset only as it was given.
  def with_index(offset = (omitted = true; nil), &block)
    return to_enum(:with_index, *([offset] unless omitted)) { size } unless block

    # nil counts from 0; anything else converts as rb_to_int does.
    indexed(offset.nil? ? 0 : implicit_integer(offset), &block)
  end

  def each_with_index(&block)
    return to_enum(:each_with_index) { size } unless block

    indexed(0, &block)
  end

  def with_object(memo)
    return to_enum(:with_object, memo) { size } unless block_given?

    Primitive.zr_enum_each(self, nil) { |x| yield(x, memo) }
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
    initialized!
    if @lookahead
      values = @lookahead
      @lookahead = nil
      return values
    end

    take_next
  end

  def peek_values
    initialized!
    @lookahead ||= take_next
    @lookahead.dup
  end

  def rewind
    initialized!
    # The object is asked first: one that knows how to start again says
    # so, and `enumerator_rewind` asks with rb_check_funcall, which
    # reaches a method the object keeps private and lets an object with
    # no such method alone.
    @receiver.__send__(:rewind) if @receiver.respond_to?(:rewind, true)
    @fiber = nil
    @lookahead = nil
    @stop = nil
    @feed = nil
    self
  end

  # The value the paused `yield` answers at the next `next`.
  def feed(value)
    initialized!
    raise TypeError, "feed value already set" if @feed

    @feed = [value]
    nil
  end

  # A lazy shows what it was made with rather than what `each` runs.
  def inspect
    return Primitive.zr_obj_form("#<#{self.class}: uninitialized>") unless @method

    receiver, method, args, kwargs = @shown || [@receiver, @method, @args, @kwargs]
    return Primitive.zr_obj_form("#<#{self.class}: ...>") if Primitive.zr_recursive_enter(self, :inspect)

    begin
      parts = args.map(&:inspect) + kwargs.map { |k, v| "#{k}: #{v.inspect}" }
      shown = parts.empty? ? "" : "(#{parts.join(', ')})"
      Primitive.zr_obj_form("#<#{self.class}: #{receiver.inspect}#{":#{method}" if method}#{shown}>")
    ensure
      Primitive.zr_recursive_leave(self, :inspect)
    end
  end

  private

  # enumerator_ptr: an allocated enumerator has nothing to iterate.
  def initialized!
    Primitive.attr! :hidden
    raise ArgumentError, "uninitialized enumerator" unless @method
  end

  # enumerator_with_index_i: the values `each` yields packed as
  # rb_enum_values_pack packs them, with the index beside them, and the
  # block's own answer handed back to `each`. The packing is the
  # kernel's (`zr_enum_each`) and not a `|*values|` parameter, which
  # made an Array of every element -- and the assembler walks every
  # instruction of every function this way.
  def indexed(offset)
    Primitive.attr! :hidden
    i = offset - 1
    Primitive.zr_enum_each(self, nil) do |x|
      i += 1
      yield(x, i)
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
    Primitive.attr! :hidden
    @receiver = receiver
    @method = method
    @args = args
    @kwargs = kwargs
    @size = size
  end

  # What a copy iterates is what the other iterates; where the other is
  # in an external iteration is a fiber's stack, which does not copy.
  def initialize_copy(other)
    super
    raise TypeError, "can't copy execution context" if Primitive.zr_hidden_get(other, :fiber)

    @generator = Primitive.zr_hidden_get(other, :generator)
    enumerate(*%i[receiver method args kwargs size].map { |name| Primitive.zr_hidden_get(other, name) })
    @fiber = @lookahead = @stop = @feed = nil
    self
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
    Primitive.attr! :hidden
    Enumerator.for(self, method, args, {}, size)
  end
end

# `1.step(10, 3)` and `(1..10).step(3)` without a block: an Enumerator
# that also answers its bounds and step, CRuby's enumerator.c arith_seq.
# It keeps the call that made it, which `inspect` replays.
class Enumerator::ArithmeticSequence < Enumerator
  attr_reader :begin, :end, :step

  # rb_arith_seq_new: `receiver.method(*args, **kwargs)` made the sequence
  # from `first` to `last` by `step`.
  def self.for(receiver, method, args, kwargs, first, last, step, exclude_end)
    Primitive.attr! :hidden
    seq = allocate
    seq.send(:sequence, [receiver, method, args, kwargs], first, last, step, exclude_end)
    seq
  end

  def exclude_end? = @exclude_end

  # arith_seq_each: a Float anywhere walks as ruby_float_step does;
  # otherwise the last element is computed first, and the walk stops
  # there.
  def each(&block)
    return self unless block
    return float_walk(float_count, &block) if float?

    c = @begin
    if @end.nil?
      while true
        yield c
        c += @step
      end
    end
    while @step == 0
      yield c
    end
    last = last_element
    if @step < 0
      while c >= last
        yield c
        c += @step
      end
    else
      while last >= c
        yield c
        c += @step
      end
    end
    self
  end

  # arith_seq_size: counted, never walked.
  def size
    if float?
      n = float_count
      return n.infinite? ? n : n.to_i
    end
    return Float::INFINITY if @end.nil?

    step = @step.is_a?(Numeric) ? @step : to_integer(@step)
    return Float::INFINITY if step == 0

    len_1 = (@end - @begin).div(step)
    return 0 if len_1.negative?

    @exclude_end && @begin + (step * len_1) == @end ? len_1 : len_1 + 1
  end

  # arith_seq_first: `begin` itself, unless the sequence is empty; with a
  # count, a walk.
  def first(n = (none = true))
    return taken(n) unless none
    return nil if @begin.nil?

    unless @end.nil?
      direction = @step <=> 0
      return nil if direction.positive? && @begin > @end
      return nil if direction.negative? && @begin < @end
    end
    @begin
  end

  private

  # arith_seq_take: a Float anywhere takes as the walk does.
  def taken(n)
    Primitive.attr! :hidden
    n = implicit_integer(n)
    raise ArgumentError, "attempt to take negative size" if n.negative?
    return [] if n.zero?
    if float?
      out = []
      float_walk([n, float_count].min) { |d| out << d }
      return out
    end

    out = []
    each do |v|
      out << v
      break if out.size == n
    end
    out
  end

  public

  # arith_seq_last: computed from the four parts, not walked.
  def last(n = (none = true))
    raise RangeError, "cannot get the last element of endless arithmetic sequence" if @end.nil?

    len_1 = idiv(@end - @begin, @step)
    return none ? nil : [] if len_1.negative?

    last = @begin + (@step * len_1)
    adjusted = @exclude_end && last == @end
    last -= @step if adjusted
    return last if none

    count = adjusted ? len_1 : len_1 + 1
    n = to_integer(n)
    n = count if n > count
    raise ArgumentError, "negative array size" if n.negative?

    out = []
    value = last - (@step * n)
    n.times { out << (value += @step) }
    out
  end

  def ==(other)
    other.is_a?(Enumerator::ArithmeticSequence) && @begin == other.begin && @end == other.end && @step == other.step &&
      @exclude_end == other.exclude_end?
  end
  alias eql? ==
  alias === ==

  def hash = [@exclude_end, @begin, @end, @step].hash

  # arith_seq_inspect: the call again, a Range receiver in parentheses,
  # and keywords as a call spells them.
  def inspect
    receiver, method, args, kwargs = @call
    shown = receiver.is_a?(Range) ? "(#{receiver})" : receiver.to_s
    parts = args.map(&:inspect) + kwargs.map { |key, value| "#{key}: #{value.inspect}" }
    "(#{shown}.#{method}#{"(#{parts.join(', ')})" unless parts.empty?})"
  end

  private

  def sequence(call, first, last, step, exclude_end)
    Primitive.attr! :hidden
    @call = call
    @begin = first
    @end = last
    @step = step
    @exclude_end = exclude_end
    @receiver = self
    @method = :each
    @args = []
    @kwargs = {}
    @size = nil
  end

  def float?
    Primitive.attr! :hidden
    @begin.is_a?(Float) || @end.is_a?(Float) || @step.is_a?(Float)
  end

  # The last element a whole walk would reach: `begin` plus as many whole
  # steps as fit, one fewer where an excluded end is met exactly.
  def last_element
    Primitive.attr! :hidden
    last = @begin + (@step * idiv(@end - @begin, @step))
    @exclude_end && last == @end ? last - @step : last
  end

  # num_idiv: a quotient taken down to a whole number.
  def idiv(a, b)
    Primitive.attr! :hidden
    q = a.is_a?(Integer) ? a.div(b) : a / b
    q.is_a?(Integer) ? q : q.floor
  end

  # ruby_float_step_size: the count allows for rounding in the last
  # value. NaN and infinity travel through, so the walk reads them as
  # nothing to do and forever, and `size` reports them as ruby does.
  def float_count
    Primitive.attr! :hidden
    first = @begin.to_f
    unit = @step.to_f
    last = @end.nil? ? (unit < 0 ? -Float::INFINITY : Float::INFINITY) : @end.to_f
    return Float::INFINITY if unit == 0
    return (unit > 0 ? first <= last : first >= last) ? 1.0 : 0.0 if unit.infinite?

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

  # ruby_float_step: `count` values, each `begin + i * step`, held to the
  # end.
  def float_walk(count)
    Primitive.attr! :hidden
    first = @begin.to_f
    unit = @step.to_f
    last = @end.nil? ? (unit < 0 ? -Float::INFINITY : Float::INFINITY) : @end.to_f
    if unit.infinite?
      yield first if count.positive?
    elsif unit == 0
      yield first while true
    else
      i = 0
      while i < count
        d = i * unit + first
        d = last if unit >= 0 ? last < d : d < last
        yield d
        i += 1
      end
    end
    self
  end
end

# A lazy enumerator is an Enumerator whose `each` runs a chain of steps.
# Each lazy holds one Step: the receiver it reads, and the runner that
# streams what it produces to the block `each` is given; a step that
# stops early breaks out of its receiver's `each`. What a step yields
# keeps the receiver's value packing unless CRuby's step passes one
# value. `inspect` shows the receiver, method and arguments the lazy was
# made with, which CRuby keeps apart from what `each` runs, as here.
class Enumerator::Lazy < Enumerator
  def self.from(receiver)
    Primitive.attr! :hidden
    allocate.send(:chain, receiver, false, :run_each) { receiver.respond_to?(:size) ? receiver.size : nil }
  end

  def initialize(receiver, size = nil, &block)
    raise ArgumentError, "tried to call lazy new without a block" unless block

    chain(receiver, :each, :run_new, block:) { size }
  end

  def lazy = self

  def force(*) = to_a

  def eager
    Enumerator.for(self, :each, [], {}, proc { size })
  end

  def to_enum(method = :each, *args, **kwargs, &size)
    Enumerator::Lazy.allocate.send(:chain, self, method, :run_send, args:, kwargs:) { size&.call }
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

    step(:take, :run_take, nil, [n], check: false) { size&.clamp(..n) }
  end

  def drop(n)
    n = implicit_integer(n)
    raise ArgumentError, "attempt to drop negative size" if n < 0

    step(:drop, :run_drop, nil, [n], check: false) { size && [size - n, 0].max }
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
  def chunk(*, &block) = Enumerator::Lazy.from(super)

  def chunk_while(*, &block) = Enumerator::Lazy.from(super)

  def slice_when(*, &block) = Enumerator::Lazy.from(super)

  def slice_before(*, &block) = Enumerator::Lazy.from(super)

  def slice_after(*, &block) = Enumerator::Lazy.from(super)

  # The eager forms, under the names CRuby keeps them by: aliases of
  # Enumerable's, and a definition of `with_index` of its own, so the
  # enumerator it answers without a block names it.
  %i[map collect flat_map collect_concat select filter find_all filter_map reject grep grep_v zip take take_while drop drop_while uniq].each do |name|
    define_method(:"_enumerable_#{name}", Enumerable.instance_method(name))
    private :"_enumerable_#{name}"
  end

  private

  def _enumerable_with_index(offset = (omitted = true; nil), &block)
    return to_enum(:_enumerable_with_index, *([offset] unless omitted)) { size } unless block

    indexed(offset.nil? ? 0 : implicit_integer(offset), &block)
  end

  # This lazy, reading `receiver` through `runner`, and shown as
  # `receiver`, `method` and `args`; a false `method` shows none.
  def chain(receiver, method, runner, block: nil, args: [], kwargs: {}, &size)
    Primitive.attr! :hidden
    enumerate(Step.new(receiver, method, runner, block, args, kwargs), :each, [], {}, size)
    @shown = [receiver, method, args, kwargs]
    self
  end

  # The lazy one method adds to this one: named after that method, sized
  # like this one when `sized`, and refused without a block when `check`.
  def step(method, runner, block, args = [], check: true, sized: false, &size)
    Primitive.attr! :hidden
    raise ArgumentError, "tried to call lazy #{method} without a block" if check && block.nil?

    size ||= sized ? proc { self.size } : proc {}
    Enumerator::Lazy.allocate.send(:chain, self, method, runner, block:, args:, &size)
  end

  # What a lazy's `each` runs: its receiver, through one runner.
  class Step
    def initialize(receiver, method, runner, block, args, kwargs)
      @receiver = receiver
      @method = method
      @runner = runner
      @block = block
      @args = args
      @kwargs = kwargs
    end

    # Any arguments a caller adds are ignored, as CRuby's generator
    # ignores them.
    def each(*, &)
      __send__(@runner, &)
    end

    private

    def run_each(&)
      @receiver.each(&)
    end

    def run_new(&)
      block = @block
      y = Enumerator::Yielder.new(&)
      @receiver.each { |*values| block.call(y, *values); nil }
      nil
    end

    def run_send
      @receiver.__send__(@method, *@args, **@kwargs) { |*values| yield(*values); nil }
    end

    # The four stages that keep no state go through the kernel's
    # adapter (zr_lazy_stage), which reads an element without the
    # `|*values|` Array the others pay once an element.
    def run_map(&out) = Primitive.zr_lazy_map(@receiver, @block, out)

    def run_select(&out) = Primitive.zr_lazy_select(@receiver, @block, out)

    def run_reject(&out) = Primitive.zr_lazy_reject(@receiver, @block, out)

    def run_filter_map(&out) = Primitive.zr_lazy_filter_map(@receiver, @block, out)

    def run_flat_map
      block = @block
      @receiver.each do |*values|
        result = block.call(*values)
        if result.is_a?(Array) || (result.respond_to?(:force) && result.respond_to?(:each))
          result.each { |v| yield v }
        else
          yield result
        end
        nil
      end
      nil
    end

    def run_take_while
      block = @block
      @receiver.each do |*values|
        break unless block.call(*values)

        yield(*values)
        nil
      end
      nil
    end

    def run_drop_while
      block = @block
      dropping = true
      @receiver.each do |*values|
        dropping = false if dropping && !block.call(*values)
        yield(*values) unless dropping
        nil
      end
      nil
    end

    def run_take
      n = @args[0]
      return nil if n == 0

      taken = 0
      @receiver.each do |*values|
        yield(*values)
        taken += 1
        break if taken == n

        nil
      end
      nil
    end

    def run_drop
      n = @args[0]
      seen = 0
      @receiver.each do |*values|
        yield(*values) if seen >= n
        seen += 1
        nil
      end
      nil
    end

    def run_grep
      pattern = @args[0]
      @receiver.each { |*values| yield(*values) if pattern === Primitive.zr_enum_value(values); nil }
      nil
    end

    def run_grep_map
      pattern = @args[0]
      block = @block
      @receiver.each do |*values|
        x = Primitive.zr_enum_value(values)
        yield block.call(x) if pattern === x
        nil
      end
      nil
    end

    def run_grep_v
      pattern = @args[0]
      @receiver.each { |*values| yield(*values) unless pattern === Primitive.zr_enum_value(values); nil }
      nil
    end

    def run_grep_v_map
      pattern = @args[0]
      block = @block
      @receiver.each do |*values|
        x = Primitive.zr_enum_value(values)
        yield block.call(x) unless pattern === x
        nil
      end
      nil
    end

    # Arrays are read by index; anything else is read with `next`, and
    # answers nil once it stops.
    def run_zip
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
        yield row
        i += 1
        nil
      end
      nil
    end

    def run_uniq
      block = @block
      seen = {}
      @receiver.each do |*values|
        key = block ? block.call(*values) : Primitive.zr_enum_value(values)
        unless seen.key?(key)
          seen[key] = true
          yield(*values)
        end
        nil
      end
      nil
    end

    def run_compact
      @receiver.each { |*values| yield(*values) unless Primitive.zr_enum_value(values).nil?; nil }
      nil
    end

    def run_with_index
      i = @args[0]
      @receiver.each do |*values|
        yield [Primitive.zr_enum_value(values), i]
        i = implicit_integer(i) + 1
        nil
      end
      nil
    end

    def run_with_index_each
      block = @block
      i = @args[0]
      @receiver.each do |*values|
        x = Primitive.zr_enum_value(values)
        block.call(x, i)
        yield x
        i = implicit_integer(i) + 1
        nil
      end
      nil
    end
  end
  private_constant :Step
end

# `a.chain(b, c)`: the enumerables one after another.
class Enumerator::Chain < Enumerator
  def initialize(*enums)
    @enums = enums
    self
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

  def inspect = Primitive.zr_obj_form("#<Enumerator::Chain: #{@enums.inspect}>")

  private def initialize_copy(other)
    Kernel.instance_method(:initialize_copy).bind_call(self, other)
    @enums = Primitive.zr_hidden_get(other, :enums).dup
    self
  end


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
    self
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

  def inspect = Primitive.zr_obj_form("#<Enumerator::Product: #{@enums.inspect}>")

  private def initialize_copy(other)
    Kernel.instance_method(:initialize_copy).bind_call(self, other)
    @enums = Primitive.zr_hidden_get(other, :enums).dup
    self
  end


  private

  def walk(depth, picked, &block)
    Primitive.attr! :hidden
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
