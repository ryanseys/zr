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
