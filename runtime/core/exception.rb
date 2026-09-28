# frozen_string_literal: true

# The exception classes other than the ones the kernel raises itself,
# and the methods that describe an exception.
class Exception
  # An attribute that a caller can leave out. The reader then refuses
  # rather than returning nil.
  UNSET = Object.new
  private_constant :UNSET

  def self.exception(*args) = new(*args)

  # Whether the report an uncaught error prints goes to a terminal.
  def self.to_tty? = Primitive.zr_io_tty_p(2)

  def message = to_s

  def to_s = Primitive.zr_exc_to_s(self)

  # `exception(msg)`: this exception, or a clone with the message `msg`.
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

  # exc_full_message: the report that ruby prints for an uncaught error.
  # All keywords go on to `detailed_message`.
  def full_message(**opt)
    highlight = checked_highlight(opt[:highlight], true)
    bottom = checked_order(opt[:order])
    opt[:highlight] = highlight
    at = caller_locations(1, 1).first
    out = +""
    error_write(out, opt, report_backtrace(self), report_message(self, opt), highlight, bottom, at && "#{at.path}:#{at.lineno}:in 'full_message': ", {}.compare_by_identity)
    out
  end

  # The backtrace entries that the raise saw, as Location objects: nil
  # before a raise, and unchanged when set_backtrace replaces the
  # strings. Locations given to set_backtrace are used for both.
  def backtrace_locations
    return @locations.dup if @locations

    rows = Primitive.zr_exc_raise_rows(self) or return nil

    rows.zip(Primitive.zr_exc_raise_nodes(self)).map { |row, node| Thread::Backtrace::Location.new(row, node) }
  end

  # An Array of Locations sets the locations as well as the strings, as
  # exc_set_backtrace does.
  def set_backtrace(backtrace)
    locations = backtrace.is_a?(Array) && !backtrace.empty? && backtrace.all?(Thread::Backtrace::Location)
    rows = Primitive.zr_exc_set_backtrace_value(self, locations ? backtrace.map(&:to_s) : backtrace)
    @locations = locations ? backtrace.dup : nil
    locations ? backtrace : rows
  end

  private

  BOLD = "\e[1m"
  UNDERLINE = "\e[1;4m"
  RESET = "\e[m"
  private_constant :BOLD, :UNDERLINE, :RESET

  # rb_ec_error_print: the report of an error that ends the program or
  # a thread, as a String. `stop` is an exception already reported,
  # which the cause chain does not repeat.
  def uncaught_report(stop)
    Primitive.attr! :hidden
    highlight = $stderr.equal?(STDERR) && Exception.to_tty?
    opt = { highlight: highlight }
    errat = begin
      report_backtrace(self)
    rescue Exception # rubocop:disable Lint/RescueException
      nil
    end
    emesg = begin
      report_message(self, opt)
    rescue Exception # rubocop:disable Lint/RescueException
      nil
    end
    # error_pos: the main program has finished, so ruby's frame names
    # only the file.
    pos = "#{Primitive.zr_program_name}: " if Thread.current.equal?(Thread.main)
    shown = {}.compare_by_identity
    shown[stop] = true if stop.is_a?(Exception)
    out = +""
    error_write(out, opt, errat, emesg, highlight, false, pos, shown)
    out
  end

  # rb_get_backtrace: the backtrace, from an override when there is one.
  def report_backtrace(exc)
    Primitive.attr! :hidden
    exc.backtrace
  end

  # rb_get_detailed_message: a String, or nil.
  def report_message(exc, opt)
    Primitive.attr! :hidden
    text = exc.detailed_message(**opt)
    text.is_a?(String) ? text : String.try_convert(text)
  end

  # rb_error_write: the head line, the `from` trail, then the chain of
  # causes, each one once. `:bottom` puts a banner first, numbers the
  # trail and turns the whole report around. `pos` heads an exception
  # with no backtrace.
  def error_write(out, opt, errat, emesg, highlight, bottom, pos, shown)
    Primitive.attr! :hidden
    out << (highlight ? "#{BOLD}Traceback#{RESET}" : "Traceback") << " (most recent call last):\n" if bottom
    write_one(out, self, opt, errat, emesg, highlight, bottom, pos, shown)
  end

  def write_one(out, exc, opt, errat, emesg, highlight, bottom, pos, shown)
    Primitive.attr! :hidden
    if bottom
      show_cause(out, exc, opt, highlight, bottom, pos, shown)
      print_backtrace(out, exc, errat, bottom)
      print_errinfo(out, exc, errat, emesg, highlight, pos)
    else
      print_errinfo(out, exc, errat, emesg, highlight, pos)
      print_backtrace(out, exc, errat, bottom)
      show_cause(out, exc, opt, highlight, bottom, pos, shown)
    end
  end

  def show_cause(out, exc, opt, highlight, bottom, pos, shown)
    Primitive.attr! :hidden
    cause = exc.cause
    return unless cause.is_a?(Exception) && !shown.key?(cause)

    shown[cause] = true
    write_one(out, cause, opt, report_backtrace(cause), report_message(cause, opt), highlight, bottom, pos, shown)
  end

  # The head line: the first frame, the message, or the class for an
  # empty one.
  def print_errinfo(out, exc, errat, emesg, highlight, pos)
    Primitive.attr! :hidden
    head = errat&.first
    if head
      out << head << ": "
    elsif pos
      out << pos
    end
    if emesg.nil? || emesg.empty?
      name = Primitive.zr_class_of_is(exc, RuntimeError) ? +"unhandled exception" : exc.class.to_s
      out << (highlight ? "#{UNDERLINE}#{name}#{RESET}" : name) << "\n"
    else
      out << emesg << "\n"
    end
  end

  # The frames under the head. A deep SystemStackError shows its first
  # 9 and last 4 frames.
  def print_backtrace(out, exc, errat, bottom)
    Primitive.attr! :hidden
    return unless errat

    len = errat.size
    width = (len - 1).to_s.size
    skip_start = exc.instance_of?(SystemStackError) && len > 18 ? 9 : -1
    i = 1
    while i < len
      if i == skip_start
        out << "\t ... #{len - 13} levels...\n"
        i += len - 13
        break if i >= len
      end
      line = errat[bottom ? len - i : i]
      out << "\t" << (bottom ? "#{(len - i).to_s.rjust(width)}: " : "") << "from " << line << "\n" if line.is_a?(String)
      i += 1
    end
  end

  # Ruby's `rb_decorate_message`: the class rides on the message's first
  # line, and an empty message is the class alone.
  def decorate(text, highlight)
    Primitive.attr! :hidden
    if Primitive.zr_class_of_is(self, RuntimeError) && text.empty?
      return highlight ? "#{UNDERLINE}unhandled exception#{RESET}" : +"unhandled exception"
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

  # setup_exception under $DEBUG: each raise tells $stderr the class,
  # the place of the raise and the message, rescued or not.
  # `raised` holds the place of the raise as its first frame.
  def debug_report(raised)
    Primitive.attr! :hidden
    text = to_s
    text = Primitive.zr_any_to_s(self) unless text.is_a?(String)
    at = raised.backtrace_locations&.first
    $stderr.write(at ? "Exception '#{self.class}' at #{at.path}:#{at.lineno} - #{text}\n" : "Exception '#{self.class}' - #{text}\n")
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
    return false if value.nil?
    return true if value == :bottom || value == +"bottom"
    return false if value == :top || value == +"top"

    raise ArgumentError, "expected :top or :bottom as order: #{value.inspect}"
  end
