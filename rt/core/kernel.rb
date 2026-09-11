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
  # name, anything else by its class.
  def conversion_name(value)
    Primitive.attr! :hidden
    value.nil? || value == true || value == false ? value.inspect : value.class.name
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

  # A literal name is resolved when the program is compiled; a computed
  # one has no file to answer it yet.
  def require(name) = Primitive.zr_unimplemented("require with a computed name")
  def require_relative(name) = Primitive.zr_unimplemented("require_relative with a computed name")
  def load(name, wrap = false) = Primitive.zr_unimplemented("load with a computed name")

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

  def Integer(value, base = nil, exception: true)
    if value.is_a?(String)
      n = parse_integer(value, base || 0)
      return n if n || !exception

      raise ArgumentError, "invalid value for Integer(): #{value.inspect}"
    end
    raise ArgumentError, "base specified for non string value" if base
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

    raise TypeError, "can't convert #{value.class} into String"
  end

  def Array(value)
    return [] if value.nil?
    return value if value.is_a?(Array)
    return value.to_ary if value.respond_to?(:to_ary)
    return value.to_a if value.respond_to?(:to_a)

    [value]
  end


  # The current thread sleeps `duration` seconds, or until `wakeup`
  # without one; the answer is the seconds slept, rounded.
  def sleep(duration = nil)
    unless duration.nil?
      raise TypeError, "can't convert #{duration.class} into time interval" unless duration.is_a?(Numeric)
      raise ArgumentError, "time interval must not be negative" if duration < 0
    end
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
    deadline = duration.nil? ? nil : started + (duration * 1e9).to_i
    Thread.current.send(:wait, deadline, false)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) - started) / 1e9).round
  end

  def itself = self

  # Every message on its own line, the first carrying the position
  # `uplevel` frames above this call. A category the program turned off
  # says nothing at all.
  def warn(*msgs, uplevel: nil, category: nil)
    Primitive.attr! :ruby
    return nil if msgs.empty?
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
    raise TypeError, "no implicit conversion of #{value.class} into Integer" unless value.respond_to?(:to_int)

    value.to_int
  end

  def exit_status(status)
    Primitive.attr! :hidden
    return 0 if status == true
    return 1 if status == false
    return status if status.is_a?(Integer)
    raise TypeError, "no implicit conversion from nil to integer" if status.nil?

    raise TypeError, "no implicit conversion of #{status.class} into Integer"
  end

  # The strict form: whitespace around, a sign, a `0x`, `0b`, `0o` or
  # `0d` prefix, digits with single underscores between them; nil on
  # anything else.
  def parse_integer(text, base)
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

module Kernel
  private :Integer, :String, :Array, :sleep, :warn, :catch, :throw, :loop, :exit, :abort, :at_exit, :require, :require_relative, :load
end

# A `ruby2_keywords` method keeps the keywords it took into its rest
# flagged, so a `*rest` call passes them on as keywords.
module Kernel
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

  # `pp` prints inspect on a line each, as `p` does; a wide inspect
  # would wrap, which is not written yet.
  def pp(*objects)
    objects.each do |object|
      text = object.inspect
      Primitive.zr_unimplemented("pp of an object whose inspect is 80 columns or wider") if text.size >= 80
      puts text
    end
    objects.size <= 1 ? objects[0] : objects
  end

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

  def public_method(name)
    m = method(name)
    raise NameError.new("method '#{name}' for class '#{self.class}' is private", name) if self.class.private_method_defined?(name)
    raise NameError.new("method '#{name}' for class '#{self.class}' is protected", name) if self.class.protected_method_defined?(name)

    m
  end

  def singleton_method(name)
    raise NameError.new("undefined singleton method '#{name}' for '#{inspect}'", name) unless singleton_methods.include?(name.to_sym)

    method(name)
  end

  def exit!(status = false)
    Primitive.zr_exit_now(status == true ? 0 : (status == false ? 1 : status))
  end

  def !~(other) = !(self =~ other)

  private :putc, :pp, :Hash, :exit!
  module_function :putc, :pp, :Hash, :exit!
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
    raise RuntimeError, "can't change permanent name" unless Primitive.zr_mod_set_temporary_name(self, name)

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
