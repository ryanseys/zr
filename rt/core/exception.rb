# The exception classes past the ones the kernel raises itself, and
# what an exception answers about itself.
class Exception
  def self.exception(*args) = new(*args)

  def message = to_s

  def to_s = Primitive.zr_exc_to_s(self)

  # `exception(msg)`: this exception, or a clone carrying `msg`.
  def exception(*args)
    return self if args.empty? || args[0].equal?(self)

    copy = clone
    Primitive.zr_exc_set_message(copy, args[0])
    copy
  end

  def ==(other)
    other.class == self.class && other.message == message && other.backtrace == backtrace
  end

  def detailed_message(highlight: false, **) = Primitive.zr_exc_detailed_message(self)

  def full_message(highlight: false, order: :top)
    lines = backtrace || []
    head = "#{lines[0] || ''}#{lines[0] ? ': ' : ''}#{detailed_message(highlight: highlight)}\n"
    rest = lines.drop(1).map { |l| "\tfrom #{l}\n" }
    order == :bottom ? (rest.reverse + [head]).join : head + rest.join
  end

  def backtrace_locations = nil
end

class NoMemoryError < Exception; end
class ScriptError < Exception; end
class LoadError < ScriptError
  attr_reader :path
end
class NotImplementedError < ScriptError; end
class SyntaxError < ScriptError; end
class SecurityError < Exception; end
class SignalException < Exception; end
class Interrupt < SignalException; end
class SystemExit < Exception
  attr_reader :status

  def initialize(*args)
    status = true
    status = args.shift if args[0] == true || args[0] == false || args[0].is_a?(Integer)
    @status = status == true ? 0 : status == false ? 1 : status
    super(*args)
  end

  def success? = @status == 0
end

class UncaughtThrowError < ArgumentError
  attr_reader :tag, :value

  def initialize(tag, value, message = "uncaught throw #{tag.inspect}")
    @tag = tag
    @value = value
    super(message)
  end
end
class EncodingError < StandardError; end
class FiberError < StandardError; end
class IOError < StandardError; end
class EOFError < IOError; end
class StopIteration < IndexError
  attr_reader :result
end
class ClosedQueueError < StopIteration; end
class NoMatchingPatternError < StandardError; end
class NoMatchingPatternKeyError < NoMatchingPatternError
  attr_reader :key, :matchee
end
class RangeError < StandardError; end
class FloatDomainError < RangeError; end

module Math
  class DomainError < ArgumentError; end
end
class RegexpError < StandardError; end
class SystemCallError < StandardError; end
class ThreadError < StandardError; end

class NameError
  attr_reader :name, :receiver

  def initialize(message = nil, name = nil, receiver: nil)
    super(message)
    @name = name
    @receiver = receiver
  end

  def local_variables = []
end

class NoMethodError
  attr_reader :args

  def initialize(message = nil, name = nil, args = [], private_call = false, receiver: nil)
    super(message, name, receiver: receiver)
    @args = args
    @private_call = private_call
  end

  def private_call? = @private_call == true
end

class KeyError
  attr_reader :key, :receiver

  def initialize(message = nil, receiver: nil, key: nil)
    super(message)
    @receiver = receiver
    @key = key
  end
end

class FrozenError
  attr_reader :receiver

  def initialize(message = nil, receiver: nil)
    super(message)
    @receiver = receiver
  end
end

class LocalJumpError
  attr_reader :exit_value, :reason
end

class SignalException
  SIGNALS = { "HUP" => 1, "INT" => 2, "QUIT" => 3, "ABRT" => 6, "KILL" => 9, "SEGV" => 11, "PIPE" => 13,
              "ALRM" => 14, "TERM" => 15, "CHLD" => 20, "USR1" => 30, "USR2" => 31 }.freeze
  private_constant :SIGNALS

  attr_reader :signo

  def initialize(sig = nil, message = nil)
    raise ArgumentError, "wrong number of arguments (given 0, expected 1)" if sig.nil? && instance_of?(SignalException)

    if sig.is_a?(Integer)
      name = SIGNALS.key(sig)
      raise ArgumentError, "invalid signal number (#{sig})" unless name

      @signo = sig
      super(message || "SIG#{name}")
    elsif sig.nil?
      @signo = 2
      super(message)
    else
      name = sig.to_s.delete_prefix("SIG")
      raise ArgumentError, "unsupported signal 'SIG#{name}'" unless SIGNALS.key?(name)

      @signo = SIGNALS[name]
      super("SIG#{name}")
    end
  end

  def signm = message
end

class Interrupt
  def initialize(message = "Interrupt")
    super(2, message)
  end
end

class Thread
  class Backtrace
    # One row of `caller_locations`, parsed from its `file:line:in
    # 'label'` form.
    class Location
      attr_reader :path, :lineno, :label

      def initialize(row)
        at = row.index(":in '")
        head = row[0, at]
        colon = head.rindex(":")
        @path = head[0, colon]
        @lineno = head[colon + 1..].to_i
        @label = row[at + 5...-1]
        @row = row
      end

      # The method's own name: no block prefix, no owner.
      def base_label
        at = @label.rindex(" in ")
        name = at ? @label[at + 4..] : @label
        return name if name.start_with?("<")

        cut = [name.rindex("#"), name.rindex(".")].compact.max
        cut ? name[cut + 1..] : name
      end

      def absolute_path
        return @path if @path.start_with?("/")
        return nil if @path == "-e"

        parts = "#{Primitive.zr_getcwd}/#{@path}".split("/").reject { |part| part.empty? || part == "." }
        "/" + parts.join("/")
      end
      def to_s = @row
      def inspect = @row.inspect
    end
  end
end

module Kernel
  def caller_locations(start = 1, length = nil)
    rows = caller(start + 1, length)
    rows&.map { |row| Thread::Backtrace::Location.new(row) }
  end
  private :caller_locations
end
