# frozen_string_literal: true

# The exception classes other than the ones the kernel raises itself,
# and the methods that describe an exception.
class Exception
  # An attribute that a caller can leave out. The reader then refuses
  # rather than returning nil.
  UNSET = Object.new
  private_constant :UNSET

  # Not the core's own `new`: an `initialize` that the program wrote for a
  # core exception class runs, as ruby's rb_class_new_instance finds it.
  def self.exception(*args) = Primitive.zr_class_new_program(self, args)

  # Whether the report an uncaught error prints goes to a terminal.
  def self.to_tty? = Primitive.zr_io_tty_p(2)

  # rb_exception_setup: the exception of `raise(*args, **opts)`, with its
  # cause resolved now (Thread#raise and Fiber#raise). `cause:` is the
  # cause; any other keyword goes to `exception` in one Hash.
  def self.setup(args, opts)
    Primitive.attr! :hidden
    given = opts.key?(:cause)
    rest = given ? opts.except(:cause) : opts
    args += [rest] unless rest.empty?
    Primitive.zr_exception_setup_m(args, opts[:cause], given)
  end
  private_class_method :setup

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

  def detailed_message(highlight: UNSET, **opt)
    # error.c's lazy_load_decoration_gems: the first call loads the
    # libraries that decorate a message, then dispatches again to reach
    # their decorators. A decorator that called this through super
    # decorates the result itself.
    unless Primitive.zr_hidden_get(Exception, :__decorated__)
      basic = Kernel.instance_method(:method).bind_call(self, :detailed_message).owner.equal?(Exception)
      if Exception.send(:load_decorations) && basic
        opt[:highlight] = highlight unless UNSET.equal?(highlight)
        return detailed_message(**opt)
      end
    end

    decorate(message.to_s, checked_highlight(UNSET.equal?(highlight) ? nil : highlight, false))
  end

  # error.c's require_decoration_gems, once per process: loads each of
  # error_highlight, did_you_mean and syntax_suggest that is still an
  # autoload (`--disable` removes one). A library that fails to load
  # leaves the message as it is, and $! does not change. Returns false
  # when an earlier call loaded them.
  def self.load_decorations
    Primitive.attr! :hidden
    return false if Primitive.zr_hidden_get(Exception, :__decorated__)

    Primitive.zr_hidden_set(Exception, :__decorated__, true)
    %i[ErrorHighlight DidYouMean SyntaxSuggest].each do |name|
      Object.const_get(name) if Object.autoload?(name)
    rescue Exception
      nil
    end
    true
  end
  private_class_method :load_decorations

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
  # strings. Locations given to set_backtrace are used for both. Each
  # call returns the same Array, as ruby keeps the one it made.
  def backtrace_locations
    kept = Primitive.zr_hidden_get(self, :__locations__)
    return kept if kept

    rows = Primitive.zr_exc_raise_rows(self) or return nil

    # The Array made for these rows, until a raise records new ones.
    made = Primitive.zr_hidden_get(self, :__made_locations__)
    return made[1] if made && made[0] == rows

    # Pairs of [node, line], one per row.
    places = Primitive.zr_exc_raise_places(self)
    locations = Array.new(rows.size) { |i| Thread::Backtrace::Location.send(:made, rows[i], places[i * 2], places[(i * 2) + 1]) }
    Primitive.zr_hidden_set(self, :__made_locations__, [rows, locations])
    locations
  end

  # An Array of Locations sets the locations as well as the strings, as
  # exc_set_backtrace does.
  def set_backtrace(backtrace) = assign_backtrace(backtrace)

  # rb_exc_set_backtrace: Strings, or Locations, which the exception
  # keeps for backtrace_locations. `raise`'s third argument comes here
  # too, and not through a set_backtrace that the program wrote.
  def assign_backtrace(backtrace)
    Primitive.attr! :hidden
    locations = backtrace.is_a?(Array) && !backtrace.empty? && backtrace.all?(Thread::Backtrace::Location)
    rows = Primitive.zr_exc_set_backtrace_value(self, locations ? backtrace.map(&:to_s) : backtrace)
    Primitive.zr_hidden_set(self, :__locations__, locations ? backtrace.dup : nil)
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
    rescue Exception
      nil
    end
    emesg = begin
      report_message(self, opt)
    rescue Exception
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

  # `$@`: the backtrace of `$!`, nil without one, checked as
  # errat_getter checks it.
  def self.errat(exc)
    Primitive.attr! :hidden
    exc&.send(:report_backtrace, exc)
  end
  private_class_method :errat

  # rb_get_backtrace: the backtrace, from an override when there is one,
  # which must give what rb_check_backtrace takes.
  def report_backtrace(exc)
    Primitive.attr! :hidden
    bt = exc.backtrace
    return bt if bt.nil? || (bt.is_a?(Array) && (bt.all?(String) || bt.all?(Thread::Backtrace::Location)))

    raise TypeError, "backtrace must be an Array of String or an Array of Thread::Backtrace::Location"
  end

  # rb_get_detailed_message: a String, or nil.
  def report_message(exc, opt)
    Primitive.attr! :hidden
    # rb_get_detailed_message: rb_check_funcall, so no method means no
    # message, and the report shows the class name alone.
    return nil unless exc.respond_to?(:detailed_message, true)

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
      # No message at all (no detailed_message) shows the class; an
      # empty one from a RuntimeError says so.
      name = !emesg.nil? && Primitive.zr_class_of_is(exc, RuntimeError) ? +"unhandled exception" : exc.class.to_s
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
    limit = Thread::Backtrace.limit
    skip_start, skip = limit >= 0 && len > limit + 2 ? [limit + 1, len - limit - 1] : [-1, 0]
    skip_start, skip = [9, len - 13] if exc.instance_of?(SystemStackError) && len > 18
    i = 1
    while i < len
      if i == skip_start
        out << "\t ... #{skip} levels...\n"
        i += skip
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
    return out if sep.empty? || rest.empty?

    # Each later line is bold on its own, as rb_decorate_message writes it.
    out << "\n" << (highlight ? rest.gsub(/^(.+)$/) { "#{BOLD}#{::Regexp.last_match(1)}#{RESET}" } : rest)
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

  # The parts that CRuby keeps as hidden ivars of an exception, which
  # Marshal writes after the message and the backtrace under CRuby's
  # names, and gives back to the loaded exception.
  def marshal_parts
    Primitive.attr! :hidden
    []
  end

  def marshal_part_set(_name, _value)
    Primitive.attr! :hidden
    nil
  end

  private :marshal_parts, :marshal_part_set
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
    self
  end

  def matchee
    raise ArgumentError, +"no matchee is available" unless Primitive.zr_hidden_get(self, :__given__)

    Primitive.zr_hidden_get(self, :__matchee__)
  end

  def key
    raise ArgumentError, +"no key is available" unless Primitive.zr_hidden_get(self, :__given__)

    Primitive.zr_hidden_get(self, :__key__)
  end

  private

  def marshal_parts
    Primitive.attr! :hidden
    return [] unless Primitive.zr_hidden_get(self, :__given__)

    [[:matchee, Primitive.zr_hidden_get(self, :__matchee__)], [:key, Primitive.zr_hidden_get(self, :__key__)]]
  end

  def marshal_part_set(name, value)
    Primitive.attr! :hidden
    case name
    when :matchee then Primitive.zr_hidden_set(self, :__matchee__, value)
    when :key
      Primitive.zr_hidden_set(self, :__given__, true)
      Primitive.zr_hidden_set(self, :__key__, value)
    end
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
    self
  end

  def receiver
    raise ArgumentError, +"no receiver is available" unless defined?(@receiver)

    @receiver
  end

  # The locals of the scope the error was raised in; the lowering's own
  # have no name a program can spell.
  def local_variables = (@local_variables || []).select { |name| name.match?(/\A[a-z_][A-Za-z0-9_]*\z/) }

  private

  def marshal_parts
    Primitive.attr! :hidden
    [[:name, @name]]
  end

  def marshal_part_set(name, value)
    Primitive.attr! :hidden
    @name = value if name == :name
  end
