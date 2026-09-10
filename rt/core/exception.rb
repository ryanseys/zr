# The exception classes past the ones the kernel raises itself, and
# what an exception answers about itself.
class Exception
  # An attribute a caller may leave out, which the reader then refuses
  # rather than answering nil.
  UNSET = Object.new
  private_constant :UNSET

  def self.exception(*args) = new(*args)

  # Whether the report an uncaught error prints goes to a terminal.
  def self.to_tty? = Primitive.zr_io_tty_p(2)

  def message = to_s

  def to_s = Primitive.zr_exc_to_s(self)

  # `exception(msg)`: this exception, or a clone carrying `msg`.
  def exception(*args)
    return self if args.empty? || args[0].equal?(self)

    copy = clone
    Primitive.zr_exc_set_message(copy, args[0])
    copy
  end

  # Ruby compares the message a raise STORED, not the one `to_s`
  # builds, so two uncaught throws of different tags are equal.
  def ==(other)
    return true if equal?(other)

    if other.class == self.class
      mesg = Primitive.zr_exc_raw_message(other)
    else
      return false unless other.respond_to?(:exception)

      other = begin
        other.exception
      rescue StandardError
        return false
      end
      return false unless other.class == self.class

      mesg = other.message
    end
    Primitive.zr_exc_raw_message(self) == mesg && backtrace == other.backtrace
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
# Ruby carries these two on Exception itself, so its own reflection
# names them; each answers as the one it stands over does.
class Exception
  def method_missing(name, *args, &block) = super

  private :method_missing

  def respond_to_missing?(name, include_private) = super
end

class ScriptError < Exception; end
class LoadError < ScriptError
  attr_reader :path
end
class NotImplementedError < ScriptError; end
class SyntaxError < ScriptError
  # The file the error was read from, which only ruby's own parser
  # fills in.
  attr_reader :path

  def initialize(message = "compile error")
    super
  end
end
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

  # The stored message is ruby's own format string; `to_s` puts the tag
  # in. Two throws therefore carry the same message.
  def initialize(tag, value, message = "uncaught throw %p")
    @tag = tag
    @value = value
    super(message)
  end

  def to_s = format(super, tag)
end
class EncodingError < StandardError; end
class FiberError < StandardError; end
class IOError < StandardError; end
class EOFError < IOError; end
class StopIteration < IndexError
  def result = Primitive.zr_hidden_get(self, :result)
end
class ClosedQueueError < StopIteration; end
class NoMatchingPatternError < StandardError; end
class NoMatchingPatternKeyError < NoMatchingPatternError
  def initialize(message = nil, **options)
    super(message)
    Primitive.zr_hidden_set(self, :__matchee__, options[:matchee]) if options.key?(:matchee)
    Primitive.zr_hidden_set(self, :__key__, options[:key]) if options.key?(:key)
    Primitive.zr_hidden_set(self, :__given__, options.key?(:key))
  end

  def matchee
    raise ArgumentError, "no matchee is available" unless Primitive.zr_hidden_get(self, :__given__)

    Primitive.zr_hidden_get(self, :__matchee__)
  end

  def key
    raise ArgumentError, "no key is available" unless Primitive.zr_hidden_get(self, :__given__)

    Primitive.zr_hidden_get(self, :__key__)
  end
end
class RangeError < StandardError; end
class FloatDomainError < RangeError; end

module Math
  class DomainError < StandardError; end
end
class RegexpError < StandardError; end
class SystemCallError < StandardError; end
class ThreadError < StandardError; end

class NameError
  attr_reader :name

  def initialize(message = nil, name = nil, receiver: UNSET)
    super(message)
    @name = name
    @receiver = receiver unless receiver.equal?(UNSET)
  end

  def receiver
    raise ArgumentError, "no receiver is available" unless defined?(@receiver)

    @receiver
  end

  def local_variables = []
end

class NoMethodError
  attr_reader :args

  def initialize(message = nil, name = nil, args = [], private_call = false, receiver: UNSET)
    super(message, name, receiver: receiver)
    @args = args
    @private_call = private_call
  end

  def private_call? = @private_call == true
end

class KeyError
  def initialize(message = nil, receiver: UNSET, key: UNSET)
    super(message)
    @receiver = receiver unless receiver.equal?(UNSET)
    @key = key unless key.equal?(UNSET)
  end

  def key
    raise ArgumentError, "no key is available" unless defined?(@key)

    @key
  end

  def receiver
    raise ArgumentError, "no receiver is available" unless defined?(@receiver)

    @receiver
  end
end

class FrozenError
  def initialize(message = nil, receiver: UNSET)
    super(message)
    @receiver = receiver unless receiver.equal?(UNSET)
  end

  def receiver
    raise ArgumentError, "no receiver is available" unless defined?(@receiver)

    @receiver
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
      # A name says what the message is, so a second argument is one
      # too many.
      raise ArgumentError, "wrong number of arguments (given 2, expected 1)" unless message.nil?

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
    # `--backtrace-limit`, which ze0 does not take: every row shows.
    def self.limit = -1

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
