# Kernel's conversion and convenience methods.
module Kernel
  def <=>(other) = equal?(other) || self == other ? 0 : nil

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

    raise TypeError, "can't convert #{value.class} into Integer"
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

  def rand(*args) = Primitive.zr_unimplemented("Kernel#rand")

  def sleep(*args) = Primitive.zr_unimplemented("Kernel#sleep")

  def warn(*messages, uplevel: nil, category: nil)
    Primitive.zr_unimplemented("Kernel#warn with uplevel") if uplevel
    messages.flatten.each { |m| Primitive.zr_warn_line(m.to_s) }
    nil
  end

  private

  # The strict form: whitespace around, a sign, a `0x`, `0b`, `0o` or
  # `0d` prefix, digits with single underscores between them; nil on
  # anything else.
  def parse_integer(text, base)
    Primitive.zr_str_ascii_check(text)
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

class FalseClass
  def &(other) = false
  def |(other) = other ? true : false
  def ^(other) = other ? true : false
end

module Kernel
  def catch(tag = Object.new, &block)
    raise LocalJumpError, "no block given (yield)" unless block

    Primitive.zr_catch(tag, block)
  end

  def throw(tag, value = nil)
    unless Primitive.zr_catch_tag_p(tag)
      raise UncaughtThrowError.new(tag, value, "uncaught throw #{tag.inspect}")
    end

    Primitive.zr_throw(tag, value)
  end
end

module Kernel
  private :Integer, :String, :Array, :rand, :sleep, :warn, :catch, :throw
end

module Kernel
  def ruby2_keywords(*names) = Primitive.zr_unimplemented("ruby2_keywords")
  private :ruby2_keywords
end

class Module
  def ruby2_keywords(*names) = Primitive.zr_unimplemented("ruby2_keywords")
  private :ruby2_keywords
end