end

class NoMemoryError < Exception; end
# Ruby defines these two on Exception itself, so its own reflection
# shows them; each behaves as the method it is in place of.
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
  # in. So two throws have the same message.
  def initialize(tag, value, message = +"uncaught throw %p")
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
    raise ArgumentError, +"no matchee is available" unless Primitive.zr_hidden_get(self, :__given__)

    Primitive.zr_hidden_get(self, :__matchee__)
  end

  def key
    raise ArgumentError, +"no key is available" unless Primitive.zr_hidden_get(self, :__given__)

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
    raise ArgumentError, +"no receiver is available" unless defined?(@receiver)

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
    raise ArgumentError, +"no key is available" unless defined?(@key)

    @key
  end

  def receiver
    raise ArgumentError, +"no receiver is available" unless defined?(@receiver)

    @receiver
  end
end

class FrozenError
  def initialize(message = nil, receiver: UNSET)
    super(message)
    @receiver = receiver unless receiver.equal?(UNSET)
  end

  def receiver
    raise ArgumentError, +"no receiver is available" unless defined?(@receiver)

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

  # A number gives its first signal in Signal.list; a name keeps its own
  # spelling, including an alias.
  def initialize(sig = nil, message = nil)
    raise ArgumentError, +"wrong number of arguments (given 0, expected 1)" if sig.nil? && instance_of?(SignalException)

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
      raise ArgumentError, +"wrong number of arguments (given 2, expected 1)" unless message.nil?

      name = sig.to_s.delete_prefix("SIG")
      raise ArgumentError, "unsupported signal 'SIG#{name}'" unless signals.key?(name)

      Primitive.zr_hidden_set(self, :signo, signals[name])
      super("SIG#{name}")
    end
  end

  def signm = to_s
end

class Interrupt
  def initialize(message = +"Interrupt")
    super(2, message)
  end
end

class Thread
  class Backtrace
    # `--backtrace-limit`, which zr does not take: every row shows.
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
        return nil if @path == +"-e"

        parts = "#{Primitive.zr_getcwd}/#{@path}".split("/").reject { |part| part.empty? || part == +"." }
        "/" + parts.join("/")
      end
      def to_s = @row
      def inspect = @row.inspect
    end
  end
end

module Kernel
  # A Range selects from the locations outward from this method's
  # caller, as `caller_locations(0)[range]`.
  def caller_locations(start = 1, length = nil)
    if Range === start
      all = caller_locations(0).drop(1)
      return all[start]
    end

    rows = caller(start + 1, length) or return nil

    rows.zip(Primitive.zr_caller_nodes(start + 1, length)).map { |row, node| Thread::Backtrace::Location.new(row, node || 0) }
  end
  private :caller_locations
end

# ruby.c defines these before the gem prelude runs, which loads each
# library only where its module is defined.
module ErrorHighlight; end
module DidYouMean; end
module SyntaxSuggest; end
