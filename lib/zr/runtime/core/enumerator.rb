# frozen_string_literal: true

# Enumerator: an iteration as an object. One made by `to_enum` sends
# its method with the block it is given. One made with a block runs the
# block with a Yielder. External iteration (`next`, `peek`) runs the
# iteration on its own fiber, one value per resume, so an endless
# iteration is fine.
class Enumerator
  include Enumerable

  class Yielder
    def initialize(&block)
      raise LocalJumpError, +"no block given" unless block

      @block = block
      self
    end

    def <<(value)
      @block.call(value)
      self
    end

    # Keywords go on to the block, as yielder_yield passes them. Only
    # keywords given go on: an empty `**` would keep a lone Array whole.
    # One value, the common call, takes no Array.
    def yield(value = (none = true; nil), *more, **keywords)
      unless Primitive.zr_hash_len_m(keywords) == 0
        return none ? @block.call(**keywords) : @block.call(value, *more, **keywords)
      end
      return @block.call if none
      return @block.call(value) if Primitive.zr_ary_len_m(more) == 0

      @block.call(value, *more)
    end

    # yielder_to_proc: a lambda that yields its arguments.
    def to_proc = method(:yield).to_proc
  end

  # The block that an `Enumerator.new` runs. It is an Enumerable of its
  # own and keeps the block hidden from programs.
  class Generator
    include Enumerable

    # generator_initialize: the block, or a Proc given in its place.
    def initialize(*args, &block)
      raise ArgumentError, wrong_arity(args.size, 1) if args.size > 1

      if args.empty?
        raise LocalJumpError, +"no block given" unless block
      else
        block = args[0]
        raise TypeError, "wrong argument type #{block.class} (expected Proc)" unless block.is_a?(Proc)
      end
      Primitive.zr_frozen_error(self) if frozen?

      Primitive.zr_hidden_set(self, :__block__, block)
      self
    end

    # generator_each: the arguments a caller adds go to the block after
    # the yielder.
    def each(*args, &block)
      Primitive.zr_hidden_get(self, :__block__).call(Yielder.new(&block), *args)
    end

    private

    def initialize_copy(other)
      super
      Primitive.zr_hidden_set(self, :__block__, Primitive.zr_hidden_get(other, :__block__))
      self
    end
  end

  def initialize(size = nil, &block)
    raise ArgumentError, +"tried to create Proc object without a block" unless block

    @generator = Generator.new(&block)
    @receiver = @generator
    @method = :each
    @args = []
    @kwargs = {}
    @size = Enumerator.send(:feasible_size, size)
    self
  end

  # `Enumerator.produce(initial) { |prev| }`: the initial value, then
  # each block return value, until the block raises StopIteration.
  class Producer
    def initialize(initial, has_initial, block)
      Primitive.attr! :hidden
      Primitive.zr_hidden_set(self, :__initial__, initial)
      Primitive.zr_hidden_set(self, :__has_initial__, has_initial)
      Primitive.zr_hidden_set(self, :__block__, block)
    end

    # producer_each: a loop in C under rb_rescue2, so no frame of loop,
    # and a StopIteration ends it with its result.
    def each
      block = Primitive.zr_hidden_get(self, :__block__)
      value = Primitive.zr_hidden_get(self, :__initial__)
      begin
        if Primitive.zr_hidden_get(self, :__has_initial__)
          yield value
        else
          value = nil
        end
        while true
          value = block.call(value)
          yield value
        end
      rescue StopIteration => e
        e.result
      end
    end
  end

  # enumerator_s_produce: `size:` is the only keyword, and the size is
  # endless unless it says otherwise.
  def self.produce(*initial, **options, &block)
    raise ArgumentError, +"no block given" unless block
    raise ArgumentError, wrong_arity(initial.size, 0..1) if initial.size > 1

    unknown = options.keys - [:size]
    raise ArgumentError, "unknown keyword#{"s" if unknown.size > 1}: #{unknown.map(&:inspect).join(", ")}" unless unknown.empty?

    size = options.key?(:size) ? feasible_size(options[:size]) : Float::INFINITY
    Producer.new(initial[0], !initial.empty?, block).to_enum(:each) { size.nil? || size.is_a?(Numeric) ? size : size.call }
  end

  # convert_to_feasible_size_value: nil, a callable, Infinity, or an Integer.
  def self.feasible_size(size)
    Primitive.attr! :hidden
    return size if size.nil? || size.respond_to?(:call) || size == Float::INFINITY

    Integer.try_convert(size) || raise(TypeError, no_implicit_conversion(size, "Integer"))
  end
  private_class_method :feasible_size

  # `to_enum(:method, *args, **kwargs)`, with a size or a proc that
  # returns it.
  # enumerator_init reads the method name as rb_check_id does: a Symbol,
  # a String, or what to_str gives.
  def self.method_name(method)
    Primitive.attr! :hidden
    return if method.is_a?(Symbol) || method.is_a?(String) || String.try_convert(method)

    raise TypeError, "#{method.inspect} is not a symbol nor a string"
  end
  private_class_method :method_name

  def self.for(receiver, method, args, kwargs, size)
    Primitive.attr! :hidden
    e = allocate
    e.send(:enumerate, receiver, method, args, kwargs, size)
    e
  end

  # enumerator_each: arguments with no block make a copy that passes
  # them on too.
  def each(*extra, &block)
    initialized!
    unless block
      return self if extra.empty?

      copy = dup
      # enumerator_each: added arguments leave the size unknown.
      copy.send(:enumerate, @receiver, @method, @args + extra, @kwargs, nil)
      return copy
    end

    # enumerator_block_call: the method by name with the arguments and
    # keywords kept, as rb_block_call_kw calls it, which TracePoint hears.
    args = extra.empty? ? @args : @args + extra
    name = Enumerator.send(:method_symbol, @method)
    return Primitive.zr_funcall_args_m(@receiver, name, args, false, block) if @kwargs.empty?

    Primitive.zr_funcall_args_m(@receiver, name, [*args, @kwargs.dup], true, block)
  end

  # The Symbol of a method name that to_enum took: a Symbol, or what
  # to_str gives.
  def self.method_symbol(method)
    Primitive.attr! :hidden
    method.is_a?(Symbol) ? method : String.try_convert(method).to_sym
  end
  private_class_method :method_symbol

  # A size that responds to call is called, a Proc or not.
  # enumerator_size: rb_check_funcall of `call`, of any visibility,
  # with the enumerator's arguments, else the size as it was given.
  def size
    initialized!
    return @size unless @size.respond_to?(:call, true)

    @size.__send__(:call, *@args, **@kwargs)
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

  # Its own method, not an alias: the enumerator it returns names the
  # method that was called, as each name has its own entry in CRuby.
  def each_with_object(memo)
    return to_enum(:each_with_object, memo) { size } unless block_given?

    Primitive.zr_enum_each(self, nil) { |x| yield(x, memo) }
    memo
  end

  # `next` and `peek` take the values as CRuby's C does, with no send of
  # `next_values` that a backtrace would show or a program could redefine.
  def next
    values = advance
    values.size <= 1 ? values[0] : values
  end

  def peek
    values = look_ahead
    values.size <= 1 ? values[0] : values.dup
  end

  def next_values = advance

  def peek_values = look_ahead.dup

  def rewind
    initialized!
    # The object is checked first: an object that can start again says
    # so. `enumerator_rewind` calls it with rb_check_funcall, which
    # reaches a method that the object keeps private and ignores an
    # object with no such method.
    # An arithmetic sequence is its own receiver.
    @receiver.__send__(:rewind) if !@receiver.equal?(self) && @receiver.respond_to?(:rewind, true)
    @fiber = nil
    @lookahead = nil
    @stop = nil
    @feed = nil
    self
  end

  # The value that the paused `yield` returns at the next `next`.
  def feed(value)
    initialized!
    raise TypeError, +"feed value already set" if @feed

    @feed = [value]
    nil
  end

  # A lazy shows what it was made with rather than what `each` runs.
  # inspect_enumerator: the real class, not a `class` override.
  def inspect
    name = Primitive.zr_real_class(self)
    return Primitive.zr_obj_form("#<#{name}: uninitialized>") unless @method

    receiver, method, args, kwargs = @shown || [@receiver, @method, @args, @kwargs]
    return Primitive.zr_obj_form("#<#{name}: ...>") if Primitive.zr_recursive_enter(self, :inspect)

    begin
      shown = shown_arguments(kwargs.empty? ? args : [*args, kwargs])
      Primitive.zr_obj_form("#<#{name}: #{receiver.inspect}#{":#{method}" if method}#{shown}>")
    ensure
      Primitive.zr_recursive_leave(self, :inspect)
    end
  end

  private

  # append_method: the arguments in parentheses. A last argument that is a
  # Hash, not empty, with only Symbol keys shows as keywords, each key and
  # value as `to_s` gives it.
  def shown_arguments(args)
    Primitive.attr! :hidden
    return +"" if args.empty?

    last = args.last
    keywords = last if last.is_a?(Hash) && !last.empty? && last.each_key.all?(Symbol)
    parts = (keywords ? args[0...-1] : args).map(&:inspect)
    keywords&.each { |key, value| parts << "#{key}: #{value}" }
    "(#{parts.join(', ')})"
  end

  # The arguments that `each` passes on, as `each(*args)` added them.
  def args_given
    Primitive.attr! :hidden
    @args
  end

  # enumerator_ptr: an allocated enumerator has nothing to iterate.
  def initialized!
    Primitive.attr! :hidden
    raise ArgumentError, +"uninitialized enumerator" unless @method
  end

  # enumerator_with_index_i: the values that `each` yields, packed as
  # rb_enum_values_pack packs them, with the index next to them. The
  # block's own return value goes back to `each`. The kernel does the
  # packing (`zr_enum_each`), not a `|*values|` parameter: that would make
  # an Array for each element, and the assembler walks every instruction
  # of every function this way.
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
  # its return value becomes the StopIteration's result, and every later
  # `next` raises a new StopIteration caused by the first.
  # The values of the next step, which moves the position on.
  def advance
    Primitive.attr! :hidden
    initialized!
    if @lookahead
      values = @lookahead
      @lookahead = nil
      return values
    end

    take_next
  end

  # The values of the next step, which stay there for the next `next`.
  def look_ahead
    Primitive.attr! :hidden
    initialized!
    @lookahead ||= take_next
  end

  def take_next
    Primitive.attr! :hidden
    raise_stop if @stop
    @fiber = Fiber.new { Enumerator.send(:external, self) } unless @fiber&.alive?
    values = @fiber.resume
    if @stop
      @fiber = nil
      @lookahead = nil
      raise @stop
    end
    values
  end

  # The body of the fiber of an external iteration over `enum`. A helper
  # of the class, not of the enumerator, calls `each`, so the frame of
  # `each` shows at the base of the fiber's backtraces, as the cfunc
  # frame that CRuby's next_i pushes does.
  def self.external(enum)
    Primitive.attr! :hidden
    result = enum.each { |*values| enum.send(:pause_with, values) }
    enum.send(:stop_with, result)
  end
  private_class_method :external

  # One step of an external iteration: the values go to `next`, and the
  # value a feed set is what the paused yield returns, once (next_ii).
  def pause_with(values)
    Primitive.attr! :hidden
    Fiber.yield(values)
    fed = @feed
    @feed = nil
    fed&.first
  end

  # The end of an external iteration, with the value of `each`.
  def stop_with(result)
    Primitive.attr! :hidden
    @stop = StopIteration.new(+"iteration reached an end")
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
    raise TypeError, +"can't copy execution context" if Primitive.zr_hidden_get(other, :fiber)

    @generator = Primitive.zr_hidden_get(other, :generator)
    enumerate(*%i[receiver method args kwargs size].map { |name| Primitive.zr_hidden_get(other, name) })
    @fiber = @lookahead = @stop = @feed = nil
    self
  end
end

module Kernel
  def to_enum(method = :each, *args, **kwargs, &size)
    Enumerator.send(:method_name, method)
    Enumerator.for(self, method, args, kwargs, size)
  end

  # A definition of its own, as CRuby defines both names: a TracePoint
  # names the one that the program called.
  def enum_for(method = :each, *args, **kwargs, &size)
    Enumerator.send(:method_name, method)
    Enumerator.for(self, method, args, kwargs, size)
  end

  # What a builtin iterator returns without a block: its count comes
  # last.
  private def enum_with_size(method, *args, size)
    Primitive.attr! :hidden
    if size == :__length__
      receiver = self
      size = receiver.is_a?(Hash) ? -> { Primitive.zr_hash_len_m(receiver) } : -> { Primitive.zr_ary_len_m(receiver) }
    end
    Enumerator.for(self, method, args, {}, size)
  end
end

# `1.step(10, 3)` and `(1..10).step(3)` without a block: an Enumerator
# that also returns its bounds and step, CRuby's enumerator.c arith_seq.
# It keeps the call that made it, which `inspect` replays.
class Enumerator::ArithmeticSequence < Enumerator
  attr_reader :begin, :end, :step

  # rb_arith_seq_new: `receiver.method(*args, **kwargs)` made the sequence
  # from `first` to `last` by `step`.
  def self.for(receiver, method, args, kwargs, first, last, step, exclude_end)
    Primitive.attr! :hidden
    seq = Primitive.zr_class_allocate(self)
    seq.send(:sequence, [receiver, method, args, kwargs], first, last, step, exclude_end)
    seq
  end

  # Only the core makes these: rb_undef_alloc_func and no `new`. The
  # core allocates through the kernel, past this method.
  def self.allocate
    Primitive.attr! :hidden
    raise TypeError, "allocator undefined for #{self}"
  end

  class << self
    undef_method :new
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
    if Primitive.zr_rb_equal(@step, 0)
      while true
        yield c
      end
    end
    last = last_element
    if Integer.send(:negative_int?, @step)
      while ArithmeticSequence.send(:coerce_relop, c, last, :>=)
        yield c
        c += @step
      end
    else
      while ArithmeticSequence.send(:coerce_relop, last, c, :>=)
        yield c
        c += @step
      end
    end
    self
  end

  # rb_num_coerce_relop, which arith_seq_each's NUM_GE is: `y.coerce(x)`,
  # then the operator on the pair it gives. No pair is a comparison that
  # coercion could not make, and a nil answer is one the comparator failed.
  def self.coerce_relop(x, y, op)
    Primitive.attr! :hidden
    pair = y.respond_to?(:coerce, true) ? y.__send__(:coerce, x) : nil
    Primitive.zr_cmperr_coerce(x, y) if pair.nil?
    raise TypeError, +"coerce must return [x, y]" unless pair.is_a?(Array) && pair.size == 2

    answer = pair[0].__send__(op, pair[1])
    Primitive.zr_cmperr(x, y) if answer.nil?
    answer
  end
  private_class_method :coerce_relop

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
    raise ArgumentError, +"attempt to take negative size" if n.negative?
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
    raise RangeError, +"cannot get the last element of endless arithmetic sequence" if @end.nil?

    len_1 = idiv(@end - @begin, @step)
    return none ? nil : [] if len_1.negative?

    last = @begin + (@step * len_1)
    adjusted = @exclude_end && last == @end
    last -= @step if adjusted
    return last if none

    count = adjusted ? len_1 : len_1 + 1
    n = to_integer(n)
    n = count if n > count
    raise ArgumentError, +"negative array size" if n.negative?

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
    # arith_seq_each: a Complex step never walks as Floats do.
    !@step.is_a?(Complex) && (@begin.is_a?(Float) || @end.is_a?(Float) || @step.is_a?(Float))
  end

  # The last element a whole walk would reach: `begin` plus as many whole
  # steps as fit, one fewer where an excluded end is met exactly.
  def last_element
    Primitive.attr! :hidden
    last = @begin + (@step * idiv(@end - @begin, @step))
    @exclude_end && Primitive.zr_rb_equal(last, @end) ? last - @step : last
  end

  # num_idiv: a quotient taken down to a whole number.
  def idiv(a, b)
    Primitive.attr! :hidden
    q = a.is_a?(Integer) ? a.div(b) : a / b
    q.is_a?(Integer) ? q : q.floor
  end

  # NUM2DBL: a number's Float. nil, true, false, a Symbol and a String
  # are no number, so a beginless sequence of Floats has no first value.
  def num2dbl(x)
    Primitive.attr! :hidden
    case x
    when Float then x
    when nil, true, false, Symbol, String then raise TypeError, no_implicit_conversion(x, "Float")
    else x.to_f
    end
  end

  # ruby_float_step_size: the count allows for rounding in the last
  # value. NaN and infinity travel through, so the walk reads them as
  # nothing to do and forever, and `size` reports them as ruby does.
  def float_count
    Primitive.attr! :hidden
    first = num2dbl(@begin)
    unit = num2dbl(@step)
    last = @end.nil? ? (unit < 0 ? -Float::INFINITY : Float::INFINITY) : num2dbl(@end)
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
      d = (n + 1) * unit + first
      n += 1 if first < last ? d <= last : (first > last && d >= last)
    end
    (n + 1).to_f
  end

  # ruby_float_step: `count` values, each `begin + i * step`, limited to
  # the end.
  def float_walk(count)
    Primitive.attr! :hidden
    first = num2dbl(@begin)
    unit = num2dbl(@step)
    last = @end.nil? ? (unit < 0 ? -Float::INFINITY : Float::INFINITY) : num2dbl(@end)
    if unit.infinite?
      yield first if count.positive?
    elsif unit == 0
      yield first while true
    else
      i = 0
      while i < count
        # `i * unit + beg`, which clang fuses on arm64.
        d = Primitive.zr_math_fma(i.to_f, unit, first)
        d = last if unit >= 0 ? last < d : d < last
        yield d
        i += 1
      end
    end
    self
  end
end

# A lazy enumerator is an Enumerator whose `each` runs a chain of steps.
# Each lazy has one Step: the receiver it reads, and the runner that
# streams the output to the block that `each` gets. A step that stops
# early breaks out of its receiver's `each`. A step reads each value its
# receiver yields as one (rb_enum_values_pack: nil for none, an Array for
# several), and its block and the next step get that one value.
# `inspect` shows the receiver, method and arguments that made the lazy.
# CRuby keeps these separate from what `each` runs, and so does this file.
class Enumerator::Lazy < Enumerator
  def self.from(receiver)
    Primitive.attr! :hidden
    allocate.send(:chain, receiver, false, :run_each) { receiver.respond_to?(:size) ? receiver.size : nil }
  end

  def initialize(receiver, size = nil, &block)
    raise ArgumentError, +"tried to call lazy new without a block" unless block

    chain(receiver, :each, :run_new, block:) { size.respond_to?(:call) ? size.call : size }
  end

  def lazy = self

  def force(*) = to_a(*)

  def eager
    Enumerator.for(self, :each, [], {}, proc { size })
  end

  # lazy_to_enum: a name that a lazy method overrides stands for its eager
  # form (EAGER), so the enumerator iterates. The core's own enumerators
  # keep the name, as rb_enumeratorize does: a lazy's `with_index` with
  # no block gives one that sends `with_index` with a block, which makes
  # another lazy and yields nothing.
  def to_enum(method = :each, *args, **kwargs, &size)
    Enumerator.send(:method_name, method)
    unless Primitive.zr_caller_core_p
      name = method.is_a?(Symbol) ? method : String.try_convert(method).to_sym
      method = EAGER.fetch(name, name)
    end
    Enumerator::Lazy.allocate.send(:chain, self, method, :run_send, args:, kwargs:) { size&.call }
  end

  alias enum_for to_enum

  # Each alias has a definition of its own, so `inspect` shows the name
  # that made the lazy, as CRuby's lazy_add_method records it.
  def map(&block) = step(:map, :run_map, block, sized: true)

  def collect(&block) = step(:collect, :run_map, block, sized: true)

  def flat_map(&block) = step(:flat_map, :run_flat_map, block)

  def collect_concat(&block) = step(:collect_concat, :run_flat_map, block)

  def select(&block) = step(:select, :run_select, block)

  def filter(&block) = step(:filter, :run_select, block)

  def find_all(&block) = step(:find_all, :run_select, block)

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
    raise ArgumentError, +"attempt to take negative size" if n < 0

    step(:take, :run_take, nil, [n], check: false) { size&.clamp(..n) }
  end

  def drop(n)
    n = implicit_integer(n)
    raise ArgumentError, +"attempt to drop negative size" if n < 0

    step(:drop, :run_drop, nil, [n], check: false) { size && [size - n, 0].max }
  end

  def grep(pattern, &block)
    step(:grep, block ? :run_grep_map : :run_grep, block, [pattern], check: false)
  end

  def grep_v(pattern, &block)
    step(:grep_v, block ? :run_grep_v_map : :run_grep_v, block, [pattern], check: false)
  end

  # lazy_zip: each argument converts with to_ary until one does not; that
  # one and those after it must respond to each, and stay as they are.
  def zip(*others, &block)
    return super if block

    args = []
    i = 0
    while i < others.size
      converted = Array.try_convert(others[i])
      break if converted.nil?

      args << converted
      i += 1
    end
    while i < others.size
      other = others[i]
      raise TypeError, "wrong argument type #{other.class} (must respond to :each)" unless other.respond_to?(:each)

      args << other
      i += 1
    end
    step(:zip, :run_zip, nil, args, check: false, sized: true)
  end

  def uniq(&block)
    step(:uniq, :run_uniq, block, check: false)
  end

  # lazy_tap_each (ruby 4.1): the block sees each value, which goes on
  # unchanged. The lazy has no size.
  def tap_each(&block) = step(:tap_each, :run_tap_each, block)

  def compact
    step(:compact, :run_compact, nil, check: false)
  end

  def with_index(offset = 0, &block)
    offset = 0 if offset.nil?
    step(:with_index, block ? :run_with_index_each : :run_with_index, block, [offset], check: false, sized: true)
  end

  # lazy_each_with_index (ruby 4.1): with_index(0), under its own name.
  def each_with_index(&block)
    step(:each_with_index, block ? :run_with_index_each : :run_with_index, block, [0], check: false, sized: true)
  end

  # The chunking methods stay Enumerable's, their enumerator made lazy.
  def chunk(*, &block) = Enumerator::Lazy.from(super)

  def chunk_while(*, &block) = Enumerator::Lazy.from(super)

  def slice_when(*, &block) = Enumerator::Lazy.from(super)

  def slice_before(*, &block) = Enumerator::Lazy.from(super)

  def slice_after(*, &block) = Enumerator::Lazy.from(super)

  # define_lazy_alias: the eager forms, as private aliases under CRuby's
  # names for them, of Enumerable's methods and of Enumerator's with_index
  # and each_with_index. lazy_to_enum names them for the lazy methods.
  EAGER = { map: :_enumerable_map, collect: :_enumerable_collect, flat_map: :_enumerable_flat_map,
    collect_concat: :_enumerable_collect_concat, select: :_enumerable_select, find_all: :_enumerable_find_all,
    filter: :_enumerable_filter, filter_map: :_enumerable_filter_map, reject: :_enumerable_reject,
    grep: :_enumerable_grep, grep_v: :_enumerable_grep_v, zip: :_enumerable_zip, take: :_enumerable_take,
    take_while: :_enumerable_take_while, drop: :_enumerable_drop, drop_while: :_enumerable_drop_while,
    uniq: :_enumerable_uniq, with_index: :_enumerable_with_index, each_with_index: :_enumerable_each_with_index }.freeze
  private_constant :EAGER
  EAGER.each do |name, eager|
    define_method(eager, (name == :with_index || name == :each_with_index ? Enumerator : Enumerable).instance_method(name))
    private eager
  end

  private

  # This lazy, reading `receiver` through `runner`, and shown as
  # `receiver`, `method` and `args`; a false `method` shows none.
  def chain(receiver, method, runner, block: nil, args: [], kwargs: {}, &size)
    Primitive.attr! :hidden
    step = Step.new(receiver, method, runner, block, args, kwargs)
    Primitive.zr_hidden_set(self, :__step__, step)
    enumerate(step, :each, [], {}, size)
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

  # What a lazy's `each` runs: its receiver, through one runner. Each
  # runner sends `each` to its receiver by name, as CRuby's
  # lazy_init_iterator does, so a program's own `each` is called.
  #
  # Values pass from step to step as their source yielded them, as
  # CRuby's memo keeps several values packed with a flag: the block of map,
  # filter_map, flat_map, take_while and drop_while gets them apart, and
  # every other block gets them packed in one (rb_enum_values_pack: nil
  # for none, an Array for several). The block of the lazy's own `each`
  # gets them packed.
  class Step
    Primitive.attr! :sends_each

    def initialize(receiver, method, runner, block, args, kwargs)
      @receiver = receiver
      @method = method
      @runner = runner
      @block = block
      @args = args
      @kwargs = kwargs
    end

    # Arguments a caller adds go to the source's `each`, as
    # lazy_init_block_i passes them; a later stage ignores them.
    def each(*extra, &)
      return @receiver.each(*extra, &) if @runner == :run_each

      __send__(@runner, true, &)
    end

    # The values for the step after this one, not packed.
    def each_raw(*extra, &)
      return @receiver.each(*extra, &) if @runner == :run_each

      __send__(@runner, false, &)
    end

    # A lazy that reads another of the core's lazies (and not a subclass,
    # whose `each` the program may define) reads its values as they came.
    # A lazy that `each` gave arguments (`io.lazy.each("")`) passes them on.
    class Raw
      def initialize(step, args) = (@step, @args = step, args)
      def each(&) = @step.each_raw(*@args, &)
    end

    private

    def source
      return @receiver unless Primitive.zr_real_class(@receiver).equal?(Enumerator::Lazy)

      step = Primitive.zr_hidden_get(@receiver, :__step__)
      step ? Raw.new(step, @receiver.send(:args_given)) : @receiver
    end

    # Gives `values` to `out`: packed in one value for the lazy's own
    # `each`, apart for a step after this one.
    def emit(out, packing, values)
      packing ? out.call(Primitive.zr_enum_value(values)) : out.call(*values)
    end

    def run_each(_packing, &)
      @receiver.each(&)
    end

    def run_new(_packing, &)
      block = @block
      y = Enumerator::Yielder.new(&)
      source.each { |*values| block.call(y, *values); nil }
      nil
    end

    # The block's value goes back to the method, as enumerator_block_call
    # passes it: `lazy.to_enum(:chunk).each { ... }` chunks by it.
    def run_send(_packing, &block)
      name = Enumerator.send(:method_symbol, @method)
      return Primitive.zr_funcall_args_m(@receiver, name, @args, false, block) if @kwargs.empty?

      Primitive.zr_funcall_args_m(@receiver, name, [*@args, @kwargs.dup], true, block)
    end

    # The four stages that keep no state go through the kernel's
    # adapter (zr_lazy_stage), which reads an element without the
    # `|*values|` Array the others pay once an element.
    def run_map(packing, &out) = Primitive.zr_lazy_map(source, @block, out, packing)

    def run_select(packing, &out) = Primitive.zr_lazy_select(source, @block, out, packing)

    def run_reject(packing, &out) = Primitive.zr_lazy_reject(source, @block, out, packing)

    def run_filter_map(packing, &out) = Primitive.zr_lazy_filter_map(source, @block, out, packing)

    def run_flat_map(packing, &out)
      block = @block
      source.each do |*values|
        # The block gets several values as they came, and nil for none.
        result = values.empty? ? block.call(nil) : block.call(*values)
        if !result.is_a?(Array) && result.respond_to?(:force) && result.respond_to?(:each)
          # lazy_flat_map_i: a block that the object keeps works after the
          # walk ends, and gives back the values it got, packed.
          result.each do |*items|
            emit(out, packing, items)
            Primitive.zr_enum_value(items)
          end
        elsif (items = Array.try_convert(result))
          # An Array is read by index, as lazy_flat_map_proc reads it.
          i = 0
          while i < Primitive.zr_ary_len_m(items)
            yield Primitive.zr_ary_at_m(items, i)
            i += 1
          end
        else
          yield result
        end
        nil
      end
      nil
    end

    def run_take_while(packing, &out)
      block = @block
      source.each do |*values|
        break unless values.empty? ? block.call(nil) : block.call(*values)

        emit(out, packing, values)
        nil
      end
      nil
    end

    def run_drop_while(packing, &out)
      block = @block
      dropping = true
      source.each do |*values|
        dropping = false if dropping && !(values.empty? ? block.call(nil) : block.call(*values))
        emit(out, packing, values) unless dropping
        nil
      end
      nil
    end

    def run_take(packing, &out)
      n = @args[0]
      return nil if n == 0

      taken = 0
      source.each do |*values|
        emit(out, packing, values)
        taken += 1
        break if taken == n

        nil
      end
      nil
    end

    def run_drop(packing, &out)
      n = @args[0]
      seen = 0
      source.each do |*values|
        emit(out, packing, values) if seen >= n
        seen += 1
        nil
      end
      nil
    end

    def run_grep(packing, &out)
      pattern = @args[0]
      source.each do |*values|
        emit(out, packing, values) if pattern === Primitive.zr_enum_value(values)
        nil
      end
      nil
    end

    def run_grep_map(_packing)
      pattern = @args[0]
      block = @block
      source.each do |*values|
        x = Primitive.zr_enum_value(values)
        yield block.call(x) if pattern === x
        nil
      end
      nil
    end

    def run_grep_v(packing, &out)
      pattern = @args[0]
      source.each do |*values|
        emit(out, packing, values) unless pattern === Primitive.zr_enum_value(values)
        nil
      end
      nil
    end

    def run_grep_v_map(_packing)
      pattern = @args[0]
      block = @block
      source.each do |*values|
        x = Primitive.zr_enum_value(values)
        yield block.call(x) unless pattern === x
        nil
      end
      nil
    end

    # Arrays are read by index; any other object is read with `next`,
    # and gives nil after it stops.
    # lazy_zip_arrays_func reads Arrays by index; once one argument is no
    # Array, lazy_zip_func walks each of them, Arrays too, with to_enum.
    def run_zip(packing, &out)
      arrays = @args.all? { |other| other.is_a?(Array) }
      cursors = arrays ? @args : @args.map(&:to_enum)
      i = 0
      source.each do |*values|
        row = [Primitive.zr_enum_value(values)]
        j = 0
        while j < Primitive.zr_ary_len_m(cursors)
          cursor = Primitive.zr_ary_at_m(cursors, j)
          row << if cursor.is_a?(Array)
                   cursor[i]
                 else
                   begin
                     cursor.next
                   rescue StopIteration
                     nil
                   end
                 end
          j += 1
        end
        # The row keeps the source's packing: apart only where it packed
        # several values (lazy_zip_func leaves the memo's flag).
        emit(out, packing, values.size > 1 ? row : [row])
        i += 1
        nil
      end
      nil
    end

    def run_uniq(packing, &out)
      block = @block
      seen = {}
      source.each do |*values|
        v = Primitive.zr_enum_value(values)
        key = block ? block.call(v) : v
        unless seen.key?(key)
          seen[key] = true
          emit(out, packing, values)
        end
        nil
      end
      nil
    end

    # lazy_tap_each_proc: the block gets the value, packed when the source
    # yields more than one.
    def run_tap_each(packing, &out)
      block = @block
      source.each do |*values|
        block.call(Primitive.zr_enum_value(values))
        emit(out, packing, values)
        nil
      end
      nil
    end

    def run_compact(packing, &out)
      source.each do |*values|
        emit(out, packing, values) unless Primitive.zr_enum_value(values).nil?
        nil
      end
      nil
    end

    # lazy_with_index_proc: the value and its index, as two values.
    def run_with_index(packing, &out)
      i = @args[0]
      source.each do |*values|
        emit(out, packing, [Primitive.zr_enum_value(values), i])
        i = implicit_integer(i) + 1
        nil
      end
      nil
    end

    def run_with_index_each(packing, &out)
      block = @block
      i = @args[0]
      source.each do |*values|
        block.call(Primitive.zr_enum_value(values), i)
        emit(out, packing, values)
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

  # Without a block, CRuby wraps the chain twice. Each enumerable gets
  # `each` by name, as enum_chain_each sends it.
  def each(*args, &block)
    Primitive.attr! :sends_each
    return to_enum(:each, *args).to_enum(:each) unless block

    i = 0
    while i < Primitive.zr_ary_len_m(@enums)
      # enum_chain's pos: how far an iteration got, which rewind reads.
      @pos = i
      Primitive.zr_ary_at_m(@enums, i).each(*args, &block)
      i += 1
    end
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

  # enum_chain_rewind: the enumerables an iteration reached, last first.
  def rewind
    i = @pos || -1
    while i >= 0
      e = @enums[i]
      e.__send__(:rewind) if e.respond_to?(:rewind, true)
      i -= 1
    end
    @pos = nil
    self
  end

  def inspect
    return Primitive.zr_obj_form("#<Enumerator::Chain: uninitialized>") if @enums.nil?

    Primitive.zr_obj_form("#<Enumerator::Chain: #{@enums.inspect}>")
  end

  private def initialize_copy(other)
    Kernel.instance_method(:initialize_copy).bind_call(self, other)
    @enums = Primitive.zr_hidden_get(other, :enums).dup
    self
  end


  undef_method :feed, :next, :next_values, :peek, :peek_values

  # new_enum_chain: a chain with a lazy part is lazy.
  def self.of(enums)
    Primitive.attr! :hidden
    chain = new(*enums)
    enums.any?(Enumerator::Lazy) ? chain.lazy : chain
  end
  private_class_method :of
end

class Enumerator
  def +(other) = Enumerator::Chain.send(:of, [self, other])
end

# `Enumerator.product(a, b)`: every combination, the last enumerable
# varying fastest.
class Enumerator::Product < Enumerator
  def initialize(*enums, **options)
    raise ArgumentError, "unknown keyword#{"s" if options.size > 1}: #{options.keys.map(&:inspect).join(", ")}" unless options.empty?

    @enums = enums
    self
  end

  def each(&block)
    return to_enum(:each) { size } unless block

    walk(0, [], &block)
    self
  end

  # enum_product_total_size: nil or an infinity ends the count; any
  # other size that is no Integer makes it nil.
  # enum_product_total_size: an empty enumerable makes the product
  # empty, before any size that is unknown or endless counts.
  def size
    sizes = @enums.map { |e| e.respond_to?(:size) ? e.size : nil }
    return 0 if sizes.any? { |n| n.is_a?(Integer) && n.zero? }

    sizes.reduce(1) do |total, n|
      return n if n.nil? || (n.is_a?(Float) && n.infinite?)
      return nil unless n.is_a?(Integer)

      total * n
    end
  end

  # enum_product_rewind: each enumerable, in order.
  def rewind
    @enums.each { |e| e.__send__(:rewind) if e.respond_to?(:rewind, true) }
    self
  end

  def inspect
    return Primitive.zr_obj_form("#<Enumerator::Product: uninitialized>") if @enums.nil?
    return Primitive.zr_obj_form("#<Enumerator::Product: ...>") if Primitive.zr_recursive_enter(self, :inspect)

    begin
      Primitive.zr_obj_form("#<Enumerator::Product: #{@enums.inspect}>")
    ensure
      Primitive.zr_recursive_leave(self, :inspect)
    end
  end

  private def initialize_copy(other)
    return self if equal?(other)

    enums = Primitive.zr_hidden_get(other, :enums)
    raise ArgumentError, +"uninitialized product" if enums.nil?

    Kernel.instance_method(:initialize_copy).bind_call(self, other)
    @enums = enums.dup
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

  undef_method :feed, :next, :next_values, :peek, :peek_values
end

class Enumerator
  def self.product(*enums, **nothing, &block)
    raise ArgumentError, "unknown keyword#{'s' if nothing.size > 1}: #{nothing.keys.map(&:inspect).join(', ')}" unless nothing.empty?

    product = Enumerator::Product.new(*enums)
    return product unless block

    product.each(&block)
    nil
  end
end
