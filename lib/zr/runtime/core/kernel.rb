# frozen_string_literal: true

# Kernel's conversion and convenience methods.
module Kernel
  # rb_exec_recursive_outer for Array#hash, Hash#hash and Struct#hash: the
  # block's hash of `obj`, unless the walk meets an object that it is
  # inside of. Then the outermost call gives `recursed`, a hash that the
  # caller makes without the elements, so equal recursive structures hash
  # the same.
  def self.outer_hash(obj, recursed)
    Primitive.attr! :hidden
    fiber = Fiber.current
    tag = Primitive.zr_hidden_get(fiber, :__hash_outer__)
    if tag
      throw tag if Primitive.zr_recursive_enter(obj, :hash)

      begin
        return yield
      ensure
        Primitive.zr_recursive_leave(obj, :hash)
      end
    end
    tag = Object.new
    Primitive.zr_state_set(fiber, :__hash_outer__, tag)
    Primitive.zr_recursive_enter(obj, :hash)
    begin
      met = true
      value = catch(tag) do
        v = yield
        met = false
        v
      end
      met ? recursed : value
    ensure
      Primitive.zr_recursive_leave(obj, :hash)
      Primitive.zr_state_set(fiber, :__hash_outer__, nil)
    end
  end

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
    raise SystemExit.new(exit_status(status), +"exit")
  end

  # How a conversion message shows a value: nil, true and false as
  # themselves, and any other value by its class. An anonymous class
  # shows its path in place of a name, as rb_builtin_class_name returns.
  # A user's own `==` never decides this, so the two singletons are
  # compared by identity.
  def conversion_name(value)
    Primitive.attr! :hidden
    nil.equal?(value) || true.equal?(value) || false.equal?(value) ? value.inspect : Primitive.zr_real_class(value).to_s
  end
  private :conversion_name

  # The message goes to stderr immediately; the SystemExit contains it.
  def abort(*args)
    raise SystemExit.new(1, +"exit") if args.empty?

    # rb_f_abort: StringValue of the message.
    message = Primitive.zr_str_operand(args[0])

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
    return false if preloaded?(feature) || parserless?(feature)

    # A listed file that a require is running now goes on, so the
    # kernel waits for that require.
    listed = feature_listed(feature)
    return false if listed.is_a?(String) && Primitive.zr_feature_loader(listed).nil?

    path = feature_path(feature)
    return false if path.nil? && listed == :bare

    load_file(path, feature, 0)
  end

  # CRuby's rb_feature_p for the name as it was written, before any file
  # is found. The entry of $LOADED_FEATURES that is the name (a name with
  # no extension with `.rb`), or a $LOAD_PATH directory joined to it. Else
  # :bare when the list has a name with no extension as it is, or with the
  # native extension: ruby then looks only for a `.rb` file, which still
  # loads, and no file is not an error. Else nil.
  def self.feature_listed(feature)
    Primitive.attr! :hidden
    bare = File.extname(feature).empty?
    name = bare ? "#{feature}.rb" : feature
    partial = bare ? [feature, "#{feature}.#{RbConfig::CONFIG["DLEXT"]}"] : []
    dirs = feature.start_with?("/", "./", "../", "~") ? {} : nil
    listed = nil
    $LOADED_FEATURES.each do |entry|
      entry = entry.to_s
      dirs ||= $LOAD_PATH.to_h { |dir| [load_dir(dir), true] }
      return entry if feature_entry?(entry, name, dirs)

      listed = :bare if partial.any? { |n| feature_entry?(entry, n, dirs) }
    end
    listed
  end

  # Whether `entry` of $LOADED_FEATURES is `name`, or one of `dirs` joined
  # to it.
  def self.feature_entry?(entry, name, dirs)
    Primitive.attr! :hidden
    return true if entry == name

    entry.end_with?(name) && entry[-name.size - 1] == "/" && dirs.key?(entry[0, entry.size - name.size - 1])
  end

  # A $LOAD_PATH entry as ruby searches it: expanded, and by its real path,
  # so the file that a symlinked directory holds is stored under the
  # directory it names.
  def self.load_dir(dir)
    Primitive.attr! :hidden
    dir = File.expand_path(File.path(dir))
    File.directory?(dir) ? File.realpath(dir) : dir
  end

  # syntax_suggest's detailed_message loads its search, which needs
  # prism, for each SyntaxError. The search reads only an error with a
  # path, which a program without the compiler cannot get, so there the
  # method returns the message as it is.
  def self.parserless?(feature)
    Primitive.attr! :hidden
    feature == "syntax_suggest/api" && !defined?(::Zr::Eval) && Primitive.zr_caller_file&.end_with?("/syntax_suggest/core_ext.rb")
  end

  # The name is taken from the directory of the file that calls, by its
  # real path, as ruby's rb_current_realfilepath: a file loaded through a
  # symlink requires relative to the file the link names. A compiled-in
  # file that is not there now keeps the path it was loaded by.
  def require_relative(name)
    file = Primitive.zr_caller_file
    raise LoadError, +"cannot infer basepath" if file.nil?

    file = File.realpath(file) if File.exist?(file)
    path = File.expand_path(File.path(name), File.dirname(file))
    Kernel.load_file(Kernel.feature_path(path), path, 1)
  end

  # A load runs the file each time, and finds it exactly: a path that
  # says where it starts, else a file under a $LOAD_PATH directory, else
  # one under the working directory.
  #
  # A `wrap` runs the file under a module: the one given, or a new one
  # for any other true value. Its constants and methods go there, and
  # its self is a clone of main that the module extends.
  def load(name, wrap = false)
    feature = File.path(name)
    path = Kernel.search(feature) || (Primitive.zr_path_kind(feature) == 2 && File.readable?(feature) && File.expand_path(feature))
    return Kernel.load_file(path, feature, 2) unless wrap

    Kernel.missing(feature, 2) unless path
    mod = wrap.is_a?(Module) ? wrap : Module.new
    return Primitive.zr_unimplemented(+"load with a wrap module") unless defined?(::Zr::Eval)

    code = ::Zr::Eval.current.compile(File.read(path), path, 1, [], false)
    Primitive.zr_eval_run(code, TOPLEVEL_BINDING.receiver.clone.extend(mod), Primitive.zr_wrap_cref(mod), nil, nil)
    true
  end

  # The file that a require of `feature` runs, or nil, as the compiler
  # resolves a literal name. A name with no `.rb` refers to a file that
  # ends in it. A native extension's name also refers to the Ruby file
  # that replaces it in this runtime's native parts.
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

    # The library that the program was compiled against lists the roots
    # of this runtime's ports of C, an empty line, then the others. The
    # ports come before $LOAD_PATH: an installed copy of such a gem that
    # rubygems activates has a C part that no program here can load. The
    # others come after it, as ruby's own library does, so a directory the
    # program adds can shadow them.
    lines = Primitive.zr_load_names(0).split("\n")
    cut = lines.index("") || lines.size
    dirs = lines[0, cut] + $LOAD_PATH.map { |dir| File.path(dir) } + (lines[cut + 1..] || [])
    dirs.each do |dir|
      path = found_in(dir, name)
      return path if path
    end
    nil
  end

  # `name` under the directory `dir`, by the directory's real path as
  # ruby stores it. A file compiled into the program under the path as
  # written is found there too, so it never needs a compile at run time.
  def self.found_in(dir, name)
    Primitive.attr! :hidden
    plain = File.expand_path(name, dir)
    real = File.expand_path(name, load_dir(dir))
    return real if Primitive.zr_unit_for(real)
    return plain if Primitive.zr_unit_for(plain)

    found(real)
  end

  # `path`, when the program was compiled with that file or it is there
  # and readable. Ruby skips a file that it cannot read, as rb_find_file
  # does, so a require of it is a LoadError.
  def self.found(path)
    Primitive.attr! :hidden
    path if Primitive.zr_unit_for(path) || (Primitive.zr_path_kind(path) == 2 && File.readable?(path))
  end

  # Whether ruby loaded `feature` before the program, by any of its names.
  def self.preloaded?(feature)
    Primitive.attr! :hidden
    Primitive.zr_load_names(2).split("\n").include?(feature.sub(/\.(?:rb|so|bundle)\z/, ""))
  end

  # Whether a require of `feature` would read no file, because the
  # runtime contains it already or an earlier require read it.
  # `autoload` calls this: ruby keeps no entry for such a feature and
  # declares only the name. A name that matches no file is not loaded,
  # so it keeps its entry and raises where the constant is read.
  def self.loaded_feature?(feature)
    Primitive.attr! :hidden
    return true if preloaded?(feature)

    path = feature_file(feature)
    !path.nil? && Primitive.zr_table_member_p($LOADED_FEATURES, path)
  end

  # The path that a require of `feature` would read, or nil when no file
  # of that name is on any load path. An autoload keeps this next to the
  # feature as it was written, so that a require of the same file is
  # recognised by any name. Ruby finds the file again each time; here it
  # is found once.
  def self.feature_file(feature)
    Primitive.attr! :hidden
    feature_path(feature)
  rescue LoadError
    nil
  end

  # A require (kind 0), require_relative (1) or load (2) of the file at
  # `path`, which `feature` gave: its compiled toplevel when the program
  # was compiled with the file, or the file compiled now. A feature that
  # ruby includes but this runtime has no file for is a refusal.
  def self.load_file(path, feature, kind)
    Primitive.attr! :hidden
    return missing(feature, kind) unless path
    # An autoload of this feature stops waiting however the file arrives
    # here: through this require, or through an earlier one. Ruby calls
    # `rb_feature_provided` again each time it checks whether an entry is
    # pending. This is the same check, done once, where both the name
    # and its resolved file are available.
    Primitive.zr_autoload_provided(feature, path) if kind != 2
    # A file that a require is running now goes on to the kernel, which
    # waits for that require as ruby does.
    return false if kind != 2 && Primitive.zr_table_member_p($LOADED_FEATURES, path) && Primitive.zr_feature_loader(path).nil?

    Primitive.zr_require_computed(path, Primitive.zr_unit_for(path) || compile(path), kind)
  end

  # A name that matches no file: ruby's LoadError, a built-in extension,
  # or a refusal for a feature that ruby includes but this runtime has no
  # file for. An entry of the table contains the reason after a tab when
  # there is one, and that reason is the full refusal message.
  def self.missing(feature, kind)
    Primitive.attr! :hidden
    if kind == 0
      name = feature.delete_suffix(".rb").delete_suffix(".so")
      row = Primitive.zr_load_names(1).lines(chomp: true).find { |line| line.split("\t", 2).first == name }
      return builtin_extension(name) if row && name.start_with?("enc/")

      Primitive.zr_unloadable(row.split("\t", 2)[1] || "require of #{feature.inspect}") if row
      # A C extension that is there but does not load: ruby's error is
      # dlopen's, with no path.
      native = native_file(feature)
      raise LoadError, "#{native}: a C extension, which zr cannot load" if native
    end
    error = LoadError.new("cannot load such file -- #{feature}")
    error.instance_variable_set(:@path, feature)
    raise error
  end

  # The C extension file that a require of `feature` finds, or nil: the
  # name with the native extension (for `.so` too, as ruby maps it).
  def self.native_file(feature)
    Primitive.attr! :hidden
    dlext = ".#{RbConfig::CONFIG["DLEXT"]}"
    ext = File.extname(feature)
    return nil unless ext.empty? || ext == ".so" || ext == dlext

    search(ext.empty? ? "#{feature}#{dlext}" : feature.delete_suffix(ext) + dlext)
  end

  # An encoding or transcoder extension of ruby's, which this runtime has
  # built in. Like ruby's require of the extension, it returns true the
  # first time, and lists the file where ruby has it.
  def self.builtin_extension(name)
    Primitive.attr! :hidden
    path = "#{RbConfig::CONFIG["rubyarchdir"]}/#{name}.#{RbConfig::CONFIG["DLEXT"]}"
    return false if $LOADED_FEATURES.include?(path)

    $LOADED_FEATURES << path
    true
  end

  # A require of `path` while a require runs it. From the thread that
  # runs it (`same`), it is a circular require: ruby warns under $VERBOSE,
  # with the backtrace, and returns false. From another thread, it waits,
  # asleep as ruby waits on the file's lock, and returns nil, so the
  # kernel looks again.
  def self.feature_busy(path, same)
    Primitive.attr! :hidden
    unless same
      sleep 0.001
      return nil
    end
    if $VERBOSE
      Primitive.zr_warn_here_m("loading in progress, circular require considered harmful - #{path}")
      caller(1).each { |line| $stderr.write("\tfrom #{line}\n") }
    end
    false
  end

  # A file that the program was not compiled with, compiled by the
  # compiler that a program with a computed require links in.
  def self.compile(path)
    Primitive.attr! :hidden
    return Primitive.zr_unimplemented(+"require of a file the program was not compiled with") unless defined?(::Zr::Eval)

    ::Zr::Eval.current.compile_file(path)
  end

  def at_exit(&block)
    raise ArgumentError, +"called without a block" unless block

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

  # The `exception:` keyword of Integer(), Float(), Rational() and
  # Complex() is true or false (rb_bool_expected).
  def exception_flag(value)
    Primitive.attr! :hidden
    return value if value == true || value == false

    raise ArgumentError, "expected true or false as exception: #{value.inspect}"
  end
  private :exception_flag

  def Integer(arg, base = 0, exception: true)
    Primitive.attr! :ruby
    exception = exception_flag(exception)
    value = arg
    base = implicit_integer(base)
    # rb_convert_to_integer, step by step.
    unless base.zero? || value.is_a?(String)
      value = String.try_convert(value)
      unless value
        return nil unless exception

        raise ArgumentError, +"base specified for non string value"
      end
    end
    case value
    when String then return string_integer(value, base, exception)
    when Integer then return value
    when Float
      return nil if !exception && !value.finite?

      return value.to_i
    when nil
      return nil unless exception

      raise TypeError, +"can't convert nil into Integer"
    end
    # to_int under rb_protect: an error, a throw, a break or a return out
    # of it, or a value that is no Integer, passes on to to_str, then to
    # to_i.
    converted = Primitive.zr_protect(nil) { value.to_int if value.respond_to?(:to_int) }
    return converted if converted.is_a?(Integer)

    text = String.try_convert(value)
    return string_integer(text, base, exception) if text

    unless exception
      converted = Primitive.zr_protect(nil) { value.to_i if value.respond_to?(:to_i) }
      return converted.is_a?(Integer) ? converted : nil
    end
    raise TypeError, "can't convert #{conversion_name(value)} into Integer" unless value.respond_to?(:to_i)

    converted = value.to_i
    return converted if converted.is_a?(Integer)

    raise TypeError, "can't convert #{conversion_name(value)} to Integer (#{conversion_name(value)}#to_i gives #{converted.class})"
  end

  # rb_str_convert_to_inum for Integer(): the whole text in `base`.
  def string_integer(text, base, exception)
    Primitive.attr! :hidden
    n = parse_integer(text, base)
    return n if n
    return nil unless exception

    raise ArgumentError, "invalid value for Integer(): #{text.inspect}"
  end
  private :string_integer

  # rb_String: to_str, else to_s, each as rb_check_funcall calls it.
  def String(value)
    converted = String.try_convert(value)
    return converted if converted

    converted = Primitive.zr_check_call(value, :to_s)
    return converted if String === converted

    name = conversion_name(value)
    raise TypeError, "can't convert #{name} into String" if converted.nil?

    raise TypeError, "can't convert #{name} to String (#{name}#to_s gives #{conversion_name(converted)})"
  end

  # rb_Array: to_ary, else to_a, else the value alone. If either returns
  # nil, the next is tried; if either returns a non-Array, it is refused.
  def Array(value)
    converted = Array.try_convert(value)
    return converted if converted

    # rb_check_to_array: to_a as rb_check_funcall finds it, a private
    # one too.
    converted = Primitive.zr_check_call(value, :to_a)
    return converted if converted.is_a?(Array)
    raise TypeError, "can't convert #{conversion_name(value)} to Array (#{conversion_name(value)}#to_a gives #{conversion_name(converted)})" unless converted.nil?

    [value]
  end


  # The current thread sleeps `duration` seconds, or until `wakeup`
  # with no duration. It returns the seconds slept, rounded.
  def sleep(duration = (forever = true; nil))
    # rb_f_sleep: a non-blocking fiber sleeps through its scheduler.
    if (scheduler = Fiber.current_scheduler)
      began = Process.clock_gettime(Process::CLOCK_REALTIME, :second)
      forever ? scheduler.kernel_sleep : scheduler.kernel_sleep(duration)
      return Process.clock_gettime(Process::CLOCK_REALTIME, :second) - began
    end
    # time_timespec: an object that is not a Numeric gives its seconds
    # and their fraction from divmod(1).
    if !duration.nil? && !duration.is_a?(Numeric) && duration.respond_to?(:divmod)
      pair = Array.try_convert(duration.divmod(1))
      duration = Integer.send(:int_operand, pair[0]) + Float(pair[1]) if pair
    end
    unless duration.nil?
      raise TypeError, "can't convert #{duration.class} into time interval" unless duration.is_a?(Numeric)
      raise ArgumentError, +"time interval must not be negative" if duration < 0
      raise RangeError, +"NaN out of Time range" if duration.is_a?(Float) && duration.nan?
    end
    # The return value is whole seconds of the wall clock: time(2) after
    # minus time(2) before, as rb_f_sleep counts them.
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

  # warning.rb's Kernel#warn and rb_warn_m: the messages as `puts` writes
  # them, after the position `uplevel` frames above this call. A category
  # that the program turned off writes nothing.
  def warn(*msgs, uplevel: nil, category: nil)
    Primitive.attr! :ruby
    unless category.nil?
      # rb_to_symbol_type: a Symbol, or what `to_sym` makes one.
      unless category.is_a?(Symbol)
        raise TypeError, "no implicit conversion of #{conversion_name(category)} into Symbol" unless category.respond_to?(:to_sym)

        symbol = category.to_sym
        unless symbol.is_a?(Symbol)
          raise TypeError, "can't convert #{conversion_name(category)} to Symbol (#{conversion_name(category)}#to_sym gives #{conversion_name(symbol)})"
        end
        category = symbol
      end
      return nil unless Warning[category]
    end
    return nil if msgs.empty? || $VERBOSE.nil?

    text = msgs.first
    unless msgs.size == 1 && uplevel.nil? && text.is_a?(String) && text.end_with?("\n")
      text = +""
      unless uplevel.nil?
        level = implicit_integer(uplevel)
        raise ArgumentError, "negative level (#{level})" if level.negative?

        # Frames of `<internal:` code do not count, as rb_warn_m skips them.
        at = caller_locations(1).reject { |frame| frame.path&.start_with?("<internal:") }[level]
        text << (at&.path ? "#{at.path}:#{at.lineno}: warning: " : "warning: ")
      end
      IO.send(:each_line_of, msgs) { |*parts| text.concat(*parts) }
    end
    # Warning itself writes the text, as rb_warning_string does there, so a
    # Warning#warn that calls super does not come back to itself.
    return $stderr.write(text) && nil if equal?(Warning)

    Warning.send(:emit, text, category)
    nil
  end

  private

  # An Integer argument as CRuby's NUM2LONG reads one: an Integer, a
  # truncated Float, or the value that `to_int` returns.
  def implicit_integer(value)
    Primitive.attr! :hidden
    return value if value.is_a?(Integer)
    raise TypeError, +"no implicit conversion from nil to integer" if value.nil?
    raise TypeError, "no implicit conversion of #{conversion_name(value)} into Integer" unless value.respond_to?(:to_int)

    # rb_to_int: what to_int gives must be an Integer.
    converted = value.to_int
    return converted if converted.is_a?(Integer)

    raise TypeError, "can't convert #{conversion_name(value)} to Integer (#{conversion_name(value)}#to_int gives #{conversion_name(converted)})"
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

    # NUM2INT: a Float truncates, anything else goes through to_int.
    Primitive.zr_index_operand_m(status)
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
  # A program that calls eval by name links in the compiler, and eval
  # support defines this method again over that compiler. A program that
  # reaches eval any other way stops here, with a refusal.
  def eval(source, binding = nil, file = "(eval)", line = 1) = Primitive.zr_unimplemented(+"eval reached in a program built without the compiler")

  def catch(tag = Object.new, &block)
    raise LocalJumpError, +"no block given (yield)" unless block

    Primitive.zr_catch(tag, block)
  end

  def throw(tag, value = nil)
    unless Primitive.zr_catch_tag_p(tag)
      raise UncaughtThrowError.new(tag, value, +"uncaught throw %p")
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
    raise ArgumentError, +"tried to create Proc object without a block" if args.size == 1 && block.nil?

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

    # rb_to_id: a Symbol, or a String that is its name.
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
    # `shown`. The setter that ruby hooks on that global checks the value
    # and returns the global's contents.
    def hooked_global(shown, name, value)
      Primitive.attr! :hidden
      case name
      when *READ_ONLY_GLOBALS
        raise NameError.new("#{shown} is a read-only variable", shown)
      when :$@
        raise ArgumentError, +"$! not set" if $!.nil?

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
        # rb_str_new_frozen: a plain frozen String, without the subclass
        # or the ivars of the one assigned.
        return value.frozen? && value.instance_of?(String) ? value : String.new(value).freeze unless value.nil?
      when :$=
        Warning.send(:deprecated, "variable $= is no longer effective; ignored")
        return false
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

    # rb_mod_attr: the boolean form warns under $VERBOSE, in the
    # deprecated category.
    def obsolete_attr_flag
      Primitive.attr! :hidden
      Warning.send(:deprecated, "optional boolean argument is obsoleted") if $VERBOSE
    end

    # ignorecase_getter's warning.
    def ignorecase_read
      Primitive.attr! :hidden
      Warning.send(:deprecated, "variable $= is no longer effective")
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
  # rb_mod_ruby2_keywords: only a method that takes a rest and no post
  # arguments or keywords is flagged; any other one warns.
  def ruby2_keywords(*names)
    names.each do |name|
      kinds = instance_method(name).parameters.map(&:first)
      rest = kinds.index(:rest)
      if rest && kinds[(rest + 1)..].none?(:req) && (kinds & %i[key keyreq keyrest nokey]).empty?
        Primitive.zr_ruby2_mark_m(self, name)
      else
        warn("Skipping set of ruby2_keywords flag for #{name} (method accepts keywords or post arguments or method does not accept argument splat)", uplevel: 0)
      end
    end
    nil
  end
  private :ruby2_keywords
