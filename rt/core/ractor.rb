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
  class MovedObject < BasicObject; end

  # The classes that hold a task or a lock, which no ractor can share.
  UNSHAREABLE = [Thread, Thread::Mutex, Thread::Queue, Thread::SizedQueue, Thread::ConditionVariable].freeze
  private_constant :UNSHAREABLE

  # Every ractor of this process, and the notice ruby prints once.
  RACTORS = []
  NOTICE = []
  private_constant :RACTORS, :NOTICE

  def self.new(*args, &block)
    raise ArgumentError, "must be called with a block" unless block

    notice
    isolate(block)
    ractor = Primitive.zr_class_build(self)
    ractor.__send__(:setup, args.map { |arg| cross(arg) }, block)
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

  # A frozen block whose self is shareable, which any ractor may call.
  def self.shareable_proc(&block)
    raise ArgumentError, "must be called with a block" unless block

    isolate(block)
    block.freeze
  end

  def self.shareable_lambda(&block)
    raise ArgumentError, "must be called with a block" unless block

    isolate(block)
    lambda(&block).freeze
  end

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

  def self.receive = current.__send__(:take)

  def self.receive_if(&block) = current.__send__(:take_if, block)

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
  # symbol, a class and the three singletons are shareable as they are.
  def self.shareable?(obj)
    return true if immutable?(obj)

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

  def self.immutable?(obj)
    Primitive.attr! :hidden
    case obj
    when Integer, Float, Symbol, Module, NilClass, TrueClass, FalseClass then true
    else false
    end
  end

  def self.deep_freeze(obj, seen)
    Primitive.attr! :hidden
    return if immutable?(obj) || seen.key?(obj.object_id)

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
  # `make_shareable(copy: true)` asks for.
  def self.cross(value, seen = {}, deeply = false)
    Primitive.attr! :hidden
    return value if immutable?(value) || (!deeply && shareable?(value))
    return seen[value.object_id] if seen.key?(value.object_id)

    copy = value.class.allocate
    seen[value.object_id] = copy
    fill(value, copy, seen, deeply)
    value.instance_variables.each do |name|
      copy.instance_variable_set(name, cross(value.instance_variable_get(name), seen, deeply))
    end
    copy.freeze if value.frozen?
    copy
  end
  private_class_method :cross

  # The parts of a copy that are not instance variables: what the class
  # itself holds.
  def self.fill(value, copy, seen, deeply)
    Primitive.attr! :hidden
    case value
    when String then copy.replace(value)
    when Array then value.each { |part| copy << cross(part, seen, deeply) }
    when Hash
      copy.compare_by_identity if value.compare_by_identity?
      value.each { |key, part| copy[cross(key, seen, deeply)] = cross(part, seen, deeply) }
      copy.default = cross(value.default, seen, deeply) unless value.default.nil?
    end
    nil
  end
  private_class_method :fill

  attr_reader :name

  def name=(text)
    @name = text.nil? ? nil : text.to_str.dup.freeze
  end

  def [](key) = local_get(key)

  def []=(key, value)
    local_set(key, value)
  end

  # The message queue, as CRuby's default port holds it: what arrives
  # waits until the ractor takes it, in the order it arrived.
  def send(message, move: false)
    Primitive.zr_unimplemented("Ractor#send with move: true") if move
    raise ClosedError, "The port was already closed" if @closed

    @queue << Ractor.send(:cross, message)
    Thread.send(:rouse, @waiters.dup)
    self
  end

  alias << send

  # What the ractor's block answered, once it ends. A failure inside it
  # arrives here wrapped, with the original as its cause, and the same
  # ractor may be asked again.
  def value
    finished
    Ractor.send(:cross, @value)
  end

  def join
    finished
    self
  end

  def close_incoming = Primitive.zr_unimplemented("Ractor#close_incoming")

  def close_outgoing = Primitive.zr_unimplemented("Ractor#close_outgoing")

  def default_port = Primitive.zr_unimplemented("Ractor#default_port")

  def monitor(_port) = Primitive.zr_unimplemented("Ractor#monitor")

  def unmonitor(_port) = Primitive.zr_unimplemented("Ractor#unmonitor")

  def self.select(*) = Primitive.zr_unimplemented("Ractor.select")

  def inspect
    text = +"#<Ractor:##{@number}"
    text << " " << @name if @name
    text << " " << @site if @site
    "#{text} #{live? ? 'running' : 'terminated'}>"
  end

  alias to_s inspect

  private

  # The main ractor: the task the program starts in, which holds a queue
  # of its own so that a ractor can answer it.
  def setup_main
    Primitive.attr! :hidden
    @queue = []
    @waiters = []
    @locals = {}
    @number = 1
    @name = nil
    @site = nil
    @thread = Thread.main
    self
  end

  def setup(args, block)
    Primitive.attr! :hidden
    @queue = []
    @waiters = []
    @locals = {}
    @name = nil
    @number = RACTORS.size + 2
    RACTORS << self
    @site = caller(3, 1)&.first&.then { |row| row[0, row.index(":in ") || row.size] }
    @thread = Thread.new do
      Thread.current.thread_variable_set(:__ractor__, self)
      instance_exec(*args, &block)
    end
    self
  end

  def live?
    Primitive.attr! :hidden
    @thread.alive?
  end

  # Waits for the ractor to end and keeps what it answered. A failure
  # inside it is ruby's RemoteError here, with the failure as its cause.
  def finished
    Primitive.attr! :hidden
    return @value if @done

    begin
      @value = @thread.value
      @done = true
    rescue Exception => e # rubocop:disable Lint/RescueException
      @done = true
      error = RemoteError.new("thrown by remote Ractor.")
      Primitive.zr_hidden_set(error, :__ractor__, self)
      raise error
    end
    @value
  end

  # The next message, waited for. A ractor that waits for one nobody
  # sends is asleep, and the scheduler sees that.
  def take
    Primitive.attr! :hidden
    while @queue.empty?
      Thread.current.send(:wait_on, @waiters, nil, true)
    end
    @queue.shift
  end

  def take_if(block)
    Primitive.attr! :hidden
    loop do
      found = @queue.index { |message| block.call(message) }
      return @queue.delete_at(found) if found

      Thread.current.send(:wait_on, @waiters, nil, true)
    end
  end

  # A ractor's own storage, which only the ractor itself may read.
  def local_get(key)
    Primitive.attr! :hidden
    mine!
    @locals[key.to_sym]
  end

  def local_set(key, value)
    Primitive.attr! :hidden
    mine!
    @locals[key.to_sym] = value
  end

  def local_absent(key)
    Primitive.attr! :hidden
    mine!
    key = key.to_sym
    @locals.key?(key) ? @locals[key] : (@locals[key] = yield)
  end

  def mine!
    Primitive.attr! :hidden
    return self if equal?(Ractor.current)

    raise RuntimeError, "Cannot get ractor local storage for non-current ractor"
  end
end
