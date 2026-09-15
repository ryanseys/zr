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

  def detailed_message(highlight: nil, **)
    decorate(message.to_s, checked_highlight(highlight, false))
  end

  # Ruby's `rb_error_write`: the head line, the `from` trail, then the
  # chain this exception came from. `:bottom` puts the banner first,
  # numbers the trail and turns the whole report around.
  def full_message(highlight: nil, order: nil)
    highlight = checked_highlight(highlight, true)
    bottom = checked_order(order)
    out = +""
    out << "#{highlight ? "#{BOLD}Traceback#{RESET}" : 'Traceback'} (most recent call last):\n" if bottom
    rows = backtrace
    rows = [asked_from(caller_locations(1, 1)&.first)] if rows.nil? || rows.empty?
    report(out, self, rows, highlight, bottom, [self])
    out
  end

  # The rows the raise saw, as Location objects: nil before a raise, and
  # unchanged when set_backtrace replaces the strings.
  def backtrace_locations
    rows = Primitive.zr_exc_raise_rows(self) or return nil

    rows.zip(Primitive.zr_exc_raise_nodes(self)).map { |row, node| Thread::Backtrace::Location.new(row, node) }
  end

  private

  BOLD = "\e[1m"
  UNDERLINE = "\e[1;4m"
  RESET = "\e[m"
  private_constant :BOLD, :UNDERLINE, :RESET

  # An exception with no backtrace hangs its head off the position that
  # asked for the report, under this method's name, as CRuby's C frame
  # does.
  def asked_from(row)
    Primitive.attr! :hidden
    row && "#{row.path}:#{row.lineno}:in 'full_message'"
  end

  def report(out, exc, rows, highlight, bottom, shown)
    Primitive.attr! :hidden
    if bottom
      chain(out, exc, highlight, bottom, shown)
      trail(out, rows, true)
      out << errinfo(rows, exc, highlight)
    else
      out << errinfo(rows, exc, highlight)
      trail(out, rows, false)
      chain(out, exc, highlight, bottom, shown)
    end
  end

  def chain(out, exc, highlight, bottom, shown)
    Primitive.attr! :hidden
    cause = exc.cause
    return unless cause.is_a?(Exception) && shown.none? { |seen| seen.equal?(cause) }

    shown << cause
    report(out, cause, cause.backtrace || [], highlight, bottom, shown)
  end

  def errinfo(rows, exc, highlight)
    Primitive.attr! :hidden
    detail = exc.detailed_message(highlight: highlight)
    rows[0] ? "#{rows[0]}: #{detail}\n" : "#{detail}\n"
  end

  # The frames under the head, in reading order, or numbered and
  # reversed under the Traceback banner.
  def trail(out, rows, bottom)
    Primitive.attr! :hidden
    return if rows.length < 2

    width = (rows.length - 1).to_s.length
    if bottom
      (1...rows.length).each do |i|
        out << "\t#{(rows.length - i).to_s.rjust(width)}: from #{rows[rows.length - i]}\n"
      end
    else
      rows.drop(1).each { |row| out << "\tfrom #{row}\n" }
    end
  end

  # Ruby's `rb_decorate_message`: the class rides on the message's first
  # line, and an empty message is the class alone.
  def decorate(text, highlight)
    Primitive.attr! :hidden
    if instance_of?(RuntimeError) && text.empty?
      return highlight ? "#{UNDERLINE}unhandled exception#{RESET}" : "unhandled exception"
    end

    path = self.class.to_s
    return highlight ? "#{UNDERLINE}#{path}#{RESET}" : path if text.empty?
    return highlight ? "#{BOLD}#{text}#{RESET}" : text if path.start_with?("#")

    first, sep, rest = text.partition("\n")
    out = +""
    out << BOLD if highlight
    out << first << " ("
    out << UNDERLINE if highlight
    out << path
    out << "#{RESET}#{BOLD}" if highlight
    out << ")"
    out << RESET if highlight
    return out if sep.empty?

    out << "\n"
    out << BOLD if highlight
    out << rest
    out << RESET if highlight
    out
  end

  def checked_highlight(value, tty)
    Primitive.attr! :hidden
    unless value.nil? || value == true || value == false
      raise ArgumentError, "expected true or false as highlight: #{value.inspect}"
    end
    return value unless value.nil?

    tty && Exception.to_tty?
  end

  def checked_order(value)
    Primitive.attr! :hidden
    return Exception.to_tty? if value.nil?
    return true if value == :bottom || value == "bottom"
    return false if value == :top || value == "top"

    raise ArgumentError, "expected :top or :bottom as order: #{value.inspect}"
  end
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
  # The feature a require could not load, which CRuby keeps where a
  # program sees it.
  def path = Primitive.zr_hidden_get(self, :@path)
end
class NotImplementedError < ScriptError; end
class SyntaxError < ScriptError
  # The file the error was read from, which only ruby's own parser
  # fills in, where a program sees it.
  def path = Primitive.zr_hidden_get(self, :@path)

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

  # The locals of the scope the error was raised in; the lowering's own
  # have no name a program can spell.
  def local_variables = (@local_variables || []).grep(/\A[a-z_][A-Za-z0-9_]*\z/)
end

class NoMethodError
  attr_reader :args

  def initialize(message = nil, name = nil, args = nil, private_call = false, receiver: UNSET)
    super(message, name, receiver: receiver)
    @args = args
    @private_call = private_call ? true : false
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

# CRuby sets these two where a program sees them.
class LocalJumpError
  def exit_value = Primitive.zr_hidden_get(self, :@exit_value)

  def reason = Primitive.zr_hidden_get(self, :@reason)
end

class SignalException
  def signo = Primitive.zr_hidden_get(self, :signo)

  # A number names its first signal in Signal.list; a name keeps its own
  # spelling, an alias among them.
  def initialize(sig = nil, message = nil)
    raise ArgumentError, "wrong number of arguments (given 0, expected 1)" if sig.nil? && instance_of?(SignalException)

    signals = Signal.list
    if sig.is_a?(Integer)
      name = signals.key(sig)
      raise ArgumentError, "invalid signal number (#{sig})" unless name

      Primitive.zr_hidden_set(self, :signo, sig)
      super(message || "SIG#{name}")
    elsif sig.nil?
      Primitive.zr_hidden_set(self, :signo, 2)
      super(message)
    else
      # A name says what the message is, so a second argument is one
      # too many.
      raise ArgumentError, "wrong number of arguments (given 2, expected 1)" unless message.nil?

      name = sig.to_s.delete_prefix("SIG")
      raise ArgumentError, "unsupported signal 'SIG#{name}'" unless signals.key?(name)

      Primitive.zr_hidden_set(self, :signo, signals[name])
      super("SIG#{name}")
    end
  end

  def signm = to_s
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

      # `node_id` is the id of the prism node the row's line ran, which
      # RubyVM::AbstractSyntaxTree.node_id_for_backtrace_location reads.
      def initialize(row, node_id = 0)
        Primitive.zr_hidden_set(self, :__node_id__, node_id)
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
    rows = caller(start + 1, length) or return nil

    rows.zip(Primitive.zr_caller_nodes(start + 1, length)).map { |row, node| Thread::Backtrace::Location.new(row, node || 0) }
  end
  private :caller_locations
end

# ruby.c defines these before the gem prelude runs, which loads each
# library only where its module stands.
module ErrorHighlight; end
module DidYouMean; end
module SyntaxSuggest; end