end

module Kernel
  # rb_f_putc: $stdout's own putc, which adds no `$\`.
  def putc(char) = $stdout.putc(char)

  PRETTY_PRINTER = []
  private_constant :PRETTY_PRINTER

  def self.pretty_printer=(load)
    Primitive.attr! :hidden
    PRETTY_PRINTER[0] = load
  end

  # The load that pp arms, done once: pp.rb's own pp handles every call
  # after the first.
  def self.pretty_printer
    Primitive.attr! :hidden
    PRETTY_PRINTER.pop
  end

  # CRuby's prelude: the first pp requires ruby's own pp.rb, whose
  # Kernel#pp replaces this one. A program that calls pp by name, or
  # sends a computed name, includes pp.rb and arms that require. Any other
  # way to reach pp prints inspect on one line each, as `p` does, and
  # stops at a line that pp.rb would break.
  def pp(*objs)
    Primitive.attr! :ruby
    if (load = Kernel.send(:pretty_printer))
      load.call
      # `pp` is a name the core sends through the program's row, so
      # this reaches the one pp.rb wrote, as the prelude's call does.
      return pp(*objs)
    end
    # CRuby's first pp requires pp.rb, which makes pp a module function
    # from then on; before that, Kernel.pp is private.
    Kernel.send(:module_function, :pp) unless Kernel.singleton_class.method_defined?(:pp)
    objects = objs
    objects.each do |object|
      text = object.inspect
      Primitive.zr_unimplemented(+"pp of an object whose inspect is 80 columns or wider") if text.size >= 80
      puts text
    end
    objects.size <= 1 ? objects[0] : objects
  end
  # CRuby's prelude aliases pp to itself, so pp.rb's definition over it
  # warns of no redefinition.
  alias pp pp

  # rubygems' Kernel#gem, before rubygems loads. Ruby loads rubygems for
  # every program, so `gem` is always there. zr loads it at boot only for
  # a program whose files name Gem or call `gem`. A file that eval
  # support carries (prism/translation/parser calls `gem "parser"`) is
  # not one of the program's, so its call comes here. The first call
  # loads rubygems and gives it the program's gems, as the prelude does
  # (lib/zr/runtime/lib/zr/gem_manifest.rb). That file's `gem` then replaces
  # this one. The names are computed, so the core does not put rubygems
  # in every program: a program that reaches here carries it in eval
  # support.
  GEM_LOAD = [true]
  private_constant :GEM_LOAD

  def gem(gem_name, *requirements)
    raise LoadError, "cannot load such file -- rubygems" unless GEM_LOAD.pop

    %w[rubygems zr/gem_manifest].each { |feature| require feature }
    # A `gem` or `__send__(:gem)` call here reaches this method again,
    # not the new one, so the call names the new method.
    Kernel.instance_method(:gem).bind_call(self, gem_name, *requirements)
  end
  private :gem

  def Hash(value)
    return {} if value.nil? || (value.is_a?(Array) && value.empty?)

    # rb_check_hash_type: to_hash must give a Hash.
    converted = Hash.try_convert(value)
    return converted if converted

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
    Primitive.zr_exit_now(exit_status(status))
  end

  def !~(other) = !(self =~ other)

  # The same call as IO.select, which Kernel also has.
  def select(*) = IO.select(*)

  private :putc, :pp, :Hash, :exit!, :select
  # pp is Kernel's private method alone, as CRuby's prelude defines it:
  # no module function.
  module_function :putc, :Hash, :exit!, :select
