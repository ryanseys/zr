# frozen_string_literal: true

# Ractor: a separate task with a boundary around it. Every value that
# crosses the boundary is shareable or a copy of its whole graph, so two
# ractors never share a mutable object. The tasks are green, as every
# task in this runtime is. A program that measures results, not
# parallelism, gets the same results as ruby.
class Ractor
  class Error < RuntimeError; end
  class IsolationError < Error; end
  class ClosedError < StopIteration; end
  class MovedError < Error; end
  class RemoteError < Error
    # The ractor whose failure this represents.
    def ractor = Primitive.zr_hidden_get(self, :__ractor__)
  end
  class UnsafeError < Error; end

  # What a moved object becomes. CRuby swaps the class of the graph it
  # gave away, so the sender still has the cell and every message to it
  # is refused. These are all the methods of a husk.
  class MovedObject < BasicObject
    def !
      ::Ractor.__send__(:moved!)
    end

    def !=(_other)
      ::Ractor.__send__(:moved!)
    end

    def ==(_other)
      ::Ractor.__send__(:moved!)
    end

    def __id__
      ::Ractor.__send__(:moved!)
    end

    def __send__(*)
      ::Ractor.__send__(:moved!)
    end

    def equal?(_other)
      ::Ractor.__send__(:moved!)
    end

    def instance_eval(*)
      ::Ractor.__send__(:moved!)
    end

    def instance_exec(*)
      ::Ractor.__send__(:moved!)
    end

    def method_missing(*)
      ::Ractor.__send__(:moved!)
    end
  end

  # A port: one end of a message queue, which belongs to the ractor that
  # made it. Any ractor can send to a port; only its owner receives. A
  # port is shareable, so it is frozen. Its queue is state kept next to
  # the object, not an instance variable of it.
  class Port
    def initialize
      seat(Ractor.current)
    end

    # The default port of `ractor`, which its setup makes before the
    # ractor is current anywhere.
    def self.of(ractor)
      Primitive.attr! :hidden
      port = Primitive.zr_class_build(self)
      port.__send__(:seat, ractor)
      port
    end
    private_class_method :of

    # A port is frozen from its allocation, so ractor.c's copy never
    # starts: init_copy refuses the frozen copy first.
    def initialize_copy(_orig) = raise(TypeError, "[bug] frozen object (#{self.class}) allocated")

    # A message for the owner, copied over the boundary, or handed over
    # when the sender gives the graph up.
    def send(obj, move: false)
      raise ClosedError, "The port was already closed" if closed?

      queue << (move ? Ractor.__send__(:hand_over, obj, owner) : Ractor.__send__(:copy, obj))
      Thread.__send__(:rouse, waiters.dup)
      self
    end

    alias << send

    # The next message, waited for. A port with nothing left to give and
    # no sender that can reach it any more is closed, and says so. A
    # `timeout` (seconds) that passes with no message gives nil.
    def receive(timeout: nil)
      mine!
      deadline = Ractor.__send__(:deadline, timeout)
      while queue.empty?
        raise ClosedError, "The port was already closed" if closed?
        return nil if Ractor.__send__(:passed?, deadline)

        Thread.current.__send__(:wait_on, waiters, deadline, true)
      end
      queue.shift
    end

    def close
      Primitive.zr_state_set(self, :__closed__, true)
      Thread.__send__(:rouse, waiters.dup)
      nil
    end

    def closed? = Primitive.zr_hidden_get(self, :__closed__)

    def inspect = "#<Ractor::Port to:##{Primitive.zr_hidden_get(owner, :__number__)} id:#{Primitive.zr_hidden_get(self, :__id__)}>"

    private

    # The port's state: its owner, and the owner's next port number (the
    # default port is 0, as ractor_genid_for_port counts them).
    def seat(ractor)
      Primitive.attr! :hidden
      Primitive.zr_state_set(self, :__queue__, [])
      Primitive.zr_state_set(self, :__waiters__, [])
      Primitive.zr_state_set(self, :__owner__, ractor)
      Primitive.zr_state_set(self, :__id__, Ractor.__send__(:next_port_id, ractor))
      Primitive.zr_state_set(self, :__closed__, false)
      freeze
    end

    def queue
      Primitive.attr! :hidden
      Primitive.zr_hidden_get(self, :__queue__)
    end

    def waiters
      Primitive.attr! :hidden
      Primitive.zr_hidden_get(self, :__waiters__)
    end

    # The ractor that made the port.
    def owner
      Primitive.attr! :hidden
      Primitive.zr_hidden_get(self, :__owner__)
    end

    def mine!
      Primitive.attr! :hidden
      return self if owner.equal?(Ractor.current)

      raise Error, "only allowed from the creator Ractor of this port"
    end

    # Whether a message waits, and the message: `Ractor.select` checks
    # its own ports this way, so it never parks on a full one.
    def waiting?
      Primitive.attr! :hidden
      !queue.empty?
    end

    def take_now
      Primitive.attr! :hidden
      queue.shift
    end
  end

  # The classes that hold a task or a lock, which no ractor can share.
  UNSHAREABLE = [Thread, Thread::Mutex, Thread::Queue, Thread::SizedQueue, Thread::ConditionVariable].freeze
  private_constant :UNSHAREABLE

  # Every ractor of this process but the main one, by number, and the
  # notice ruby prints once.
  RACTORS = {}
  NOTICE = []
  private_constant :RACTORS, :NOTICE

  # ractor_create's order: the name, the ractor's number, the isolated
  # block, then each argument as a message of its own.
  def self.new(*args, name: nil, &block)
    raise ArgumentError, "must be called with a block" unless block

    notice
    # The name is a String before anything starts, as ractor_init reads it.
    name = Primitive.zr_str_operand(name) unless name.nil?
    number = next_number
    isolate(block)
    ractor = Primitive.zr_class_build(self)
    start(ractor, number, args.map { |arg| copy(arg) }, block, caller(1, 1)&.first)
    name!(ractor, name) unless name.nil?
    ractor
  end

  # The number of a new ractor: one more than the last one, as
  # ractor_next_id counts them. A Ractor.new that fails takes one too.
  def self.next_number
    Primitive.attr! :hidden
    number = (Primitive.zr_hidden_get(self, :__numbers__) || 1) + 1
    Primitive.zr_hidden_set(self, :__numbers__, number)
    number
  end
  private_class_method :next_number

  # The experimental notice, once per process for any number of ractors,
  # with the line that requested the first one.
  def self.notice
    Primitive.attr! :hidden
    return nil unless NOTICE.empty?

    NOTICE << true
    Warning.experimental("Ractor API is experimental and may change in future versions of Ruby.")
  end
  private_class_method :notice

  # rb_proc_isolate_bang: a block that a ractor runs reaches nothing
  # outside itself, and keeps no instance variable. Ruby decides this when
  # the ractor is made, not when the block is written, and names what the
  # block reaches. The block is shareable from then on.
  def self.isolate(block)
    Primitive.attr! :hidden
    outer!(block, "isolate a Proc", Primitive.zr_proc_captures_m(block))
    raise IsolationError, "can not isolate a Proc because it has instance variables" unless Primitive.zr_ivar_names_m(block).empty?

    Primitive.zr_set_shareable_m(block)
  end
  private_class_method :isolate

  # proc_shared_outer_variables: the refusal of a block that reaches the
  # outer locals `names`, or the method's block through `yield`.
  def self.outer!(block, action, names)
    Primitive.attr! :hidden
    yields = Primitive.zr_proc_yields_m(block)
    return if names.empty? && !yields
    raise IsolationError, "can not #{action} because it uses 'yield'." if names.empty?

    raise IsolationError, "can not #{action} because it accesses outer variables (#{names.join(", ")})#{" and uses 'yield'" if yields}."
  end
  private_class_method :outer!

  # A copy of the block that any ractor can call: frozen, with `self:`
  # as its self (nil unless given), and no Binding to reach its scope.
  def self.shareable_proc(**options, &block)
    raise ArgumentError, "tried to create Proc object without a block" unless block

    shareable(block, options, lambda: false)
  end

  # The same, and a literal block becomes a lambda.
  def self.shareable_lambda(**options, &block)
    raise ArgumentError, "tried to create Proc object without a block" unless block

    shareable(block, options, lambda: true)
  end

  # Ruby's rules for a shareable block, in ruby's order. Its self must
  # be shareable. It cannot write a local outside itself, nor use
  # `yield`. Every local that it reads there must be bound once in its
  # own scope, so the value that the block copies is the only value of
  # the local. That value must be shareable.
  #
  # Ruby lists the locals in the order of its symbol table, which no
  # other ruby can know; here they are in the order of their first
  # declaration, and the read locals are checked from the last one.
  def self.shareable(block, options, lambda:)
    Primitive.attr! :hidden
    unknown = options.keys - [:self]
    raise ArgumentError, "unknown keyword#{"s" if unknown.size > 1}: #{unknown.map(&:inspect).join(", ")}" unless unknown.empty?

    receiver = options[:self]
    raise IsolationError, "self should be shareable: #{receiver.inspect}" unless shareable?(receiver)

    rows = Primitive.zr_proc_capture_rows_m(block)
    outer!(block, "make a Proc shareable", rows.select { |_, write, _| write }.map(&:first))
    scope = Primitive.zr_proc_scope(block) unless rows.empty?
    rows.reverse_each do |name, _, rebound|
      raise IsolationError, "cannot make a shareable Proc because the outer variable '#{name}' may be reassigned." if rebound

      value = scope.local_variable_get(name)
      raise IsolationError, "cannot make a shareable Proc because it can refer unshareable object #{value.inspect} from variable '#{name}'" unless shareable?(value)
    end
    Primitive.zr_proc_isolated_m(block, receiver, lambda)
  end
  private_class_method :shareable

  # The main ractor, which is the one the program starts in.
  def self.main
    @main ||= begin
      seat(Primitive.zr_class_build(self), 1, Thread.main)
    end
  end

  # The ractor this task belongs to: the main one until a task of a
  # ractor's own says otherwise.
  def self.current
    number = Primitive.zr_ractor_number_m
    number.zero? ? main : RACTORS[number]
  end

  def self.count = RACTORS.each_value.count { |ractor| live?(ractor) } + 1

  # rb_multi_ractor_p: once a second ractor has been made, the process
  # stays multi-ractor.
  def self.multi?
    Primitive.attr! :hidden
    !RACTORS.empty?
  end

  def self.main? = current.equal?(main)

  # rb_ractor_require: a non-main ractor's require runs on the main ractor,
  # which may read what the ractor cannot; its value or its error comes
  # back to the ractor.
  def self.on_main
    Primitive.attr! :hidden
    number = Primitive.zr_ractor_leave_m
    begin
      yield
    ensure
      Primitive.zr_ractor_enter_m(number) unless number.zero?
    end
  end
  private_class_method :on_main

  # A message from this ractor's own port.
  def self.receive(timeout: nil) = current.default_port.receive(timeout: timeout)

  class << self
    alias recv receive
  end

  # The first message in any of the ports, or the value of the first
  # ractor to end, with what gave it. The ractors are watched through one
  # port of their own (made in the current ractor, as ractor.rb makes it),
  # which gets each one's exit token. A `timeout` that passes gives nil.
  def self.select(*ports, timeout: nil)
    Primitive.attr! :sends_each
    raise ArgumentError, "specify at least one Ractor::Port or Ractor" if ports.empty?

    monitored = []
    others = []
    watch = nil
    begin
      ports.each do |arg|
        case arg
        when Ractor then monitored << arg
        when Port then others << arg
        else raise ArgumentError, "should be Ractor::Port or Ractor"
        end
      end
      unless monitored.empty?
        watch = Port.new
        monitored.each { |ractor| ractor.monitor(watch) }
      end
      port, message = first_message(watch ? [watch, *others] : others, deadline(timeout))
      return nil if port.nil?
      return [port, message] unless port.equal?(watch)

      ractor = message[0]
      [ractor, ractor.value]
    ensure
      if watch
        monitored.each { |ractor| ractor.unmonitor(watch) }
        watch.close
      end
    end
  end

  # The first message of `ports`, with the port it came from, or nil when
  # the deadline passes first. A closed port with nothing left ends the
  # wait, as CRuby's does.
  def self.first_message(ports, deadline)
    Primitive.attr! :hidden
    loop do
      ports.each do |port|
        return [port, port.__send__(:take_now)] if port.__send__(:waiting?)
        raise ClosedError, "The port was already closed" if port.closed?
      end
      return nil if passed?(deadline)

      parked(ports, deadline)
    end
  end
  private_class_method :first_message

  # Sleeps until a send to any of the ports wakes this task, or the
  # deadline passes. Nothing else runs between the test above and the
  # park, so no message is missed.
  def self.parked(ports, deadline)
    Primitive.attr! :hidden
    me = Thread.current
    ports.each { |port| port.__send__(:waiters) << me }
    begin
      me.__send__(:wait, deadline, true)
    ensure
      ports.each { |port| port.__send__(:waiters).delete(me) }
    end
  end
  private_class_method :parked

  # The monotonic time in nanoseconds when a wait of `timeout` seconds
  # ends, read as rb_time_interval reads it, or nil to wait for good.
  def self.deadline(timeout)
    Primitive.attr! :hidden
    return nil if timeout.nil?

    Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) + (Thread.__send__(:interval, timeout) * 1e9).to_i
  end
  private_class_method :deadline

  def self.passed?(deadline)
    Primitive.attr! :hidden
    !deadline.nil? && Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) >= deadline
  end
  private_class_method :passed?

  def self.[](key) = locals(current)[key.to_sym]

  # rb_ractor_local_storage_value_lookup: whether the current Ractor
  # holds `key` (a value of nil counts), and its value.
  def self.c_local(key)
    Primitive.attr! :hidden
    locals = locals(current)
    [locals.key?(key), locals[key]]
  end

  def self.[]=(key, value)
    locals(current)[key.to_sym] = value
  end

  def self.store_if_absent(key)
    locals = locals(current)
    key = key.to_sym
    locals.key?(key) ? locals[key] : (locals[key] = yield)
  end

  def self.make_shareable(obj, copy: false)
    return make_shareable(copy(obj, true)) if copy

    seen = {}.compare_by_identity
    deep_freeze(obj, seen)
    # Each object in the graph is shareable from now on.
    seen.each_key { |node| Primitive.zr_set_shareable_m(node) }
    obj
  end

  # Whether every object reachable from `obj` is frozen. A number, a
  # symbol, a class and the three singletons are shareable as they are,
  # and so is an object that the runtime marked shareable (a Ractor, ENV,
  # an isolated Proc). A husk left by a move accepts no message, so it is
  # shareable. C data that holds a task, a lock or a handle on the system
  # is never shareable. A frozen Method is shareable when its receiver is
  # (RUBY_TYPED_FROZEN_SHAREABLE_NO_REC).
  def self.shareable?(obj)
    return true if moved?(obj) || immutable?(obj) || Primitive.zr_shareable_mark_p_m(obj)
    return false unless Primitive.zr_frozen_p_m(obj) && !unshareable?(obj)
    return shareable?(obj.receiver) if Method === obj

    each_reachable(obj) { |ref| return false unless shareable?(ref) }
  end

  # The value a shareable constant takes, when the compiler cannot see
  # that the value is a literal. Ruby demands a value that is already
  # shareable there.
  def self.ensure_shareable(value, name)
    Primitive.attr! :hidden
    raise IsolationError, "cannot assign unshareable object to #{name}" unless shareable?(value)

    value
  end

  # rb_check_ivar_modifiable's refusal, for an object that is shareable
  # but not frozen. The runtime calls this because the words are here.
  def self.isolation!(obj)
    Primitive.attr! :hidden
    raise IsolationError, "can't modify instance variables of a shareable #{Primitive.zr_real_class(obj)}"
  end

  # What a ractor cannot reach in a class that another ractor created,
  # in CRuby's words (class ownership). The runtime calls these, with the
  # class, a name and a value, because the words are here; a read gives
  # the value back when it is shareable.
  def self.foreign_class!(klass, _name, _value)
    Primitive.attr! :hidden
    # A singleton class is named by its object, with no dispatch.
    named = klass.singleton_class? ? klass.attached_object : klass
    raise IsolationError, "can not modify #{Module === named ? path(named) : ANY_TO_S.bind_call(named)} because it is created by another Ractor"
  end

  def self.const_read(owner, name, value)
    Primitive.attr! :hidden
    return value if shareable?(value)

    raise IsolationError, "can not access non-shareable objects in constant #{path(owner)}::#{name} of a class/module created by another Ractor."
  end

  def self.const_write!(_owner, _name, _value)
    Primitive.attr! :hidden
    raise IsolationError, "can not set constants of classes/modules created by another Ractor"
  end

  def self.class_ivar_read(owner, name, value)
    Primitive.attr! :hidden
    return value if shareable?(value)

    raise IsolationError, "can not get unshareable values from instance variables of classes/modules created by another Ractor " \
                          "(#{name} from #{path(owner)})"
  end

  def self.class_ivar_write!(_owner, _name, _value)
    Primitive.attr! :hidden
    raise IsolationError, "can not set instance variables of classes/modules created by another Ractor"
  end

  def self.cvar_read(owner, name, value)
    Primitive.attr! :hidden
    return value if shareable?(value)

    raise IsolationError, "can not read non-shareable class variable #{name} of #{owner}, which was created by another Ractor"
  end

  def self.cvar_write!(owner, name, _value)
    Primitive.attr! :hidden
    raise IsolationError, "can not set class variable #{name} of #{owner}, which was created by another Ractor"
  end

  # init_copy_owner_check: a copy of a class or module that another
  # ractor made is the copying ractor's, so it takes no unshareable value.
  def self.copy_entry(_owner, name, value)
    Primitive.attr! :hidden
    return if shareable?(value)

    raise IsolationError, "can not copy a class/module created by another Ractor because " \
                          "#{entry_kind(name)} #{name} refers to an unshareable object"
  end

  # rb_class_check_singleton_movable: the receiver of a moved object
  # owns its singleton class, so the sender's unshareable values may not
  # go with it.
  def self.move_entry(_owner, name, value)
    Primitive.attr! :hidden
    return if shareable?(value)

    raise IsolationError, "can not move an object whose singleton class has " \
                          "#{entry_kind(name)} #{name} referring to an unshareable object"
  end

  def self.entry_kind(name)
    Primitive.attr! :hidden
    name.start_with?("@") ? "variable" : "constant"
  end
  private_class_method :copy_entry, :move_entry, :entry_kind

  def self.gvar_isolation!(name)
    Primitive.attr! :hidden
    raise IsolationError, "can not access global variable #{name} from non-main Ractor"
  end

  # rb_class_path: a module's name as its constant gives it, which no
  # `to_s` of the program changes; rb_any_to_s for any other object.
  MODULE_TO_S = Module.instance_method(:to_s)
  ANY_TO_S = Kernel.instance_method(:to_s)
  private_constant :MODULE_TO_S, :ANY_TO_S

  def self.path(mod)
    Primitive.attr! :hidden
    MODULE_TO_S.bind_call(mod)
  end
  private_class_method :path

  # The refusal a husk gives every message it still gets.
  def self.moved!
    Primitive.attr! :hidden
    raise MovedError, "can not send any methods to a moved object"
  end
  private_class_method :moved!

  # Whether `obj` is a husk a move left behind.
  def self.moved?(obj)
    Primitive.attr! :hidden
    !Primitive.zr_special_p_m(obj) && Primitive.zr_class_of(obj) == MovedObject
  end
  private_class_method :moved?

  def self.immutable?(obj)
    Primitive.attr! :hidden
    case obj
    when Integer, Float, Symbol, Module, Encoding, NilClass, TrueClass, FalseClass then true
    else false
    end
  end

  def self.deep_freeze(obj, seen)
    Primitive.attr! :hidden
    return if immutable?(obj) || moved?(obj) || Primitive.zr_shareable_mark_p_m(obj) || seen.key?(obj)

    raise Error, "can not make shareable object for #{obj.inspect}" if unshareable?(obj)

    seen[obj] = true
    return freeze_method(obj) if Method === obj

    shareable_proc!(obj) if Proc === obj
    # make_shareable_check_shareable_freeze: the program's #freeze runs,
    # and one that leaves the object unfrozen is an error.
    unless obj.frozen?
      obj.send(:freeze)
      raise Error, +"#freeze does not freeze object correctly" unless obj.frozen?
    end
    each_reachable(obj) { |ref| deep_freeze(ref, seen) }
  end

  # rb_proc_ractor_make_shareable: a Proc that the core makes (a Method's,
  # a Hash's, a curry) is C in CRuby and cannot be made shareable. Any
  # other keeps its self wherever it runs, so the self must be shareable.
  def self.shareable_proc!(obj)
    Primitive.attr! :hidden
    raise RuntimeError, +"not supported yet" if Primitive.zr_proc_c_level_m(obj)
    raise IsolationError, "Proc's self is not shareable: #{obj.inspect}" unless shareable?(Primitive.zr_proc_self_m(obj))
  end

  # A Method refers to its receiver but does not make it shareable
  # (RUBY_TYPED_FROZEN_SHAREABLE_NO_REC): the receiver must be shareable
  # already, and only the Method is frozen.
  def self.freeze_method(obj)
    Primitive.attr! :hidden
    raise Error, "can not make shareable object for #{obj.inspect} because it refers unshareable objects" unless shareable?(obj.receiver)

    obj.send(:freeze) unless obj.frozen?
    nil
  end

  # The objects that CRuby keeps as C data that is not shareable when
  # frozen: a task, a lock, a handle on the system, or a scope.
  def self.unshareable?(obj)
    Primitive.attr! :hidden
    case obj
    when Thread, Thread::Mutex, Thread::Queue, Thread::SizedQueue, Thread::ConditionVariable, ThreadGroup, Monitor,
         Enumerator, Binding, Fiber, Random, TracePoint, Thread::Backtrace::Location, ObjectSpace::WeakMap,
         ObjectSpace::WeakKeyMap, IO::Buffer, IO, Dir, File::Stat, Encoding::Converter
      true
    else false
    end
  end

  # Whether ruby keeps `obj` as C data (a T_DATA, or an IO's T_FILE).
  # ractor.c's courier copies such an object only through a dump hook,
  # and moves none of them but an IO.
  def self.c_data?(obj)
    Primitive.attr! :hidden
    case obj
    when IO, Set, Thread::Backtrace, TracePoint, ThreadGroup, Monitor, Dir, File::Stat, IO::Buffer, Enumerator::Yielder,
         Enumerator::Generator, ObjectSpace::WeakKeyMap, Binding, Encoding::Converter
      true
    else Marshal.__send__(:data_kind?, Primitive.zr_real_class(obj))
    end
  end
  private_class_method :c_data?

  # Gives each object that one object refers to, to the block: its parts,
  # then its instance variables. A walk over a graph of Strings and
  # numbers makes no Array a node. The return value is true, so a caller
  # can `return` its own value out of the block. The parts are read as
  # the C reads them, with no `each` of a subclass.
  def self.each_reachable(obj)
    Primitive.attr! :hidden
    case obj
    when Array then Primitive.zr_ary_len_m(obj).times { |i| yield Primitive.zr_ary_at_m(obj, i) }
    when Hash
      Primitive.zr_hash_foreach(obj) { |key, value| yield key; yield value }
      yield obj.default
    when Range
      yield obj.begin
      yield obj.end
    when Struct, Data then struct_values(obj).each { |part| yield part }
    end
    Primitive.zr_ivar_names_m(obj).each { |name| yield Primitive.zr_hidden_get(obj, name) }
    true
  end

  # A value crossing the boundary (ractor_prepare_payload): a shareable
  # one by reference, any other as a copy of its whole graph. The whole
  # graph is checked first, so a refusal copies nothing and runs no hook;
  # it names the class of the value that was sent. `deeply` also copies a
  # shareable value, as `make_shareable(copy: true)` requires.
  def self.copy(value, deeply = false)
    Primitive.attr! :hidden
    return value if immutable?(value) || (!deeply && shareable?(value))
    raise Error, "can not copy #{Primitive.zr_class_of(value)} object." unless copyable?(value, {}.compare_by_identity, deeply)

    cross(value, {}.compare_by_identity, deeply)
  end
  private_class_method :copy

  # copy_courier_supported_p: whether the courier can carry the graph. C
  # data goes only through a dump hook, whose result is not walked here.
  def self.copyable?(value, seen, deeply)
    Primitive.attr! :hidden
    return true if immutable?(value) || (!deeply && shareable?(value)) || seen.key?(value) || location?(value)

    seen[value] = true
    if c_data?(value)
      return false unless hook(value)
    else
      each_ref(value) { |ref| return false unless copyable?(ref, seen, deeply) }
    end
    instance_refs(value) { |ref| return false unless copyable?(ref, seen, deeply) }
    true
  end
  private_class_method :copyable?

  # A backtrace's location: ruby copies a backtrace natively, so an
  # Exception's locations go with it as they are.
  def self.location?(value)
    Primitive.attr! :hidden
    Thread::Backtrace::Location === value
  end
  private_class_method :location?

  # The dump hook of C data, in Marshal's order (courier_hook_of). A Set
  # takes Marshal's compat path, which comes to the same as a copy of its
  # table.
  def self.hook(value)
    Primitive.attr! :hidden
    if value.respond_to?(:marshal_dump, true) then :marshal_dump
    elsif value.respond_to?(:_dump, true) then :_dump
    elsif Set === value then :compat
    elsif value.respond_to?(:_dump_data, true) then :_dump_data
    end
  end
  private_class_method :hook

  # The references of `value` that its kind keeps outside its instance
  # variables: an Array's elements, a Hash's keys, values and default
  # (a default proc is a Proc, which no courier carries), an Exception's
  # message, cause and backtrace.
  def self.each_ref(value)
    Primitive.attr! :hidden
    case value
    when Array then Primitive.zr_ary_len_m(value).times { |i| yield Primitive.zr_ary_at_m(value, i) }
    when Hash
      Primitive.zr_hash_foreach(value) do |key, part|
        yield key
        yield part
      end
      yield value.default_proc || value.default
    when Exception then Primitive.zr_exc_refs_m(value).each { |ref| yield ref }
    end
    nil
  end
  private_class_method :each_ref

  # The values of every instance variable of `value`, the runtime's
  # hidden ones too: a Struct's values, a Range's bounds, a MatchData's
  # String are kept there.
  def self.instance_refs(value)
    Primitive.attr! :hidden
    Primitive.zr_ivar_all_names_m(value).each { |name| yield Primitive.zr_hidden_get(value, name) }
    nil
  end
  private_class_method :instance_refs

  # The copy of a graph that `copyable?` passed. An object that appears
  # twice in the graph is copied once, so a cycle comes out a cycle. A
  # move (`given`) collects the nodes that the sender gives up.
  def self.cross(value, seen, deeply, given = nil)
    Primitive.attr! :hidden
    return value if immutable?(value) || (!deeply && shareable?(value)) || location?(value)
    return seen[value] if seen.key?(value)
    return hooked(value, seen, deeply) if !given && c_data?(value)

    copy = Primitive.zr_copy_cell(value)
    seen[value] = copy
    given << value if given
    fill(value, copy, seen, deeply, given)
    Primitive.zr_ivar_all_names_m(value).each do |name|
      Primitive.zr_state_set(copy, name, cross(Primitive.zr_hidden_get(value, name), seen, deeply, given))
    end
    copy.freeze if Primitive.zr_frozen_p_m(value)
    copy
  end
  private_class_method :cross

  # The parts of a copy that are not instance variables: the contents
  # that the class itself stores, which `zr_copy_cell` leaves empty.
  def self.fill(value, copy, seen, deeply, given)
    Primitive.attr! :hidden
    case value
    when String then copy.replace(value)
    when Array then Primitive.zr_ary_len_m(value).times { |i| copy << cross(Primitive.zr_ary_at_m(value, i), seen, deeply, given) }
    when Hash
      copy.compare_by_identity if value.compare_by_identity?
      Primitive.zr_hash_foreach(value) { |key, part| copy[cross(key, seen, deeply, given)] = cross(part, seen, deeply, given) }
      copy.default = cross(value.default, seen, deeply, given) unless value.default.nil?
    when Regexp then Primitive.zr_regexp_copy_from(copy, value)
    when Exception then Primitive.zr_exc_set_refs_m(copy, Primitive.zr_exc_refs_m(value).map { |ref| cross(ref, seen, deeply, given) })
    end
    nil
  end
  private_class_method :fill

  # C data, copied through its dump hook, as Marshal would carry it. The
  # receiving side's load runs here, at the send.
  def self.hooked(value, seen, deeply)
    Primitive.attr! :hidden
    klass = Primitive.zr_real_class(value)
    case hook(value)
    when :marshal_dump
      copy = seen[value] = Primitive.zr_class_allocate(klass)
      copy.__send__(:marshal_load, cross(value.__send__(:marshal_dump), seen, deeply))
    when :_dump then copy = seen[value] = klass.__send__(:_load, value.__send__(:_dump, -1))
    when :compat
      copy = seen[value] = Primitive.zr_copy_cell(value)
      Primitive.zr_ivar_all_names_m(value).each do |name|
        Primitive.zr_state_set(copy, name, cross(Primitive.zr_hidden_get(value, name), seen, deeply))
      end
    else
      copy = seen[value] = Primitive.zr_class_allocate(klass)
      copy.__send__(:_load_data, cross(value.__send__(:_dump_data), seen, deeply))
    end
    copy.freeze if Primitive.zr_frozen_p_m(value)
    copy
  end
  private_class_method :hooked

  # The values of a Struct or a Data, as the object stores them: none
  # yet for one that was only allocated.
  def self.struct_values(obj)
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(obj, :__values__) || []
  end
  private_class_method :struct_values

  # A value that the sender gives up to `receiver`: the receiver gets the
  # graph, with each node's singleton class, which it then owns, and every
  # node that the sender still points at becomes a husk. A graph with an
  # unmovable object in it is refused before anything moves, so the
  # sender keeps what it had.
  def self.hand_over(value, receiver)
    Primitive.attr! :hidden
    return value if immutable?(value) || shareable?(value)

    unmovable!(value, {}.compare_by_identity)
    given = []
    seen = {}.compare_by_identity
    copy = cross(value, seen, false, given)
    taker = receiver.equal?(main) ? 0 : Primitive.zr_hidden_get(receiver, :__number__)
    given.each do |node|
      Primitive.zr_move_singleton_m(node, seen[node], taker)
      node.__send__(:moved_into, seen[node]) if IO === node
      Primitive.zr_moved_m(node, MovedObject)
    end
    copy
  end
  private_class_method :hand_over

  # move_preflight: C data moves only when it is an IO, and a singleton
  # class moves with its object only when it holds shareable values.
  def self.unmovable!(value, seen)
    Primitive.attr! :hidden
    return if immutable?(value) || shareable?(value) || seen.key?(value) || location?(value)

    seen[value] = true
    Primitive.zr_singleton_movable_m(value)
    raise Error, "can not move a #{Primitive.zr_real_class(value)} object" if c_data?(value) && !(IO === value)

    each_ref(value) { |ref| unmovable!(ref, seen) }
    instance_refs(value) { |ref| unmovable!(ref, seen) }
  end
  private_class_method :unmovable!

  def name = Primitive.zr_hidden_get(self, :__name__)

  def [](key) = Ractor.__send__(:locals, self)[key.to_sym]

  def []=(key, value)
    Ractor.__send__(:locals, self)[key.to_sym] = value
  end

  # The port every message to the ractor goes through, which the ractor
  # itself receives from.
  def default_port = Primitive.zr_hidden_get(self, :__port__)

  # A message for the ractor: its default port keeps it until the ractor
  # takes it, in the order it arrived.
  def send(...)
    Primitive.attr! :ruby
    default_port.send(...)
    self
  end

  alias << send

  # The return value of the ractor's block, after it ends, as it is: the
  # ractor that takes it owns it from then on. A failure in the block
  # arrives here wrapped, with the original as its cause. Only the first
  # ractor to ask (the successor) takes it, and only once.
  def value
    join
    Ractor.__send__(:take, self)
  end

  # Waits for the ractor to end, through a port of the current ractor.
  # A ractor that failed raises its failure here, which takes the value.
  def join
    port = Port.new
    monitor(port)
    Ractor.__send__(:take, self) if port.receive[1] == :aborted
    self
  ensure
    port&.close
  end

  # Sends `[ractor, :exited]` on `port` when the ractor ends and its
  # block returned, `[ractor, :aborted]` when something was raised out of
  # it. A ractor that has already ended sends it immediately and returns
  # false.
  def monitor(port)
    unless Ractor.__send__(:live?, self)
      port.send([self, Ractor.__send__(:token, self)])
      return false
    end
    Primitive.zr_hidden_get(self, :__monitors__) << port
    true
  end

  def unmonitor(port)
    Primitive.zr_hidden_get(self, :__monitors__).delete(port)
    self
  end

  # Closes the default port, which only the ractor that owns it may do.
  def close = default_port.close

  # What `require` becomes inside a ractor. This runtime loads every
  # file on the one task that runs the program, so it is Kernel's own.
  def self._require(feature) = Kernel.required(feature)

  private def receive(timeout: nil) = default_port.receive(timeout: timeout)
  alias recv receive

  def inspect
    site = Primitive.zr_hidden_get(self, :__site__)
    text = +"#<Ractor:##{Primitive.zr_hidden_get(self, :__number__)}"
    text << " " << name if name
    text << " " << site if site
    "#{text} #{Ractor.__send__(:live?, self) ? 'running' : 'terminated'}>"
  end

  alias to_s inspect

  # A ractor's own state is in hidden slots, as CRuby keeps it in C
  # fields: a program sees no instance variable on a Ractor, and cannot
  # give it one (a Ractor is shareable). The class reads the state, so a
  # program that reopens Ractor and defines a method of the same name
  # (bootstraptest's `setup`) changes nothing here.

  def self.name!(ractor, text)
    Primitive.attr! :hidden
    Primitive.zr_hidden_set(ractor, :__name__, text.to_str.dup.freeze)
  end
  private_class_method :name!

  # The storage of `ractor`, which only the ractor itself may read.
  def self.locals(ractor)
    Primitive.attr! :hidden
    raise RuntimeError, "Cannot get ractor local storage for non-current ractor" unless ractor.equal?(current)

    Primitive.zr_hidden_get(ractor, :__locals__)
  end
  private_class_method :locals

  # How the ractor's block ended: :exited, or :aborted when something was
  # raised out of it.
  def self.token(ractor)
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(ractor, :__token__) || :exited
  end
  private_class_method :token

  # The number of the next port that `ractor` makes.
  def self.next_port_id(ractor)
    Primitive.attr! :hidden
    id = Primitive.zr_hidden_get(ractor, :__ports__) || 0
    Primitive.zr_hidden_set(ractor, :__ports__, id + 1)
    id
  end
  private_class_method :next_port_id

  # The state that every ractor has, the main one too: its number, its
  # task, its storage, its watchers and its port 0.
  def self.seat(ractor, number, task)
    Primitive.attr! :hidden
    Primitive.zr_set_shareable_m(ractor)
    Primitive.zr_hidden_set(ractor, :__locals__, {})
    Primitive.zr_hidden_set(ractor, :__monitors__, [])
    Primitive.zr_hidden_set(ractor, :__number__, number)
    Primitive.zr_hidden_set(ractor, :__thread__, task)
    Primitive.zr_hidden_set(ractor, :__port__, Port.__send__(:of, ractor))
    ractor
  end
  private_class_method :seat

  # Starts `ractor`'s task, which runs the block with the arguments.
  def self.start(ractor, number, args, block, where)
    Primitive.attr! :hidden
    seat(ractor, number, nil)
    RACTORS[number] = ractor
    Primitive.zr_hidden_set(ractor, :__site__, where && where[0, where.index(":in ") || where.size])
    # The block's self is the ractor, as with ruby's isolated block. Its
    # own copy is rebound, so a block that the program still has keeps the
    # self it was written with.
    body = Primitive.zr_proc_rebind_m(block.dup, ractor)
    task = Thread.new do
      Primitive.zr_ractor_enter_m(number)
      # The ractor has a default thread group of its own, which its
      # threads start in.
      Primitive.zr_hidden_set(Thread.current, :group, ThreadGroup.new)
      begin
        answer = body.call(*args)
        Primitive.zr_hidden_set(ractor, :__token__, :exited)
        answer
      rescue Exception # rubocop:disable Lint/RescueException
        Primitive.zr_hidden_set(ractor, :__token__, :aborted)
        raise
      ensure
        ended(ractor)
      end
    end
    # The task is the ractor's, not a thread that the program requested,
    # so a report shows no line of its own for it.
    Primitive.zr_hidden_set(task, :site, nil)
    Primitive.zr_hidden_set(ractor, :__thread__, task)
    ractor
  end
  private_class_method :start

  # The end of the ractor's task: nothing reaches it any more, so its
  # port closes, and everything watching it gets its token.
  def self.ended(ractor)
    Primitive.attr! :hidden
    monitors = Primitive.zr_hidden_get(ractor, :__monitors__)
    monitors.each { |port| port.send([ractor, token(ractor)]) unless port.closed? }
    monitors.clear
    Primitive.zr_hidden_get(ractor, :__port__).close
  end
  private_class_method :ended

  def self.live?(ractor)
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(ractor, :__thread__).alive?
  end
  private_class_method :live?

  # ractor_value: the value of the ended ractor, which the first ractor
  # to ask for it (the successor) takes once. A failure in the ractor is
  # ruby's RemoteError here, with the failure as its cause.
  def self.take(ractor)
    Primitive.attr! :hidden
    successor = Primitive.zr_hidden_get(ractor, :__successor__)
    if successor.nil?
      successor = current
      Primitive.zr_hidden_set(ractor, :__successor__, successor)
    end
    raise Error, "Only the successor ractor can take a value" unless successor.equal?(current)
    raise Error, "The value was already taken" if Primitive.zr_hidden_get(ractor, :__taken__)

    Primitive.zr_hidden_set(ractor, :__taken__, true)
    begin
      Primitive.zr_hidden_get(ractor, :__thread__).value
    rescue Exception # rubocop:disable Lint/RescueException
      error = RemoteError.new("thrown by remote Ractor.")
      Primitive.zr_hidden_set(error, :__ractor__, ractor)
      raise error
    end
  end
  private_class_method :take
end