end

class NoMethodError
  attr_reader :args

  def initialize(message = nil, name = nil, args = nil, private_call = false, receiver: UNSET)
    super(message, name, receiver: receiver)
    @args = args
    @private_call = private_call ? true : false
    self
  end

  def private_call? = @private_call == true

  private

  def marshal_parts
    Primitive.attr! :hidden
    [[:name, @name], [:args, @args], [:private_call?, @private_call]]
  end

  def marshal_part_set(name, value)
    Primitive.attr! :hidden
    case name
    when :name then @name = value
    when :args then @args = value
    when :private_call? then @private_call = value
    end
  end
end

class KeyError
  def initialize(message = nil, receiver: UNSET, key: UNSET)
    super(message)
    @receiver = receiver unless receiver.equal?(UNSET)
    @key = key unless key.equal?(UNSET)
    self
  end

  def key
    raise ArgumentError, +"no key is available" unless defined?(@key)

    @key
  end

  def receiver
    raise ArgumentError, +"no receiver is available" unless defined?(@receiver)

    @receiver
  end

  private

  def marshal_parts
    Primitive.attr! :hidden
    parts = []
    parts << [:receiver, @receiver] if defined?(@receiver)
    parts << [:key, @key] if defined?(@key)
    parts
  end

  def marshal_part_set(name, value)
    Primitive.attr! :hidden
    case name
    when :receiver then @receiver = value
    when :key then @key = value
    end
  end
