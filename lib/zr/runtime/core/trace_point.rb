# frozen_string_literal: true

# TracePoint, over the events that a traced program fires (lib/zr/runtime/kernel/trace.rb).
# An enabled TracePoint adds its events to the kernel's mask. An event
# comes to TracePoint.fire with a record that describes its frame, and
# each enabled TracePoint that wants it runs its block, the newest first.
# While a block runs, the fiber keeps the record. Every accessor reads
# it, and it stops the handlers from firing events of their own, as
# CRuby's ec->trace_arg does.
class TracePoint
  EVENTS = {
    line: 0x1, class: 0x2, end: 0x4, call: 0x8, return: 0x10, c_call: 0x20, c_return: 0x40, raise: 0x80,
    b_call: 0x100, b_return: 0x200, thread_begin: 0x400, thread_end: 0x800, fiber_switch: 0x1000,
    script_compiled: 0x2000, rescue: 0x4000, a_call: 0x128, a_return: 0x250
  }.freeze
  NAMES = EVENTS.first(15).to_h(&:reverse).freeze
  ALL = 0x7fff
  C_EVENTS = 0x60
  # The events that a set_trace_func hook takes, by their names there.
  HOOK_NAMES = {
    line: "line", class: "class", end: "end", call: "call", return: "return",
    c_call: "c-call", c_return: "c-return", raise: "raise"
  }.freeze
  # The RubyVM object that `stat` keys its counts by, made at the first call.
  VM = [nil]
  private_constant :EVENTS, :NAMES, :ALL, :C_EVENTS, :HOOK_NAMES, :VM

  Primitive.zr_undef_alloc(self)

  class << self
    undef_method :new

    def new(*events, &block)
      mask = events.empty? ? ALL : 0
      events.each { |event| mask |= flag(event) }
      raise ArgumentError, +"must be called with a block" unless block

      point = Primitive.zr_class_build(self)
      Primitive.zr_hidden_set(point, :__events__, mask)
      Primitive.zr_hidden_set(point, :__proc__, block)
      point
    end

    def trace(*events, &block) = new(*events, &block).tap(&:enable)

    # The enabled TracePoints of the one VM, by CRuby's key: its RubyVM
    # object, with the count of hooks and of deleted hooks.
    def stat
      VM[0] ||= Primitive.zr_class_build(RubyVM)
      { VM[0] => [enabled.size, 0] }
    end

    def allow_reentry
      row = current_row
      raise RuntimeError, +"No need to allow reentrance." if row.nil?

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
      # rb_to_symbol_type: a Symbol, or what to_sym gives.
      name = event
      unless name.is_a?(Symbol)
        raise TypeError, "no implicit conversion of #{conversion_name(event)} into Symbol" unless event.respond_to?(:to_sym)

        name = event.to_sym
        raise TypeError, "can't convert #{conversion_name(event)} to Symbol (#{conversion_name(event)}#to_sym gives #{conversion_name(name)})" unless name.is_a?(Symbol)
      end

      EVENTS.fetch(name) { raise ArgumentError, "unknown event: #{name}" }
    end

    # A program whose code never names TracePoint is built without the
    # events, so its code fires none (lib/zr/hir/build/loader.rb,
    # `names_of?`). A point that such a program enables, by a name in a
    # string or one the run computed, says so once, and names the build
    # that arms them.
    def untraced!
      Primitive.attr! :hidden
      return if Primitive.zr_trace_built_m || Primitive.zr_hidden_get(self, :__untraced__)

      Primitive.zr_hidden_set(self, :__untraced__, true)
      STDERR.write("zr: warning: a TracePoint is enabled, but zr built this program without trace events because no file names " \
                   "TracePoint, so its code fires none. Build it with --trace (or ZR_TRACE=1).\n")
    end

    def enabled
      Primitive.attr! :hidden
      Primitive.zr_hidden_get(self, :__enabled__) || Primitive.zr_hidden_set(self, :__enabled__, [])
    end

    # set_trace_func and Thread#set_trace_func (`adding` false) and
    # Thread#add_trace_func: a TracePoint over every event a hook takes,
    # for every thread (`thread` nil) or for one. A set removes the hooks
    # set before for the same threads.
    def trace_func(hook, thread, adding, site)
      Primitive.attr! :hidden
      unless adding
        funcs.select { |point| Primitive.zr_hidden_get(point, :__hook_thread__).equal?(thread) }.each do |point|
          funcs.delete(point)
          point.disable
        end
      end
      return nil if hook.nil?
      raise TypeError, +"trace_func needs to be Proc" unless hook.is_a?(Proc)

      point = new(*HOOK_NAMES.keys) do |tp|
        klass = tp.defined_class
        klass = klass.attached_object if klass.is_a?(Class) && klass.singleton_class?
        hook.call(HOOK_NAMES.fetch(tp.event), tp.path, tp.lineno, tp.method_id, tp.binding, klass)
      end
      Primitive.zr_hidden_set(point, :__hook_thread__, thread)
      funcs << point
      # A hook is C's, so no TracePoint#enable runs for a trace to see.
      Primitive.zr_hidden_set(point, :__thread__, thread)
      # The hook hears the return of the C method that set it, which
      # returns once the hook is in place. It runs untraced, as every
      # hook does, and may remove itself.
      if thread.nil? || thread.equal?(Thread.current)
        hook.call(+"c-return", site.path, site.lineno, adding ? :add_trace_func : :set_trace_func, nil, thread ? Thread : Kernel)
      end
      point.send(:switch, true) if funcs.include?(point)
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

    # The kernel's mask: every event that an enabled TracePoint wants.
    def rearm
      Primitive.attr! :hidden
      mask = 0
      enabled.each { |point| mask |= Primitive.zr_hidden_get(point, :__events__) }
      Primitive.zr_hidden_set(self, :__armed__, mask)
      builtin_places if (mask & 0x78).nonzero?
      Primitive.zr_trace_events_set(mask & ALL)
    end

    # The same mask, for an event Ruby fires rather than compiled code.
    # A thread starts and ends far too rarely to be worth a word of the
    # kernel's, and this is what keeps one that starts while nothing
    # traces from building a row for no one.
    def armed
      Primitive.attr! :hidden
      Primitive.zr_hidden_get(self, :__armed__) || 0
    end

    # A thread's own events, which thread_start_func_2 fires around the
    # thread's body: the record gives no file, no line and no method, and
    # `self` is the thread, as th->self is.
    def thread_event(name, thread)
      Primitive.attr! :hidden
      bit = EVENTS.fetch(name)
      return nil if (armed & bit).zero?

      fire([bit, nil, nil, 0, nil, nil, nil, thread, nil, 0, 0])
    end

    # CRuby's own Ruby methods, marked the first time a TracePoint wants
    # :call or :return, so each send to one fires them: the position
    # that each one's events report, by its class and name.
    def builtin_places
      Primitive.attr! :hidden
      Primitive.zr_hidden_get(self, :__builtin_places__) || Primitive.zr_hidden_set(self, :__builtin_places__, marked_builtins)
    end

    # Method#source_location of a core method that CRuby writes in Ruby:
    # the def in its builtin source. Any other core method has none.
    def builtin_source(method)
      Primitive.attr! :hidden
      owner = method.owner
      name = method.original_name
      # A module_function's copy on the module shares the def.
      place = if owner.singleton_class?
                BUILTIN_LINES["#{owner.attached_object}.#{name}"] || (BUILTIN_LINES["#{owner.attached_object}##{name}"] if owner.attached_object.is_a?(Module))
              else
                BUILTIN_LINES["#{owner}##{name}"]
              end
      [place[0], place[3]] if place
    end

    def marked_builtins
      Primitive.attr! :hidden
      places = {}.compare_by_identity
      BUILTIN_LINES.each do |key, place|
        singleton = key.include?(".")
        owner_path, name = key.split(singleton ? "." : "#", 2)
        owner = Object.const_get(owner_path, false) rescue next
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

      path, _call, line = BUILTIN_LINES.fetch(+"TracePoint#enable")
      fire([EVENTS[:return], value, path, line, :enable, :enable, TracePoint, point, nil, 0, 0])
    end

    # A traced program fired the event `row` describes.
    def fire(row)
      Primitive.attr! :hidden
      return nil unless current_row.nil?

      # A :call or :return around one of CRuby's own Ruby methods reports
      # the position of that method in CRuby's builtin sources.
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
      # The last one runs first. A targeted point's hook is the code's own,
      # which ruby runs after the global ones.
      points = points.select { |point| Primitive.zr_hidden_get(point, :__target__) } + points.reject { |point| Primitive.zr_hidden_get(point, :__target__) }
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
    raise ArgumentError, +"only target_line is specified" if target.nil? && !target_line.nil?
    raise ArgumentError, +"can't nest-enable a targeting TracePoint" if target.nil? && enabled? && Primitive.zr_hidden_get(self, :__target__)

    aim(target, target_line) unless target.nil?
    if target_thread
      raise ArgumentError, +"can not override target_thread filter" if Primitive.zr_hidden_get(self, :__thread__)

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
    raise ArgumentError, +"can't disable a targeting TracePoint in a block" if block_given? && Primitive.zr_hidden_get(self, :__target__)

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
    when :thread_begin, :thread_end
      # These have no position, so tracepoint_inspect shows the thread.
      return "#<TracePoint:#{event} #{row[7].inspect}>"
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
    raise RuntimeError, +"not supported by this event" unless %i[return c_return b_return].include?(event)

    row[1]
  end

  def raised_exception
    raise RuntimeError, +"not supported by this event" unless %i[raise rescue].include?(event)

    row[1]
  end

  def parameters
    raise RuntimeError, +"not supported by this event" if %i[raise line class end script_compiled rescue].include?(event)
    # rb_tracearg_parameters returns the parameters for a call and a
    # return, refuses for the events above, and falls through to nil for
    # the others: an event that the machine fires is in no method and has none.
    return nil if %i[thread_begin thread_end fiber_switch].include?(event)
    return c_parameters if %i[c_call c_return].include?(event)

    Primitive.zr_trace_parameters(row[9], row[10], row[11])
  end

  # rb_unnamed_parameters: a C method's parameters, as its arity gives
  # them. The entry that was called answers: an alias still has them
  # after its original name is removed.
  def c_parameters
    Primitive.attr! :hidden
    klass = defined_class or return []
    [callee_id, method_id].uniq.each do |name|
      return klass.instance_method(name).parameters if klass.method_defined?(name, false) || klass.private_method_defined?(name, false)
    end
    []
  end
  private :c_parameters

  # The string that this code was compiled from, or nil when it came from
  # a file, as rb_tracearg_eval_script returns nil for an iseq alone.
  def eval_script
    raise RuntimeError, +"not supported by this event" unless event == :script_compiled

    row[1][0]
  end

  # The code itself, which rb_tracearg_instruction_sequence wraps for
  # the handler. This runtime has no bytecode to give, so the sequence
  # contains what the record kept of it: its method name, its label and
  # its first line.
  def instruction_sequence
    raise RuntimeError, +"not supported by this event" unless event == :script_compiled

    _script, path, label, line = row[1]
    RubyVM::InstructionSequence.send(:made, nil, nil, label, label, path, line)
  end

  private

  # The record of the event being handled, for any TracePoint.
  def row
    Primitive.attr! :hidden
    TracePoint.send(:current_row) or raise RuntimeError, +"access from outside"
  end

  # rb_tracepoint_enable_for_target: the code the target runs, which
  # must be Ruby's, and the line in it, which only a :line event has.
  def aim(target, line)
    Primitive.attr! :hidden
    raise ArgumentError, +"specified target is not supported" if RubyVM::InstructionSequence.of(target).nil?
    raise ArgumentError, +"can't nest-enable a targeting TracePoint" if enabled?

    events = Primitive.zr_hidden_get(self, :__events__)
    raise ArgumentError, +"target_line is specified, but line event is not specified" if line && (events & EVENTS[:line]).zero?

    # rb_iseq_add_local_tracepoint_recursively: a hook only for an event
    # that the target's code fires, and only on a line of it.
    raise ArgumentError, +"can not enable any hooks" if (events & (TARGET_EVENTS.fetch(target.is_a?(Proc)) | C_EVENTS)).zero?

    line = line.is_a?(Integer) ? line : Primitive.zr_index_operand_m(line) unless line.nil?
    raise ArgumentError, +"can not enable any hooks" if line && (line.negative? || !target_line?(target, line))

    Primitive.zr_hidden_set(self, :__target__, target)
    Primitive.zr_hidden_set(self, :__target_line__, line)
  end

  # The events that a Proc's code (true) or a method's code (false) and the
  # blocks in it can fire.
  TARGET_EVENTS = {
    true => EVENTS.values_at(:line, :b_call, :b_return, :rescue).sum,
    false => EVENTS.values_at(:line, :call, :return, :b_call, :b_return, :rescue).sum
  }.freeze
  private_constant :TARGET_EVENTS

  # Whether `line` of `target` fires a :line event. For a block, whose
  # lines zr does not list, a line before its first one does not.
  def target_line?(target, line)
    Primitive.attr! :hidden
    RubyVM::InstructionSequence.of(target).trace_points.any? { |at, _| at == line }
  rescue NotImplementedError
    line >= target.source_location[1]
  end

  def switch(on)
    Primitive.attr! :hidden
    points = TracePoint.send(:enabled)
    if on
      TracePoint.send(:untraced!)
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
