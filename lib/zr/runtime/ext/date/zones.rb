# frozen_string_literal: true

require_relative "zonetab"

# The zone names and offsets of a loose parse: ZONES is generated, in
# zonetab.rb.
class Date
  # The seconds a zone name or a numeric offset stands for, or nil. A
  # daylight name adds an hour to the standard one it shrinks to.
  private_class_method def self.zone_to_diff(text)
    Primitive.attr! :hidden
    text = text.to_s
    dst = false
    if (m = /\s(?:(standard|daylight)\s)?time\s*\z/i.match(text)) && m[1]
      dst = m[1].casecmp?("daylight")
      text = text[0, m.begin(0)]
    elsif (m = /\sdst\s*\z/i.match(text))
      dst = true
      text = text[0, m.begin(0)]
    end
    known = ZONES[text.gsub(/\s+/, " ").sub(/\s\z/, "").downcase]
    return known + (dst ? 3600 : 0) if known

    numeric_zone(text)
  end

  # "+09", "-0930", "gmt+9:30" and the fractional hour "+9.5".
  private_class_method def self.numeric_zone(text)
    Primitive.attr! :hidden
    text = text[3..] if text.length > 3 && text.match?(/\A(?:gmt|utc)/i)
    m = /\A([-+])(\d+)(.*)\z/m.match(text) or return nil

    sign = m[1] == "-" ? -1 : 1
    digits = m[2]
    rest = m[3]
    if rest.start_with?(":")
      parts = rest.split(":", -1)
      hour = digits.to_i
      return nil unless (0..23).cover?(hour)

      min = parts[1].to_i
      return nil unless (0..59).cover?(min)

      sec = parts[2].to_i
      return nil unless (0..59).cover?(sec)

      sign * ((hour * 3600) + (min * 60) + sec)
    elsif rest.start_with?(",", ".")
      fractional_zone(sign, digits.to_i, rest[1..])
    elsif digits.length > 2
      odd = digits.length % 2
      hour = digits[0, 2 - odd].to_i
      min = digits[2 - odd, 2].to_i
      sec = digits[4 - odd, 2].to_i
      sign * ((hour * 3600) + (min * 60) + sec)
    else
      sign * digits.to_i * 3600
    end
  end

  # A fraction of an hour, rounded half to even at seven digits, which
  # is finer than a millisecond.
  private_class_method def self.fractional_zone(sign, hour, digits)
    Primitive.attr! :hidden
    return nil unless (0..23).cover?(hour)

    kept = digits[0, 7]
    value = kept.to_i
    value += 1 if digits[7]&.between?((value.even? ? "5" : "6"), "9")
    value *= 36
    hour *= sign
    value *= sign
    return (value * (kept.length == 1 ? 10 : 1)) + (hour * 3600) if kept.length <= 2

    offset = Rational(value, 10**(kept.length - 2)) + (hour * 3600)
    offset.denominator == 1 ? offset.numerator : offset
  end
end