end

class FrozenError
  def initialize(message = nil, receiver: UNSET)
    super(message)
    @receiver = receiver unless receiver.equal?(UNSET)
    self
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

  # error_handle: a `return` that leaves an END block or an at_exit
  # handler is no exception in ruby (TAG_RETURN), and ruby reports it as
  # the file and "unexpected return". Any other jump is nil.
  def exit_report
    Primitive.attr! :hidden
    return unless reason == :return

    "#{backtrace_locations&.first&.path}: unexpected return\n"
  end
end

class SignalException
  def signo = Primitive.zr_hidden_get(self, :signo)

  # A number gives its first signal in Signal.list; a name keeps its own
  # spelling, including an alias.
  def initialize(sig = (none = true; nil), message = (bare = true; nil), *rest)
    raise ArgumentError, +"wrong number of arguments (given 0, expected 1)" if none && instance_of?(SignalException)
    # esignal_init: a number takes a message too, a name does not.
    raise ArgumentError, "wrong number of arguments (given #{2 + rest.size}, expected #{Integer.try_convert(sig) ? "1..2" : "1"})" unless rest.empty?

    number = Integer.try_convert(sig) unless none
    if number
      # The number is a C int (NUM2INT); one up to NSIG names its signal,
      # or SIG and the number. A message given as nil gives the class's
      # name.
      number = IO.send(:c_int, number)
      raise ArgumentError, "invalid signal number (#{number})" unless number.between?(0, Primitive.zr_signal_limit)

      Primitive.zr_hidden_set(self, :signo, number)
      super(bare ? "SIG#{Signal.list.key(number) || number}" : message)
    elsif none
      Primitive.zr_hidden_set(self, :signo, 2)
      super(message)
    else
      # A name says what the message is, so a second argument is one
      # too many.
      raise ArgumentError, +"wrong number of arguments (given 2, expected 1)" unless message.nil?

      # signm2signo checks the name: no minus, no null byte, a known
      # signal other than EXIT.
      signo = Signal.send(:number, sig)
      Primitive.zr_hidden_set(self, :signo, signo)
      super("SIG#{(sig.is_a?(Symbol) ? sig.name : String.try_convert(sig)).delete_prefix("SIG")}")
    end
  end

  def signm = to_s

  # Marshal writes the number next to the message and the backtrace.
  def marshal_parts
    Primitive.attr! :hidden
    [[:signo, signo]]
  end

  def marshal_part_set(name, value)
    Primitive.attr! :hidden
    Primitive.zr_hidden_set(self, :signo, value) if name == :signo
  end
  private :marshal_parts, :marshal_part_set
