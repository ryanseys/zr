# TracePoint, over the events a traced program fires (rt/kernel/trace.rb).
# An enabled TracePoint adds its events to the kernel's mask; an event
# comes to TracePoint.fire with a row that describes its frame, and each
# enabled TracePoint that asks for it runs its block, the newest first.
# While a block runs, the fiber carries the row, which every accessor
# reads and which keeps the handlers from firing events of their own, as
# CRuby's ec->trace_arg does.
class TracePoint
  EVENTS = {
    line: 0x1, class: 0x2, end: 0x4, call: 0x8, return: 0x10, c_call: 0x20, c_return: 0x40, raise: 0x80,
    b_call: 0x100, b_return: 0x200, thread_begin: 0x400, thread_end: 0x800, fiber_switch: 0x1000,
    script_compiled: 0x2000, rescue: 0x4000, a_call: 0x128, a_return: 0x250
  }.freeze
  NAMES = EVENTS.first(15).to_h(&:reverse).freeze
  ALL = 0x7fff
  # The events a program here fires; the rest have no firing point yet.
  FIRED = 0x43ff
  C_EVENTS = 0x60
  # The events a set_trace_func hook takes, by the names it takes them.
  HOOK_NAMES = {
    line: "line", class: "class", end: "end", call: "call", return: "return",
    c_call: "c-call", c_return: "c-return", raise: "raise"
  }.freeze
  private_constant :EVENTS, :NAMES, :ALL, :FIRED, :C_EVENTS, :HOOK_NAMES

  Primitive.zr_undef_alloc(self)

  class << self
    undef_method :new

    def new(*events, &block)
      mask = events.empty? ? ALL : events.inject(0) { |all, event| all | flag(event) }
      raise ArgumentError, "must be called with a block" unless block

      point = Primitive.zr_class_build(self)
      Primitive.zr_hidden_set(point, :__events__, mask)
      Primitive.zr_hidden_set(point, :__proc__, block)
      point
    end

    def trace(*events, &block) = new(*events, &block).tap(&:enable)

    def stat = {}

    def allow_reentry
      row = current_row
      raise RuntimeError, "No need to allow reentrance." if row.nil?

      Primitive.zr_hidden_set(Fiber.current, :__trace_row__, nil)
      begin
        yield
      ensure
        Primitive.zr_hidden_set(Fiber.current, :__trace_row__, row)
      end
    end

    private

    # symbol2event_flag.
    def flag(event)
      name = event.is_a?(Symbol) ? event : String.try_convert(event)&.to_sym
      raise TypeError, "#{event.inspect} is not a symbol nor a string" if name.nil?

      EVENTS.fetch(name) { raise ArgumentError, "unknown event: #{name}" }
    end

    def enabled
      Primitive.attr! :hidden
      Primitive.zr_hidden_get(self, :__enabled__) || Primitive.zr_hidden_set(self, :__enabled__, [])
    end

    # set_trace_func and Thread#set_trace_func (`adding` false) and
    # Thread#add_trace_func: a TracePoint over every event a hook takes,
    # for every thread (`thread` nil) or for one. A set removes the hooks
    # set before for the same threads.
    def trace_func(hook, thread, adding)
      Primitive.attr! :hidden
      unless adding
        funcs.select { |point| Primitive.zr_hidden_get(point, :__hook_thread__).equal?(thread) }.each do |point|
          funcs.delete(point)
          point.disable
        end
      end
      return nil if hook.nil?
      raise TypeError, "trace_func needs to be Proc" unless hook.is_a?(Proc)

      point = new(*HOOK_NAMES.keys) do |tp|
        klass = tp.defined_class
        klass = klass.attached_object if klass.is_a?(Class) && klass.singleton_class?
        hook.call(HOOK_NAMES.fetch(tp.event), tp.path, tp.lineno, tp.method_id, tp.binding, klass)
      end
      Primitive.zr_hidden_set(point, :__hook_thread__, thread)
      funcs << point
      # A hook is C's, so no TracePoint#enable runs for a trace to see.
      Primitive.zr_hidden_set(point, :__thread__, thread)
      point.send(:switch, true)
      hook
    end

    def funcs
      Primitive.attr! :hidden
      Primitive.zr_hidden_get(self, :__funcs__) || Primitive.zr_hidden_set(self, :__funcs__, [])
    end

    # A targeted point sees the events its target's code fires, in the
    # code itself or a block written inside it, and no C event; with a
    # target line, only the :line events of that line.
    def targets?(point, row)
      Primitive.attr! :hidden
      target = Primitive.zr_hidden_get(point, :__target__)
      return true if target.nil?
      return false if (row[0] & C_EVENTS).nonzero?

      line = Primitive.zr_hidden_get(point, :__target_line__)
      return false unless line.nil? || (row[0] == EVENTS[:line] && row[3] == line)

      Primitive.zr_trace_within(row[9], target) == true
    end

    def current_row
      Primitive.attr! :hidden
      Primitive.zr_hidden_get(Fiber.current, :__trace_row__)
    end

    # The kernel's mask: every event an enabled TracePoint asks for.
    def rearm
      Primitive.attr! :hidden
      mask = enabled.inject(0) { |all, point| all | Primitive.zr_hidden_get(point, :__events__) }
      builtin_places if (mask & 0x78).nonzero?
      Primitive.zr_trace_events_set(mask & FIRED)
    end

    # CRuby's own Ruby methods, marked the first time a TracePoint asks
    # for :call or :return, so each send to one fires them: the place
    # each one's events report, by its class and name.
    def builtin_places
      Primitive.attr! :hidden
      Primitive.zr_hidden_get(self, :__builtin_places__) || Primitive.zr_hidden_set(self, :__builtin_places__, marked_builtins)
    end

    def marked_builtins
      Primitive.attr! :hidden
      places = {}.compare_by_identity
      BUILTIN_LINES.each do |key, place|
        singleton = key.include?(".")
        owner_path, name = key.split(singleton ? "." : "#", 2)
        owner = owner_path.split("::").inject(Object) { |scope, part| scope.const_get(part, false) } rescue next
        target = singleton ? owner.singleton_class : owner
        next unless Primitive.zr_trace_mark_ruby(target, name.to_sym)

        (places[target] ||= {})[name.to_sym] = place
      end
      places
    end

    # The :return of the TracePoint#enable that started `point`'s trace,
    # which CRuby's hook sees as the method leaves.
    # The first enable in the process runs before any hook is in place
    # and sees nothing.
    def enable_returned(point, value)
      Primitive.attr! :hidden
      return Primitive.zr_hidden_set(self, :__enabled_before__, true) unless Primitive.zr_hidden_get(self, :__enabled_before__)

      path, _call, line = BUILTIN_LINES.fetch("TracePoint#enable")
      fire([EVENTS[:return], value, path, line, :enable, :enable, TracePoint, point, nil, 0, 0])
    end

    # A traced program fired the event `row` describes.
    def fire(row)
      Primitive.attr! :hidden
      return nil unless current_row.nil?

      # A :call or :return around one of CRuby's own Ruby methods reports
      # the place that method stands in CRuby's builtin sources.
      if (row[0] & 0x18).nonzero? && row[10].nonzero? && (place = builtin_places[row[6]]&.[](row[4]))
        row[2] = place[0]
        row[3] = row[0] == 0x8 ? place[1] : place[2]
        row[8] = nil
      end

      thread = Thread.current
      points = enabled.select do |point|
        (Primitive.zr_hidden_get(point, :__events__) & row[0]).nonzero? &&
          (Primitive.zr_hidden_get(point, :__thread__).nil? || Primitive.zr_hidden_get(point, :__thread__).equal?(thread)) &&
          targets?(point, row)
      end
      fiber = Fiber.current
      Primitive.zr_hidden_set(fiber, :__trace_row__, row)
      begin
        i = points.size - 1
        while i >= 0
          Primitive.zr_hidden_get(points[i], :__proc__).call(points[i])
          i -= 1
        end
      ensure
        Primitive.zr_hidden_set(fiber, :__trace_row__, nil)
      end
      nil
    end
  end

  def enable(target: nil, target_line: nil, target_thread: :default)
    Primitive.attr! :ruby
    was = enabled?
    if target_thread == :default
      target_thread = block_given? && target.nil? && target_line.nil? ? Thread.current : nil
    end
    raise ArgumentError, "only target_line is specified" if target.nil? && !target_line.nil?

    aim(target, target_line) unless target.nil?
    if target_thread
      raise ArgumentError, "can not override target_thread filter" if Primitive.zr_hidden_get(self, :__thread__)

      Primitive.zr_hidden_set(self, :__thread__, target_thread)
    else
      Primitive.zr_hidden_set(self, :__thread__, nil)
    end
    # A :return hook already in place sees this call return by itself.
    returning = TracePoint.send(:enabled).any? { |point| (Primitive.zr_hidden_get(point, :__events__) & EVENTS[:return]).nonzero? }
    switch(true)
    unless block_given?
      # The trace this call started sees the call return.
      TracePoint.send(:enable_returned, self, was) unless was || returning
      return was
    end
    Primitive.zr_hidden_set(TracePoint, :__enabled_before__, true)

    begin
      yield
    ensure
      switch(was)
    end
  end

  def disable
    Primitive.attr! :ruby
    was = enabled?
    switch(false)
    return was unless block_given?

    begin
      yield
    ensure
      switch(was)
    end
  end

  def enabled? = TracePoint.send(:enabled).include?(self)

  def inspect
    row = TracePoint.send(:current_row)
    return "#<TracePoint:#{enabled? ? 'enabled' : 'disabled'}>" if row.nil?

    case event
    when :line
      return "#<TracePoint:line #{path}:#{lineno} in '#{method_id}'>" if method_id
    when :call, :c_call, :return, :c_return
      return "#<TracePoint:#{event} '#{method_id}' #{path}:#{lineno}>"
    end
    "#<TracePoint:#{event} #{path}:#{lineno}>"
  end

  def event = NAMES.fetch(row[0])
  def path = row[2]
  def lineno = row[3]
  def method_id = row[4]
  def callee_id = row[5]
  def defined_class = row[6]

  def self
    row[7]
  end

  def binding
    return nil if %i[c_call c_return].include?(event) || row[8].nil?

    Primitive.zr_trace_binding(row[8])
  end

  def return_value
    raise RuntimeError, "not supported by this event" unless %i[return c_return b_return].include?(event)

    row[1]
  end

  def raised_exception
    raise RuntimeError, "not supported by this event" unless %i[raise rescue].include?(event)

    row[1]
  end

  def parameters
    raise RuntimeError, "not supported by this event" if %i[raise line class end script_compiled rescue].include?(event)

    Primitive.zr_trace_parameters(row[9], row[10])
  end

  def eval_script
    raise RuntimeError, "not supported by this event" unless event == :script_compiled
  end

  def instruction_sequence
    raise RuntimeError, "not supported by this event" unless event == :script_compiled
  end

  private

  # The row of the event being handled, whichever TracePoint asks.
  def row
    Primitive.attr! :hidden
    TracePoint.send(:current_row) or raise RuntimeError, "access from outside"
  end

  # rb_tracepoint_enable_for_target: the code the target runs, which
  # must be Ruby's, and the line in it, which only a :line event has.
  def aim(target, line)
    Primitive.attr! :hidden
    raise ArgumentError, "specified target is not supported" if RubyVM::InstructionSequence.of(target).nil?
    raise ArgumentError, "can't nest-enable a targeting TracePoint" if enabled?

    events = Primitive.zr_hidden_get(self, :__events__)
    raise ArgumentError, "target_line is specified, but line event is not specified" if line && (events & EVENTS[:line]).zero?

    Primitive.zr_hidden_set(self, :__target__, target)
    Primitive.zr_hidden_set(self, :__target_line__, line && Integer(line))
  end

  def switch(on)
    Primitive.attr! :hidden
    points = TracePoint.send(:enabled)
    if on
      unfired = Primitive.zr_hidden_get(self, :__events__) & ~FIRED
      Primitive.zr_unimplemented("TracePoint events #{NAMES.select { |bit, _| (unfired & bit).nonzero? }.values.join(', ')}") if unfired.nonzero?
      points << self unless points.include?(self)
    else
      points.delete(self)
      Primitive.zr_hidden_set(self, :__thread__, nil)
      Primitive.zr_hidden_set(self, :__target__, nil)
      Primitive.zr_hidden_set(self, :__target_line__, nil)
    end
    TracePoint.send(:rearm)
  end
end