end

class Module
  def set_temporary_name(name)
    if name.nil?
      Primitive.zr_mod_set_temporary_name(self, nil)
      return self
    end
    name = name.to_str
    raise ArgumentError, +"empty class/module name" if name.empty?
    # is_constant_path: constant names joined by `::`, maybe with a
    # leading `::`; an empty part or a trailing `::` is not one.
    parts = name.delete_prefix("::").split("::", -1)
    raise ArgumentError, +"the temporary name must not be a constant path to avoid confusion" if parts.all? { |part| constant_name?(part) }
    raise RuntimeError, +"can't change permanent name" unless Primitive.zr_mod_set_temporary_name(self, -name)

    self
  end
end

class Module
  private

  def constant_name?(part)
    Primitive.attr! :hidden
    !part.empty? && part[0].between?("A", "Z") && part.chars.all? { |c| c.between?("A", "Z") || c.between?("a", "z") || c.between?("0", "9") || c == +"_" }
  end
end

class Class
  def attached_object
    object = Primitive.zr_mod_attached(self)
    raise TypeError, "'#{inspect}' is not a singleton class" if object.nil?

    object
  end
end

module Kernel
  # chomp, chop, sub and gsub on the caller's `$_`, which ruby.c defines
  # only for `ruby -n` and `ruby -p`: such a program's prelude calls
  # Kernel.line_methods, which copies them in as private methods.
  module LineMethods
    def chomp(*args) = Primitive.zr_lastline_set(LineMethods.uscore.chomp(*args))

    def chop = Primitive.zr_lastline_set(LineMethods.uscore.chop)

    def sub(*args, &block) = Primitive.zr_lastline_set(LineMethods.uscore.sub(*args, &block))

    def gsub(*args, &block) = Primitive.zr_lastline_set(LineMethods.uscore.gsub(*args, &block))

    # uscore_get: `$_`, which must be a String.
    def self.uscore
      line = Primitive.zr_lastline_get
      raise TypeError, "$_ value need to be String (#{line.nil? ? "nil" : line.class} given)" unless line.is_a?(String)

      line
    end
  end
  private_constant :LineMethods

  def self.line_methods
    Primitive.attr! :hidden
    %i[chomp chop sub gsub].each do |name|
      # rb_define_global_function: a private method and Kernel.name.
      define_method(name, LineMethods.instance_method(name))
      module_function name
    end
  end
end