end

class Interrupt
  # interrupt_init: SIGINT, and the message, nil when none is given, so
  # the class's name is the message.
  def initialize(message = nil)
    super(2, message)
  end
end

class Thread
  # The location of each frame that the kernel gives a debugger
  # (zr_debug_frames_from), as rb_debug_inspector_backtrace_locations
  # gives them: a C frame has no path and no line. In a TracePoint's
  # hook, the frame of the core method that CRuby writes in Ruby and whose
  # event the hook handles (Kernel#class) is Ruby code at its place in
  # CRuby's builtin sources (TracePoint.fire): its row takes the binding
  # that the event gives, and the place and name of its code.
  def self.frame_locations(frames)
    Primitive.attr! :hidden
    event = TracePoint.send(:current_row)
    frames.map do |frame|
      row, node, receiver, _binding, meta, _klass, entry = frame
      unless event && event[8].is_a?(Array) && entry.nonzero? && entry == event[10]
        next Backtrace::Location.send(:made, row, node, meta.zero? ? false : nil)
      end

      path, line = event[8]
      frame[3] = Primitive.zr_trace_builtin_binding(entry, receiver)
      Primitive.zr_hidden_set(frame[3], :__source__, event[8])
      frame << [path, line, event[4].to_s]
      Backtrace::Location.send(:made, "#{path}:#{line}#{row[row.index(":in '")..]}", 0, line)
    end
  end

  # rb_debug_inspector_frame_iseq_get: the code of a frame, by its row: at
  # the place that frame_locations gave it, or of its FrameMeta, or nil
  # for a C frame, which has none.
  def self.frame_iseq(frame)
    Primitive.attr! :hidden
    if (place = frame[7])
      path, line, label = place
      return RubyVM::InstructionSequence.send(:made, nil, nil, label, label, path, line)
    end
    RubyVM::InstructionSequence.send(:of_frame, frame[4]) unless frame[4].zero?
  end
  private_class_method :frame_locations, :frame_iseq

  class Backtrace
    # `--backtrace-limit`, or -1 when no limit was given.
    def self.limit = Primitive.zr_backtrace_limit_m

    # One row of `caller_locations`, parsed from its `file:line:in
    # 'label'` form.
    class Location
      attr_reader :path, :lineno, :label

      # rb_undef_alloc_func, and no `new`: only the core makes a Location,
      # through `made`, so clone and dup raise TypeError.
      Primitive.zr_undef_alloc(self)
      class << self
        undef_method :new
      end

      def self.made(row, node_id = 0, line = nil)
        Primitive.attr! :hidden
        location = Primitive.zr_class_build(self)
        location.send(:initialize, row, node_id, line)
        location
      end
      private_class_method :made

      # The locations of `fiber`'s frames, which runs on a stack of its
      # own, as Thread#backtrace_locations takes them for another thread;
      # nil when it has no stack.
      def self.of_fiber(fiber, start, limit)
        Primitive.attr! :hidden
        rows = Primitive.zr_fiber_backtrace_m(fiber, start, limit) or return nil
        places = Primitive.zr_fiber_places_m(fiber, start, limit) || []
        Array.new(rows.size) { |i| made(rows[i], places[i * 2] || 0, places[(i * 2) + 1]) }
      end
      private_class_method :of_fiber

      # `node_id` is the id of the prism node the row's line ran, which
      # RubyVM::AbstractSyntaxTree.node_id_for_backtrace_location reads,
      # negative in code that an eval compiled, with the number of its
      # kept spots in the bits from 32 up (zr_frame_place_id).
      # `line` is the frame's line when the kernel knows it: a row at line
      # 0 shows none, so its whole head is the path, digits and all. It is
      # false for a C frame with no Ruby frame under it, which has no path
      # and shows the program's name.
      def initialize(row, node_id = 0, line = nil)
        Primitive.attr! :hidden
        place = node_id&.abs
        Primitive.zr_hidden_set(self, :__node_id__, place && (place & 0xffffffff))
        Primitive.zr_hidden_set(self, :__script__, place >> 32) if node_id&.negative?
        at = row.index(":in '")
        head = row[0, at]
        # A frame at line 0 shows no line, as location_format writes it.
        shown = head[/:(-?\d+)\z/, 1] unless line == 0 || line == false
        @path = if line == false then nil
                elsif shown then head.byteslice(0, head.bytesize - shown.bytesize - 1)
                else head
                end
        @lineno = shown.to_i
        @label = row[(at + 5)...-1]
        @row = row
      end

      # The method's own name: no block prefix, no owner.
      def base_label
        at = @label.rindex(" in ")
        name = at ? @label[(at + 4)..] : @label
        return name if name.start_with?("<")

        cut = [name.rindex("#"), name.rindex(".")].compact.max
        cut ? name[(cut + 1)..] : name
      end

      # The real path of the frame's file, as ruby fixed it when the file
      # loaded; nil for -e and for an eval's own file name.
      def absolute_path
        return nil if @path.nil? || @path == +"-e"

        Kernel.send(:real_path_of, @path)
      end

      def to_s = @row

      # The range of the node that the frame runs, which the compiler
      # recorded for each node where a frame can stand (Hir::Spots). CRuby
      # reads the file again, checks that its code is the code it compiled,
      # and parses it to find the node. It reads code that an eval compiled
      # again only when RubyVM.keep_script_lines kept its lines, and zr then
      # keeps the eval's spots (Zr::Eval#kept_script).
      def source_range
        script = Primitive.zr_hidden_get(self, :__script__)
        raise ArgumentError, +"cannot get source range for location in eval" if script&.zero?
        raise RuntimeError, +"cannot get source range for location without Ruby bytecode" if @path.nil?

        id = Primitive.zr_hidden_get(self, :__node_id__)
        raise RuntimeError, +"cannot get source range for location without a node ID" if id.nil? || id.zero?

        rows = script ? Location.send(:rows, ::Zr::Eval.current.script_spots(script).split("\n")) : Location.send(:checked_ranges, @path, absolute_path)
        range = rows&.[](id) or raise RuntimeError, "cannot find node ID #{id & 0x3fffffff} in parsed source"
        Ruby::SourceRange.send(:of, [@path, script.nil?, *range])
      end

      # The node that the frame runs, from a parse of its file again
      # (Thread::Backtrace::Location#syntax_tree). Nil where the frame
      # runs no Ruby file, or the file changed since the compile.
      def syntax_tree
        return nil if @path.nil? || !Primitive.zr_hidden_get(self, :__script__).nil?

        id = Primitive.zr_hidden_get(self, :__node_id__)
        return nil if id.nil? || id.zero?

        tree = RubyVM::InstructionSequence.send(:parse_again, @path, absolute_path) or return nil
        queue = [tree]
        while (node = queue.shift)
          return node if node.node_id == id
          # A frame at the entry of a body stands at its first statement.
          return Location.send(:first_statement, node) if (node.node_id | 0x40000000) == id

          queue.concat(node.compact_child_nodes)
        end
        nil
      end

      # The node where a frame stands at the entry of a def, block or
      # lambda: the first instruction's node of its first statement, as
      # Hir::Spots.first_run finds it.
      def self.first_statement(node)
        Primitive.attr! :hidden
        body = node.body
        body = body.statements if body.is_a?(::Ruby::Prism::BeginNode)
        return nil unless body.is_a?(::Ruby::Prism::StatementsNode)

        first = body.body.first
        writes = [::Ruby::Prism::LocalVariableWriteNode, ::Ruby::Prism::InstanceVariableWriteNode, ::Ruby::Prism::GlobalVariableWriteNode,
                  ::Ruby::Prism::ClassVariableWriteNode, ::Ruby::Prism::ConstantWriteNode]
        first = first.value while writes.any? { first.is_a?(_1) } && first.value
        first = first.receiver while first.is_a?(::Ruby::Prism::CallNode) && first.receiver
        first
      end
      private_class_method :first_statement

      # `[crc, length]`: the digest of the code of the file at `path` that
      # the program compiled (Hir::Spots.digest), or nil.
      def self.digest_of(path)
        Primitive.attr! :hidden
        @digests ||= Primitive.zr_load_names(4).split("\f").to_h { |text| [text[/\A[^\n]*/], digest(text.split("\n"))] }
        return @digests[path] if @digests.key?(path)

        spots = defined?(::Zr::Eval) && ::Zr::Eval.current.file_spots(path)
        spots ? digest(spots.split("\n")) : nil
      end

      def self.digest(lines)
        Primitive.attr! :hidden
        _, _, _, crc, length = lines.find { |line| line.start_with?("0 h ") }&.split
        crc && [crc.to_i, length.to_i]
      end
      private_class_method :digest_of, :digest

      # The ranges of the file at `path`, after a read of the file at
      # `absolute` again, as location_source_range_m reads it: an error of
      # the read propagates, and the file must still have the code that was
      # compiled. Code with no real path is an eval's, except -e's.
      def self.checked_ranges(path, absolute)
        Primitive.attr! :hidden
        if absolute.nil?
          raise ArgumentError, +"cannot get source range for location in eval" unless path == "-e"

          return ranges_of(path)
        end
        source = File.binread(absolute)
        digest = digest_of(path)
        raise RuntimeError, +"source has been modified" unless digest && same_code?(source, *digest)

        ranges_of(path)
      end

      # Whether `source` is the code whose CRC-32 is `crc` and whose length
      # is `length`, with no more than a data section after an `__END__`
      # line, as location_source_hash_matches checks it.
      def self.same_code?(source, crc, length)
        Primitive.attr! :hidden
        return false if source.bytesize < length

        code = source.byteslice(0, length)
        return false unless Primitive.zr_zlib_checksum(0, 0, code) == crc
        return true if source.bytesize == length

        last = code.byteslice((code.byterindex("\n", -2)&.+(1)) || 0, code.bytesize)
        ["__END__", "__END__\n", "__END__\r\n"].include?(last)
      end
      private_class_method :checked_ranges, :same_code?

      # The ranges of the file at `path`: from the program's spot table, or
      # from the spots of a load that compiled it at run time.
      def self.ranges_of(path)
        Primitive.attr! :hidden
        return ranges[path] if ranges.key?(path)

        spots = defined?(::Zr::Eval) && ::Zr::Eval.current.file_spots(path)
        spots ? rows(spots.split("\n")) : nil
      end
      private_class_method :ranges_of

      # `{ file => { node id => [line, column, end line, end column] } }`:
      # the ranges in the program's spot table, read once.
      def self.ranges
        Primitive.attr! :hidden
        @ranges ||= Primitive.zr_load_names(4).split("\f").to_h do |text|
          file, *lines = text.split("\n")
          [file, rows(lines)]
        end
      end

      # `{ node id => [line, column, end line, end column] }` from the
      # range lines of a file's spots.
      def self.rows(lines)
        Primitive.attr! :hidden
        rows = {}
        lines.each do |line|
          id, point, _name, *numbers = line.split
          rows[id.to_i] = numbers.map(&:to_i) if point == "r"
        end
        rows
      end
      private_class_method :ranges, :rows

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

    # The level and the size are C longs, as caller's are.
    start = Primitive.zr_index_operand_m(start)
    raise ArgumentError, "negative level (#{start})" if start.negative?
    length = Primitive.zr_index_operand_m(length) unless length.nil?
    rows = caller(start + 1, length) or return nil

    # Pairs of [node, line], one per row.
    places = Primitive.zr_caller_places(start + 1, length)
    Array.new(rows.size) { |i| Thread::Backtrace::Location.send(:made, rows[i], places[i * 2] || 0, places[(i * 2) + 1]) }
  end
  private :caller_locations
end
