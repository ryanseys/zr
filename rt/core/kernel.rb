# Kernel's conversion and convenience methods.
module Kernel
  def <=>(other) = equal?(other) || self == other ? 0 : nil

  def loop
    return to_enum(:loop) { Float::INFINITY } unless block_given?

    begin
      while true
        yield
      end
    rescue StopIteration => e
      e.result
    end
  end

  def exit(status = true)
    raise SystemExit.new(exit_status(status), "exit")
  end

  # How a conversion message names a value: nil, true and false by
  # themselves, and anything else by its class -- an anonymous class by
  # the path it carries instead of a name, which is what
  # rb_builtin_class_name answers. A user's own `==` never decides this,
  # so the two singletons are compared by identity.
  def conversion_name(value)
    Primitive.attr! :hidden
    value.nil? || value.equal?(true) || value.equal?(false) ? value.inspect : value.class.to_s
  end
  private :conversion_name

  # The message goes to stderr at once; the SystemExit carries it.
  def abort(*args)
    raise SystemExit.new(1, "exit") if args.empty?

    message = args[0]
    raise TypeError, "no implicit conversion of #{conversion_name(message)} into String" unless message.is_a?(String)

    Primitive.zr_warn_line(message)
    raise SystemExit.new(1, message)
  end

  # A literal name is resolved when the program is compiled. A computed
  # one is found when the call runs, as ruby finds it.
  def require(name) = Kernel.required(name)

  # A require's search and load, which Kernel#require and Kernel.require
  # share.
  def self.required(name)
    Primitive.attr! :hidden
    feature = File.path(name)
    return false if preloaded?(feature)

    load_file(feature_path(feature), feature, 0)
  end

  # The name is taken from the directory of the file that calls.
  def require_relative(name)
    file = Primitive.zr_caller_file
    raise LoadError, "cannot infer basepath" if file.nil?

    path = File.expand_path(File.path(name), File.dirname(file))
    Kernel.load_file(Kernel.feature_path(path), path, 1)
  end

  # A load runs the file each time, and names it exactly: a path that
  # says where it starts, else a file under a $LOAD_PATH directory, else
  # one under the working directory.
  #
  # A `wrap` runs the file under a module: the one given, or a new one
  # for any other true value. Its constants and methods land there, and
  # its self is a clone of main that the module extends.
  def load(name, wrap = false)
    feature = File.path(name)
    path = Kernel.search(feature) || (Primitive.zr_path_kind(feature) == 2 && File.expand_path(feature))
    return Kernel.load_file(path, feature, 2) unless wrap

    Kernel.missing(feature, 2) unless path
    mod = wrap.is_a?(Module) ? wrap : Module.new
    return Primitive.zr_unimplemented("load with a wrap module") unless defined?(::Ze0::Eval)

    code = ::Ze0::Eval.current.compile(File.read(path), path, 1, [], false)
    Primitive.zr_eval_run(code, TOPLEVEL_BINDING.receiver.clone.extend(mod), Primitive.zr_wrap_cref(mod), nil, nil)
    true
  end

  # The file a require of `feature` runs, or nil, as the compiler
  # resolves a literal name: a name with no `.rb` names a file that ends
  # in it, and a native extension's name also names the Ruby that stands
  # in for it among this runtime's native halves.
  def self.feature_path(feature)
    Primitive.attr! :hidden
    return search(feature) if feature.end_with?(".rb")

    found = search("#{feature}.rb")
    return found if found || !feature.end_with?(".so", ".bundle", ".dylib", ".o")

    found(File.join(Primitive.zr_load_names(3), "#{feature.delete_suffix(File.extname(feature))}.rb"))
  end

  # `name` looked for as ruby looks: a path that says where it starts is
  # taken from there; any other name under each $LOAD_PATH directory and
  # the library the program was compiled against.
  def self.search(name)
    Primitive.attr! :hidden
    return found(File.expand_path(name)) if name.start_with?("/", "./", "../", "~")

    # The library the program was compiled against lists pure Ruby first,
    # then the gems whose native half this runtime carries. Those come
    # ahead of $LOAD_PATH: an installed copy of such a gem that rubygems
    # activates has a C half no program here can load.
    pure, *native = Primitive.zr_load_names(0).split("\n")
    dirs = native + $LOAD_PATH.map { |dir| File.path(dir) } + [pure].compact
    dirs.each do |dir|
      path = found(File.expand_path(name, dir))
      return path if path
    end
    nil
  end

  # `path`, when the program was compiled with that file or it is there.
  def self.found(path)
    Primitive.attr! :hidden
    path if Primitive.zr_unit_for(path) || Primitive.zr_path_kind(path) == 2
  end

  # Whether ruby loaded `feature` before the program, by any of its names.
  def self.preloaded?(feature)
    Primitive.attr! :hidden
    Primitive.zr_load_names(2).split("\n").include?(feature.sub(/\.(?:rb|so|bundle)\z/, ""))
  end

  # Whether a require of `feature` would read no file, because the
  # runtime holds it already or a require read it before. `autoload`
  # asks: ruby keeps no row for such a feature and declares the name
  # alone, and a name no file answers is not loaded, so it keeps its row
  # and raises where the constant is read.
  def self.loaded_feature?(feature)
    Primitive.attr! :hidden
    return true if preloaded?(feature)

    path = begin
      feature_path(feature)
    rescue LoadError
      nil
    end
    !path.nil? && $LOADED_FEATURES.include?(path)
  end

  # A require (kind 0), require_relative (1) or load (2) of the file at
  # `path`, which `feature` named: its compiled toplevel when the program
  # was compiled with the file, or the file compiled now. A feature ruby
  # carries that this runtime has no file for stops by name.
  def self.load_file(path, feature, kind)
    Primitive.attr! :hidden
    missing(feature, kind) unless path
    return false if kind != 2 && $LOADED_FEATURES.include?(path)

    Primitive.zr_require_computed(path, Primitive.zr_unit_for(path) || compile(path), kind)
  end

  # A name no file answers: ruby's LoadError, or a stop by name for a
  # feature ruby carries that this runtime has no file for.
  def self.missing(feature, kind)
    Primitive.attr! :hidden
    if kind == 0 && Primitive.zr_load_names(1).split("\n").include?(feature.delete_suffix(".rb"))
      Primitive.zr_unloadable("require of #{feature.inspect}")
    end
    error = LoadError.new("cannot load such file -- #{feature}")
    error.instance_variable_set(:@path, feature)
    raise error
  end

  # A file the program was not compiled with, compiled by the compiler a
  # program that computes a require carries.
  def self.compile(path)
    Primitive.attr! :hidden
    return Primitive.zr_unimplemented("require of a file the program was not compiled with") unless defined?(::Ze0::Eval)

    ::Ze0::Eval.current.compile_file(path)
  end

  def at_exit(&block)
    raise ArgumentError, "called without a block" unless block

    Primitive.zr_at_exit_add(block)
  end

  def tap
    yield self
    self
  end

  def then
    return to_enum(:then) { 1 } unless block_given?

    yield self
  end
  alias yield_self then

  def Integer(arg, base = 0, exception: true)
    Primitive.attr! :ruby
    value = arg
    base = implicit_integer(base)
    if value.is_a?(String)
      n = parse_integer(value, base)
      return n if n
      return nil unless exception

      raise ArgumentError, "invalid value for Integer(): #{value.inspect}"
    end
    raise ArgumentError, "base specified for non string value" unless base.zero?
    return value if value.is_a?(Integer)

    if value.nil?
      return nil unless exception

      raise TypeError, "can't convert nil into Integer"
    end
    return value.to_int if value.respond_to?(:to_int)
    return value.to_i if value.respond_to?(:to_i)
    return nil unless exception

    raise TypeError, "can't convert #{conversion_name(value)} into Integer"
  end

  def String(value)
    return value if value.is_a?(String)
    return value.to_str if value.respond_to?(:to_str)
    return value.to_s if value.respond_to?(:to_s)

    raise TypeError, "can't convert #{conversion_name(value)} into String"
  end

  # rb_Array: to_ary, else to_a, else the value alone. Either answering
  # nil passes to the next; answering anything but an Array is refused.
  def Array(value)
    converted = Array.try_convert(value)
    return converted if converted

    if value.respond_to?(:to_a)
      converted = value.to_a
      return converted if converted.is_a?(Array)
      raise TypeError, "can't convert #{conversion_name(value)} to Array (#{conversion_name(value)}#to_a gives #{conversion_name(converted)})" unless converted.nil?
    end
    [value]
  end


  # The current thread sleeps `duration` seconds, or until `wakeup`
  # without one; the answer is the seconds slept, rounded.
  def sleep(duration = (forever = true; nil))
    # rb_f_sleep: a non-blocking fiber sleeps through its scheduler.
    if (scheduler = Fiber.current_scheduler)
      began = Process.clock_gettime(Process::CLOCK_REALTIME, :second)
      forever ? scheduler.kernel_sleep : scheduler.kernel_sleep(duration)
      return Process.clock_gettime(Process::CLOCK_REALTIME, :second) - began
    end
    unless duration.nil?
      raise TypeError, "can't convert #{duration.class} into time interval" unless duration.is_a?(Numeric)
      raise ArgumentError, "time interval must not be negative" if duration < 0
    end
    # The answer is whole seconds of the wall clock, time(2) after less
    # time(2) before, as rb_f_sleep counts them.
    began = Process.clock_gettime(Process::CLOCK_REALTIME, :second)
    deadline = duration.nil? ? nil : Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) + (duration * 1e9).to_i
    Thread.current.send(:wait, deadline, false)
    Process.clock_gettime(Process::CLOCK_REALTIME, :second) - began
  end

  def itself = self

  def clone(freeze: nil)
    Primitive.attr! :ruby
    Primitive.zr_obj_clone(self, freeze)
  end

  # Every message on its own line, the first carrying the position
  # `uplevel` frames above this call. A category the program turned off
  # says nothing at all.
  def warn(*msgs, uplevel: nil, category: nil)
    Primitive.attr! :ruby
    # rb_warn_m: silence, with $VERBOSE nil, says nothing at all.
    return nil if msgs.empty? || $VERBOSE.nil?
    return nil if category && !Warning[category]

    text = msgs.flatten.map { |m| m.to_s.end_with?("\n") ? m.to_s : "#{m}\n" }.join
    unless uplevel.nil?
      frame = caller(implicit_integer(uplevel) + 1, 1)&.first
      text = "#{frame ? "#{frame.sub(/:in .*\z/, '')}: " : ''}warning: #{text}"
    end
    Warning.warn(text, category: category)
    nil
  end

  private

  # An Integer argument as CRuby's NUM2LONG reads one: an Integer, a
  # Float truncated, or whatever `to_int` answers.
  def implicit_integer(value)
    Primitive.attr! :hidden
    return value if value.is_a?(Integer)
    raise TypeError, "no implicit conversion from nil to integer" if value.nil?
    raise TypeError, "no implicit conversion of #{conversion_name(value)} into Integer" unless value.respond_to?(:to_int)

    value.to_int
  end

  # rb_to_int: an Integer, or what `to_int` makes one, where nil is a
  # value like any other.
  def to_integer(value)
    Primitive.attr! :hidden
    return value if value.is_a?(Integer)
    raise TypeError, "no implicit conversion of #{conversion_name(value)} into Integer" unless value.respond_to?(:to_int)

    converted = value.to_int
    return converted if converted.is_a?(Integer)

    raise TypeError, "can't convert #{value.class} to Integer (#{value.class}#to_int gives #{converted.class})"
  end

  def exit_status(status)
    Primitive.attr! :hidden
    return 0 if status == true
    return 1 if status == false
    return status if status.is_a?(Integer)
    raise TypeError, "no implicit conversion from nil to integer" if status.nil?

    raise TypeError, "no implicit conversion of #{conversion_name(status)} into Integer"
  end

  # The strict form: whitespace around, a sign, a `0x`, `0b`, `0o` or
  # `0d` prefix, digits with single underscores between them; nil on
  # anything else.
  def parse_integer(text, base)
    Primitive.attr! :hidden
    # A NUL is not a digit and `strip` would drop it, so the scan that
    # follows would read a prefix and call the rest of the text good.
    return nil if text.include?("\u0000")

    base = -base if base < 0
    raise ArgumentError, "invalid radix #{base}" if base == 1 || base > 36

    s = text.strip
    sign = 1
    if s.start_with?("-", "+")
      sign = -1 if s.start_with?("-")
      s = s[1..]
    end
    if base == 0
      base = 10
      if s.start_with?("0x", "0X") then base = 16; s = s[2..]
      elsif s.start_with?("0b", "0B") then base = 2; s = s[2..]
      elsif s.start_with?("0o", "0O") then base = 8; s = s[2..]
      elsif s.start_with?("0d", "0D") then s = s[2..]
      elsif s.start_with?("0") && s.bytesize > 1 then base = 8
      end
    elsif base == 16 && s.start_with?("0x", "0X") then s = s[2..]
    elsif base == 2 && s.start_with?("0b", "0B") then s = s[2..]
    elsif base == 8 && s.start_with?("0o", "0O") then s = s[2..]
    elsif base == 10 && s.start_with?("0d", "0D") then s = s[2..]
    end
    return nil if s.empty? || s.start_with?("_") || s.end_with?("_") || s.include?("__")

    n = 0
    s.each_byte do |b|
      next if b == 95

      digit = if b >= 48 && b <= 57 then b - 48
              elsif b >= 97 && b <= 122 then b - 87
              elsif b >= 65 && b <= 90 then b - 55
              else return nil
              end
      return nil if digit >= base

      n = n * base + digit
    end
    sign * n
  end
