# frozen_string_literal: true

# Ractor: a task of its own with a boundary around it. Every value that
# crosses the boundary is shareable or a copy of its whole graph, so two
# ractors never hold the same mutable object. The tasks are green, as
# every task in this runtime is, so a program that measures answers
# instead of parallelism gets ruby's answers.
class Ractor
  class Error < RuntimeError; end
  class IsolationError < Error; end
  class ClosedError < StopIteration; end
  class MovedError < Error; end
  class RemoteError < Error
    # The ractor whose failure this stands for.
    def ractor = Primitive.zr_hidden_get(self, :__ractor__)
  end
  class UnsafeError < Error; end

  # What a moved object becomes. CRuby swaps the class of the graph it
  # gave away, so the sender still holds the cell and every message to it
  # refuses. These are all the methods a husk has.
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
  # made it. Anyone may send to a port; only its owner receives. A port is
  # shareable, so it is frozen, and the queue it holds is state beside the
  # object rather than an instance variable of it.
  class Port
    def initialize
      Primitive.zr_state_set(self, :__queue__, [])
      Primitive.zr_state_set(self, :__waiters__, [])
      Primitive.zr_state_set(self, :__owner__, Thread.current.thread_variable_get(:__ractor__))
      Primitive.zr_state_set(self, :__closed__, false)
      freeze
    end

    # A message for the owner, copied over the boundary, or handed over
    # when the sender gives the graph up.
    def send(obj, move: false)
      raise ClosedError, "The port was already closed" if closed?

      queue << (move ? Ractor.__send__(:hand_over, obj) : Ractor.__send__(:cross, obj))
      Thread.__send__(:rouse, waiters.dup)
      self
    end

    alias << send

    # The next message, waited for. A port with nothing left to give and
    # no sender that can reach it any more is closed, and says so.
    def receive
      mine!
      while queue.empty?
        raise ClosedError, "The port was already closed" if closed?

        Thread.current.__send__(:wait_on, waiters, nil, true)
      end
      queue.shift
    end

    def close
      Primitive.zr_state_set(self, :__closed__, true)
      Thread.__send__(:rouse, waiters.dup)
      nil
    end

    def closed? = Primitive.zr_hidden_get(self, :__closed__)

    def inspect = "#<Ractor::Port to:##{owner.__send__(:number)} id:#{object_id}>"

    private

    def queue
      Primitive.attr! :hidden
      Primitive.zr_hidden_get(self, :__queue__)
    end

    def waiters
      Primitive.attr! :hidden
      Primitive.zr_hidden_get(self, :__waiters__)
    end

    # The ractor that made the port. A port made before the main ractor
    # is named belongs to it.
    def owner
      Primitive.attr! :hidden
      Primitive.zr_hidden_get(self, :__owner__) || Ractor.main
    end

    def mine!
      Primitive.attr! :hidden
      return self if owner.equal?(Ractor.current)

      raise Error, "only allowed from the creator Ractor of this port"
    end

    # Whether a message waits, and the one that does: `Ractor.select`
    # asks its own ports this way, so it never parks on a full one.
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

  # What CRuby refuses to move: a handle on a task, a lock, or code with
  # a scope of its own.
  UNMOVABLE = [*UNSHAREABLE, Proc, Method, UnboundMethod, Binding, Fiber].freeze
  private_constant :UNMOVABLE

  # Every ractor of this process, and the notice ruby prints once.
  RACTORS = []
  NOTICE = []
  private_constant :RACTORS, :NOTICE

  def self.new(*args, name: nil, &block)
    raise ArgumentError, "must be called with a block" unless block

    notice
    isolate(block)
    ractor = Primitive.zr_class_build(self)
    ractor.__send__(:setup, args.map { |arg| cross(arg) }, block, caller(1, 1)&.first)
    ractor.name = name unless name.nil?
    ractor
  end

  # The experimental notice, once for the process however many ractors
  # follow, naming the line that asked for the first one.
  def self.notice
    Primitive.attr! :hidden
    return nil unless NOTICE.empty?

    NOTICE << true
    Warning.experimental("Ractor API is experimental and may change in future versions of Ruby.")
  end
  private_class_method :notice

  # A block a ractor can run reaches nothing outside itself. Ruby decides
  # this when the ractor is made, not when the block is written, and names
  # what the block reaches.
  def self.isolate(block)
    Primitive.attr! :hidden
    outer = Primitive.zr_proc_captures_m(block)
    return block if outer.empty?

    raise ArgumentError, "can not isolate a Proc because it accesses outer variables (#{outer.join(', ')})."
  end
  private_class_method :isolate

  # A copy of the block that any ractor may call: frozen, answering to
  # `self:` (nil unless given), with no Binding to reach its scope by.
  def self.shareable_proc(**options, &block)
    raise ArgumentError, "tried to create Proc object without a block" unless block

    shareable(block, options, lambda: false)
  end

  # The same, and a literal block becomes a lambda.
  def self.shareable_lambda(**options, &block)
    raise ArgumentError, "tried to create Proc object without a block" unless block

    shareable(block, options, lambda: true)
  end

  # Ruby's rules for a shareable block, in ruby's order. Its self has to
  # be shareable. It may not write a local outside itself. And every
  # local it reads there must be bound once in its own scope -- so the
  # value the block copies is the only one the local will ever hold --
  # and hold a shareable value now.
  #
  # Written locals are named in the order ruby names them, by symbol;
  # read ones are checked the other way round, as ruby checks them.
  def self.shareable(block, options, lambda:)
    Primitive.attr! :hidden
    unknown = options.keys - [:self]
    raise ArgumentError, "unknown keyword#{"s" if unknown.size > 1}: #{unknown.map(&:inspect).join(", ")}" unless unknown.empty?

    receiver = options[:self]
    raise IsolationError, "self should be shareable: #{receiver.inspect}" unless shareable?(receiver)

    rows = Primitive.zr_proc_capture_rows_m(block)
    written = rows.filter_map { |name, write, _| name if write }
    raise ArgumentError, "can not make a Proc shareable because it accesses outer variables (#{written.join(", ")})." unless written.empty?

    scope = Primitive.zr_proc_binding(block) unless rows.empty?
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
      ractor = Primitive.zr_class_build(self)
      ractor.__send__(:setup_main)
      ractor
    end
  end

  # The ractor this task belongs to: the main one until a task of a
  # ractor's own says otherwise.
  def self.current = Thread.current.thread_variable_get(:__ractor__) || main

  def self.count = RACTORS.count { |ractor| ractor.__send__(:live?) } + 1

  def self.main? = current.equal?(main)

  # A message from this ractor's own port.
  def self.receive = current.default_port.receive

  # The first message any of the ports holds, or the value of the first
  # ractor to end. A Ractor stands for a port of its own here: it is
  # watched, and the token its end sends is the answer.
  def self.select(*ports)
    raise ArgumentError, "specify at least one Ractor::Port or Ractor" if ports.empty?

    watched = {}
    ports = ports.map do |arg|
      case arg
      when Ractor
        port = Port.new
        watched[port] = arg
        arg.monitor(port)
        port
      when Port then arg
      else raise ArgumentError, "should be Ractor::Port or Ractor"
      end
    end
    begin
      port, message = first_message(ports)
      ractor = watched[port]
      ractor ? [ractor, ractor.value] : [port, message]
    ensure
      watched.each do |own, ractor|
        ractor.unmonitor(own)
        own.close
      end
    end
  end

  # The first message of `ports`, with the port it came from. A closed
  # port with nothing left ends the wait, as CRuby's does.
  def self.first_message(ports)
    Primitive.attr! :hidden
    loop do
      ports.each do |port|
        return [port, port.__send__(:take_now)] if port.__send__(:waiting?)
        raise ClosedError, "The port was already closed" if port.closed?
      end
      parked(ports)
    end
  end
  private_class_method :first_message

  # Sleeps until a send to any of the ports wakes this task. Nothing else
  # runs between the test above and the park, so no message is missed.
  def self.parked(ports)
    Primitive.attr! :hidden
    me = Thread.current
    ports.each { |port| port.__send__(:waiters) << me }
    begin
      me.__send__(:wait, nil, true)
    ensure
      ports.each { |port| port.__send__(:waiters).delete(me) }
    end
  end
  private_class_method :parked

  def self.[](key) = current.__send__(:local_get, key)

  def self.[]=(key, value)
    current.__send__(:local_set, key, value)
  end

  def self.store_if_absent(key)
    current.__send__(:local_absent, key) { yield }
  end

  def self.make_shareable(obj, copy: false)
    return make_shareable(cross(obj, {}, true)) if copy

    deep_freeze(obj, {})
    obj
  end

  # Whether every object reachable from `obj` is frozen. A number, a
  # symbol, a class and the three singletons are shareable as they are,
  # and so is a Ractor: what it holds is the runtime's own. A husk left
  # by a move answers no message, and is shareable for that reason.
  def self.shareable?(obj)
    return true if moved?(obj) || immutable?(obj) || obj.is_a?(Ractor)

    obj.frozen? && reachable(obj).all? { |ref| shareable?(ref) }
  end

  # The value a shareable constant takes, when the compiler cannot see
  # that the value is a literal. Ruby demands a value that is already
  # shareable there.
  def self.ensure_shareable(value, name)
    Primitive.attr! :hidden
    raise IsolationError, "cannot assign unshareable object to #{name}" unless shareable?(value)

    value
  end

  # The refusal an instance variable of a shareable object gets outside
  # the main ractor. The runtime asks for it, because the words live here.
  def self.isolation!
    Primitive.attr! :hidden
    raise IsolationError, "can not access instance variables of shareable objects from non-main Ractors"
  end

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
    when Integer, Float, Symbol, Module, NilClass, TrueClass, FalseClass then true
    else false
    end
  end

  def self.deep_freeze(obj, seen)
    Primitive.attr! :hidden
    return if immutable?(obj) || moved?(obj) || obj.is_a?(Ractor) || seen.key?(obj.object_id)

    raise Error, "can not make shareable object for #{obj.inspect}" if UNSHAREABLE.any? { |k| obj.is_a?(k) }

    seen[obj.object_id] = true
    obj.freeze
    reachable(obj).each { |ref| deep_freeze(ref, seen) }
  end

  # What one object refers to: its parts, then its instance variables.
  def self.reachable(obj)
    Primitive.attr! :hidden
    parts =
      case obj
      when Array then obj
      when Hash then obj.flat_map { |key, value| [key, value] } << obj.default
      when Range then [obj.begin, obj.end]
      when Struct then obj.to_a
      else []
      end
    parts + obj.instance_variables.map { |name| obj.instance_variable_get(name) }
  end

  # A value crossing the boundary: a shareable one by reference, anything
  # else as a copy of its whole graph. An object that appears twice in the
  # graph is copied once, so a cycle comes out a cycle, as CRuby's own
  # copy does. `deeply` copies a shareable value as well, which
  # `make_shareable(copy: true)` asks for, and `given` collects the nodes
  # a move then takes away from the sender.
  def self.cross(value, seen = {}, deeply = false, given = nil)
    Primitive.attr! :hidden
    return value if immutable?(value) || (!deeply && shareable?(value))
    return seen[value.object_id] if seen.key?(value.object_id)

    copy = value.class.allocate
    seen[value.object_id] = copy
    given << value if given
    fill(value, copy, seen, deeply, given)
    value.instance_variables.each do |name|
      copy.instance_variable_set(name, cross(value.instance_variable_get(name), seen, deeply, given))
    end
    copy.freeze if value.frozen?
    copy
  end
  private_class_method :cross

  # The parts of a copy that are not instance variables: what the class
  # itself holds.
  def self.fill(value, copy, seen, deeply, given = nil)
    Primitive.attr! :hidden
    case value
    when String then copy.replace(value)
    when Array then value.each { |part| copy << cross(part, seen, deeply, given) }
    when Hash
      copy.compare_by_identity if value.compare_by_identity?
      value.each { |key, part| copy[cross(key, seen, deeply, given)] = cross(part, seen, deeply, given) }
      copy.default = cross(value.default, seen, deeply, given) unless value.default.nil?
    end
    nil
  end
  private_class_method :fill

  # A value the sender gives up: the receiver holds the graph, and every
  # node of it the sender still points at becomes a husk. A graph with
  # something unmovable in it refuses before anything moves, so the
  # sender keeps what it had.
  def self.hand_over(value)
    Primitive.attr! :hidden
    unmovable!(value, {})
    given = []
    copy = cross(value, {}, false, given)
    given.each { |node| Primitive.zr_moved_m(node, MovedObject) }
    copy
  end
  private_class_method :hand_over

  def self.unmovable!(value, seen)
    Primitive.attr! :hidden
    return if immutable?(value) || shareable?(value) || seen.key?(value.object_id)

    raise Error, "can not move #{value.class} object." if UNMOVABLE.any? { |k| value.is_a?(k) }

    seen[value.object_id] = true
    reachable(value).each { |ref| unmovable!(ref, seen) }
  end
  private_class_method :unmovable!

  def name = Primitive.zr_hidden_get(self, :__name__)

  def name=(text)
    Primitive.zr_hidden_set(self, :__name__, text.nil? ? nil : text.to_str.dup.freeze)
  end

  def [](key) = local_get(key)

  def []=(key, value)
    local_set(key, value)
  end

  # The port every message to the ractor goes through, which the ractor
  # itself receives from.
  def default_port = Primitive.zr_hidden_get(self, :__port__)

  # A message for the ractor: its default port holds it until the ractor
  # takes it, in the order it arrived.
  def send(message, move: false)
    default_port.send(message, move: move)
    self
  end

  alias << send

  # What the ractor's block answered, once it ends. A failure inside it
  # arrives here wrapped, with the original as its cause, and the same
  # ractor may be asked again, which answers the same object.
  def value = finished

  def join
    finished
    self
  end

  # A token on `port` when the ractor ends: `:exited` when its block
  # answered, `:aborted` when something was raised out of it. A ractor
  # that has ended already sends the token at once and says false.
  def monitor(port)
    unless live?
      port.send(token)
      return false
    end
    monitors << port
    true
  end

  def unmonitor(port)
    monitors.delete(port)
    self
  end

  def close_incoming = Primitive.zr_unimplemented("Ractor#close_incoming")

  def close_outgoing = Primitive.zr_unimplemented("Ractor#close_outgoing")

  def inspect
    text = +"#<Ractor:##{number}"
    text << " " << name if name
    text << " " << site if site
    "#{text} #{live? ? 'running' : 'terminated'}>"
  end

  alias to_s inspect

  private

  # The ractor's own state. CRuby keeps it in C fields, so a program sees
  # no instance variable on a Ractor at all: these names carry no `@`,
  # which keeps them out of every list and out of Marshal. An `@name` a
  # program writes inside a ractor is then the program's own, and the
  # runtime refuses it where CRuby does.
  def locals
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(self, :__locals__)
  end

  def monitors
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(self, :__monitors__)
  end

  def number
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(self, :__number__)
  end

  def site
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(self, :__site__)
  end

  def thread
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(self, :__thread__)
  end

  def token
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(self, :__token__) || :exited
  end

  # The main ractor: the task the program starts in, which holds a port
  # of its own so that a ractor can answer it.
  def setup_main
    Primitive.attr! :hidden
    Primitive.zr_hidden_set(self, :__locals__, {})
    Primitive.zr_hidden_set(self, :__monitors__, [])
    Primitive.zr_hidden_set(self, :__number__, 1)
    Primitive.zr_hidden_set(self, :__thread__, Thread.main)
    own_port
    self
  end

  def setup(args, block, where)
    Primitive.attr! :hidden
    Primitive.zr_hidden_set(self, :__locals__, {})
    Primitive.zr_hidden_set(self, :__monitors__, [])
    Primitive.zr_hidden_set(self, :__number__, RACTORS.size + 2)
    RACTORS << self
    Primitive.zr_hidden_set(self, :__site__, where && where[0, where.index(":in ") || where.size])
    own_port
    # The block answers to the ractor, as ruby's isolated block does. Its
    # own copy is rebound, so a block the program still holds keeps the
    # self it was written with.
    body = Primitive.zr_proc_rebind_m(block.dup, self)
    task = Thread.new do
      Primitive.zr_ractor_enter_m
      Thread.current.thread_variable_set(:__ractor__, self)
      begin
        answer = body.call(*args)
        Primitive.zr_hidden_set(self, :__token__, :exited)
        answer
      rescue Exception # rubocop:disable Lint/RescueException
        Primitive.zr_hidden_set(self, :__token__, :aborted)
        raise
      ensure
        ended
      end
    end
    # The task is the ractor's, not a thread the program asked for, so it
    # names no line of its own where a report shows it.
    task.instance_variable_set(:@site, nil)
    Primitive.zr_hidden_set(self, :__thread__, task)
    self
  end

  # The port the ractor receives on, which belongs to the ractor however
  # made it.
  def own_port
    Primitive.attr! :hidden
    port = Port.new
    Primitive.zr_state_set(port, :__owner__, self)
    Primitive.zr_hidden_set(self, :__port__, port)
  end

  # The end of the ractor's task: nothing reaches it any more, so its
  # port closes, and everything watching it gets its token.
  def ended
    Primitive.attr! :hidden
    monitors.each { |port| port.send(token) unless port.closed? }
    monitors.clear
    default_port.close
  end

  def live?
    Primitive.attr! :hidden
    thread.alive?
  end

  # Waits for the ractor to end and keeps what it answered, copied over
  # the boundary once, so every ask answers the same object. A failure
  # inside it is ruby's RemoteError here, with the failure as its cause.
  def finished
    Primitive.attr! :hidden
    return Primitive.zr_hidden_get(self, :__value__) if Primitive.zr_hidden_get(self, :__done__)

    begin
      answer = Ractor.__send__(:cross, thread.value)
      Primitive.zr_hidden_set(self, :__value__, answer)
      Primitive.zr_hidden_set(self, :__done__, true)
    rescue Exception # rubocop:disable Lint/RescueException
      Primitive.zr_hidden_set(self, :__done__, true)
      error = RemoteError.new("thrown by remote Ractor.")
      Primitive.zr_hidden_set(error, :__ractor__, self)
      raise error
    end
    Primitive.zr_hidden_get(self, :__value__)
  end

  # A ractor's own storage, which only the ractor itself may read.
  def local_get(key)
    Primitive.attr! :hidden
    mine!
    locals[key.to_sym]
  end

  def local_set(key, value)
    Primitive.attr! :hidden
    mine!
    locals[key.to_sym] = value
  end

  def local_absent(key)
    Primitive.attr! :hidden
    mine!
    key = key.to_sym
    locals.key?(key) ? locals[key] : (locals[key] = yield)
  end

  def mine!
    Primitive.attr! :hidden
    return self if equal?(Ractor.current)

    raise RuntimeError, "Cannot get ractor local storage for non-current ractor"
  end
end
