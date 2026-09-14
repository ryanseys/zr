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
  FIRED = 0x39f
  private_constant :EVENTS, :NAMES, :ALL, :FIRED

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

    def current_row
      Primitive.attr! :hidden
      Primitive.zr_hidden_get(Fiber.current, :__trace_row__)
    end

    # The kernel's mask: every event an enabled TracePoint asks for.
    def rearm
      Primitive.attr! :hidden
      mask = enabled.inject(0) { |all, point| all | Primitive.zr_hidden_get(point, :__events__) }
      Primitive.zr_trace_events_set(mask & FIRED)
    end

    # A traced program fired the event `row` describes.
    def fire(row)
      Primitive.attr! :hidden
      return nil unless current_row.nil?

      thread = Thread.current
      points = enabled.select do |point|
        (Primitive.zr_hidden_get(point, :__events__) & row[0]).nonzero? &&
          (Primitive.zr_hidden_get(point, :__thread__).nil? || Primitive.zr_hidden_get(point, :__thread__).equal?(thread))
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
    Primitive.zr_unimplemented("TracePoint#enable with a target") unless target.nil? && target_line.nil?

    was = enabled?
    if target_thread == :default
      target_thread = block_given? ? Thread.current : nil
    end
    if target_thread
      raise ArgumentError, "can not override target_thread filter" if Primitive.zr_hidden_get(self, :__thread__)

      Primitive.zr_hidden_set(self, :__thread__, target_thread)
    else
      Primitive.zr_hidden_set(self, :__thread__, nil)
    end
    switch(true)
    return was unless block_given?

    begin
      yield
    ensure
      switch(was)
    end
  end

  def disable
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

    Primitive.zr_unimplemented("TracePoint#parameters")
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
    end
    TracePoint.send(:rearm)
  end
end