end

class NilClass
  def to_i = 0
  def to_f = 0.0
  def to_a = []
  def to_h = {}
  def &(other) = false
  def |(other) = other ? true : false
  def ^(other) = other ? true : false
  def nil? = true
end

class TrueClass
  def &(other) = other ? true : false
  def |(other) = true
  def ^(other) = other ? false : true
end

class NilClass
  def =~(other) = nil
end

class FalseClass
  def &(other) = false
  def |(other) = other ? true : false
  def ^(other) = other ? true : false
end

module Kernel
  # A program that names an eval carries the compiler, and the eval road
  # defines this again over the compiler it brought. One that reaches an
  # eval any other way stops here, by name.
  def eval(source, binding = nil, file = "(eval)", line = 1) = Primitive.zr_unimplemented("eval reached in a program built without the compiler")

  def catch(tag = Object.new, &block)
    raise LocalJumpError, "no block given (yield)" unless block

    Primitive.zr_catch(tag, block)
  end

  def throw(tag, value = nil)
    unless Primitive.zr_catch_tag_p(tag)
      raise UncaughtThrowError.new(tag, value, "uncaught throw %p")
    end

    Primitive.zr_throw(tag, value)
  end
end

# Commands on global variables: each assignment to a traced global runs
# its commands with the new value, the newest first, as rb_gvar_set_entry
# runs them. A command that assigns the global it watches runs no
# command again.
module Kernel
  def trace_var(*args, &block)
    raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 1..2)" unless args.size.between?(1, 2)
    raise ArgumentError, "tried to create Proc object without a block" if args.size == 1 && block.nil?

    name, command = args.size == 1 ? [args[0], block] : args
    return untrace_var(*args) if command.nil?

    name = Primitive.zr_gvar_resolve_m(Kernel.send(:global_name, name))
    Kernel.send(:gvar_commands)[name].unshift(command)
    Primitive.zr_gvar_traced
    nil
  end

  def untrace_var(*args)
    raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 1..2)" unless args.size.between?(1, 2)

    name, command = args
    name = Primitive.zr_gvar_resolve_m(Kernel.send(:global_name, name))
    commands = Kernel.send(:gvar_commands)
    unless commands.key?(name) || Primitive.zr_gvar_defined_m(name)
      raise NameError.new("undefined global variable #{name}", name)
    end
    if command.nil?
      removed = commands[name]
      commands[name] = []
      return removed
    end
    [command] if commands[name].delete(command) { nil }
  end

  # A hook every thread's events reach, which replaces the one before.
  def set_trace_func(hook) = TracePoint.send(:trace_func, hook, nil, false)

  # Ruby's own globals, in the order ruby lists them, then the ones the
  # program assigned or aliased.
  def global_variables = Kernel.send(:builtin_globals) | Primitive.zr_global_variables

  module_function :trace_var, :untrace_var, :set_trace_func

  class << self
    private

    # rb_to_id: a Symbol, or a String that names one.
    def global_name(name)
      Primitive.attr! :hidden
      return name if name.is_a?(Symbol)

      text = String.try_convert(name)
      raise TypeError, "#{name.inspect} is not a symbol nor a string" if text.nil?

      text.to_sym
    end

    def gvar_commands
      Primitive.attr! :hidden
      Primitive.zr_hidden_get(self, :__gvar_commands__) ||
        Primitive.zr_hidden_set(self, :__gvar_commands__, Hash.new { |table, name| table[name] = [] })
    end

    def builtin_globals
      Primitive.attr! :hidden
      %i[
        $? $-w $DEBUG $-d $@ $; $-F $: $-I $LOAD_PATH $" $LOADED_FEATURES $0 $PROGRAM_NAME $-p $-l $-a $& $` $' $+ $=
        $stdin $stdout $> $stderr $VERBOSE $-v $, $/ $-0 $\\ $-W $_ $~ $< $! $. $FILENAME $-i $* $$
      ]
    end

    # The globals ruby refuses to assign.
    READ_ONLY_GLOBALS = %i[$! $& $` $' $+ $$ $? $* $< $FILENAME $LOAD_PATH $LOADED_FEATURES $-a $-l $-p $-W].freeze

    # A program assigns `value` to the global `name`, which it wrote as
    # `shown`: the setter ruby hooks on that global checks the value and
    # answers what the global holds.
    def hooked_global(shown, name, value)
      Primitive.attr! :hidden
      case name
      when *READ_ONLY_GLOBALS
        raise NameError.new("#{shown} is a read-only variable", shown)
      when :$@
        raise ArgumentError, "$! not set" if $!.nil?

        $!.set_backtrace(value)
      when :$~
        raise TypeError, "wrong argument type #{conversion_name(value)} (expected MatchData)" unless value.nil? || value.is_a?(MatchData)
      when :$;
        raise TypeError, "value of #{shown} must be String or Regexp" unless value.nil? || value.is_a?(String) || value.is_a?(Regexp)

        Warning.send(:deprecated, "non-nil '#{shown}' is deprecated") unless value.nil?
      when :$,, :$\
        separator(shown, value)
      when :$/
        separator(shown, value)
        return value.frozen? || value == "\n" ? value : value.dup.freeze unless value.nil?
      when :$stdout, :$stderr
        raise TypeError, "#{shown} must have write method, #{value.class} given" unless value.respond_to?(:write)
      when :$0
        text = String.try_convert(value)
        raise TypeError, "no implicit conversion of #{conversion_name(value)} into String" if text.nil?

        return text.frozen? ? text : text.dup.freeze
      when :$VERBOSE
        return value ? true : value
      when :$.
        return Integer.send(:int_operand, value)
      end
      value
    end

    # rb_deprecated_str_setter: a String or nil, and a warning for a
    # String.
    def separator(shown, value)
      Primitive.attr! :hidden
      raise TypeError, "value of #{shown} must be String" unless value.nil? || value.is_a?(String)

      Warning.send(:deprecated, "non-nil '#{shown}' is deprecated") unless value.nil?
    end

    # The global `name` was assigned `value`: its commands run, unless
    # they run already.
    def traced_assign(name, value)
      Primitive.attr! :hidden
      commands = gvar_commands.fetch(name, nil)
      return if commands.nil? || commands.empty?

      running = Primitive.zr_hidden_get(self, :__gvar_running__) || Primitive.zr_hidden_set(self, :__gvar_running__, {})
      return if running.key?(name)

      running[name] = true
      begin
        # A loop and not `each`, whose frame CRuby's backtrace has no row for.
        pending = commands.dup
        until pending.empty?
          command = pending.shift
          command.is_a?(String) ? TOPLEVEL_BINDING.send(:eval, command) : command.call(value)
        end
      ensure
        running.delete(name)
      end
    end
  end
end

module Kernel
  private :Integer, :String, :Array, :sleep, :warn, :catch, :throw, :loop, :exit, :abort, :at_exit, :require, :require_relative, :load
end

# A `ruby2_keywords` method keeps the keywords it took into its rest
# flagged, so a `*rest` call passes them on as keywords.
class << self
  def ruby2_keywords(*names)
    names.each { |name| Primitive.zr_ruby2_mark_m(Object, name) }
    nil
  end
  private :ruby2_keywords
end

class Module
  def ruby2_keywords(*names)
    names.each { |name| Primitive.zr_ruby2_mark_m(self, name) }
    nil
  end
  private :ruby2_keywords
end

module Kernel
  def putc(char)
    if char.is_a?(String)
      print char[0]
    else
      print (Integer(char) & 255).chr
    end
    char
  end

  PRETTY_PRINTER = []
  private_constant :PRETTY_PRINTER

  def self.pretty_printer=(load)
    Primitive.attr! :hidden
    PRETTY_PRINTER[0] = load
  end

  # The load pp arms, taken once: pp.rb's own pp answers every call
  # after the first.
  def self.pretty_printer
    Primitive.attr! :hidden
    PRETTY_PRINTER.pop
  end

  # CRuby's prelude: the first pp requires ruby's own pp.rb, whose
  # Kernel#pp replaces this one. A program that names pp carries pp.rb
  # and arms that require; one that reaches pp only through a name it
  # builds prints inspect on a line each, as `p` does.
  def pp(*objs)
    Primitive.attr! :ruby
    if (load = Kernel.send(:pretty_printer))
      load.call
      # A send of the core library reaches the core's own row, so the
      # call goes through the row pp.rb wrote.
      return Kernel.instance_method(:pp).bind_call(self, *objs)
    end
    # CRuby's first pp requires pp.rb, which makes pp a module function
    # from then on; before that, Kernel.pp is private.
    Kernel.send(:module_function, :pp) unless Kernel.singleton_class.method_defined?(:pp)
    objects = objs
    objects.each do |object|
      text = object.inspect
      Primitive.zr_unimplemented("pp of an object whose inspect is 80 columns or wider") if text.size >= 80
      puts text
    end
    objects.size <= 1 ? objects[0] : objects
  end
  # CRuby's prelude aliases pp to itself, so pp.rb's definition over it
  # warns of no redefinition.
  alias pp pp

  def Hash(value)
    return {} if value.nil? || (value.is_a?(Array) && value.empty?)
    return value if value.is_a?(Hash)
    return value.to_hash if value.respond_to?(:to_hash)

    raise TypeError, "can't convert #{value.class} into Hash"
  end

  def display(port = $>)
    port.write(to_s)
    nil
  end

  def singleton_method(name)
    raise NameError.new("undefined singleton method '#{name}' for '#{inspect}'", name) unless singleton_methods.include?(name.to_sym)

    method(name)
  end

  def exit!(status = false)
    Primitive.zr_exit_now(status == true ? 0 : (status == false ? 1 : status))
  end

  def !~(other) = !(self =~ other)

  # The same call as IO.select, which Kernel carries too.
  def select(*) = IO.select(*)

  private :putc, :pp, :Hash, :exit!, :select
  # pp is Kernel's private method alone, as CRuby's prelude defines it:
  # no module function.
  module_function :putc, :Hash, :exit!, :select
end

class Module
  alias attr attr_reader

  def set_temporary_name(name)
    if name.nil?
      Primitive.zr_mod_set_temporary_name(self, nil)
      return self
    end
    name = name.to_str
    raise ArgumentError, "empty class/module name" if name.empty?
    raise ArgumentError, "the temporary name must not be a constant path to avoid confusion" if name.split("::").all? { |part| constant_name?(part) }
    raise RuntimeError, "can't change permanent name" unless Primitive.zr_mod_set_temporary_name(self, -name)

    self
  end
end

class Module
  private

  def constant_name?(part)
    Primitive.attr! :hidden
    !part.empty? && part[0].between?("A", "Z") && part.chars.all? { |c| c.between?("A", "Z") || c.between?("a", "z") || c.between?("0", "9") || c == "_" }
  end
end

class Class
  def attached_object
    object = Primitive.zr_mod_attached(self)
    raise TypeError, "'#{inspect}' is not a singleton class" if object.nil?

    object
  end
end
