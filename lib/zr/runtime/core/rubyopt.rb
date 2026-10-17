# frozen_string_literal: true

# RUBYOPT, as ruby reads it when a program starts (ruby.c's moreswitches
# with envopt): the switches that change how the program runs. They come
# before the switches that the build took from its command line
# (lib/zr/cli/ruby_options.rb), which run later and so win, as the
# command line wins in ruby. The rest are the build's to give: -I, -r,
# -K, --enable and --disable change what the build compiles in. `zr run`
# reads RUBYOPT as it builds, and says so (ZR_RUBYOPT_READ), so the
# program does not read it again.
module Kernel
  # The words of RUBYOPT: -d, -w, -W[level|:category], -v, -E ext[:int],
  # -U, --verbose, --debug, --encoding and --backtrace-limit. A word
  # without its "-" gets one. A level of -w, -W or -v turns on the
  # deprecation warnings, unless a -W:category word sets them.
  def self.rubyopt(text)
    Primitive.attr! :hidden
    categories = {}
    deprecated = nil
    words = text.split
    until words.empty?
      word = words.shift
      word = "-#{word}" unless word.start_with?("-")
      case word
      when "--verbose" then $VERBOSE = deprecated = true
      when "--debug" then $DEBUG = $VERBOSE = true
      when /\A--backtrace-limit=-?\d+\z/ then Primitive.zr_backtrace_limit_set(Integer(word.split("=", 2).last))
      when /\A--(?:external-)?encoding=/ then rubyopt_encodings(word.split("=", 2).last)
      when /\A--internal-encoding=/ then rubyopt_encodings(":#{word.split("=", 2).last}")
      when /\A-W:(?:no-)?\w+\z/ then categories[word.delete_prefix("-W:").delete_prefix("no-").to_sym] = !word.start_with?("-W:no-")
      when /\A--/ then nil
      else
        letters = word[1..]
        until letters.empty?
          letter = letters[0]
          letters = letters[1..]
          case letter
          when "d" then $DEBUG = $VERBOSE = true
          when "w" then $VERBOSE = deprecated = true
          when "v"
            STDOUT.puts RUBY_DESCRIPTION
            $VERBOSE = deprecated = true
          when "W"
            level = letters.empty? ? "2" : letters
            letters = ""
            $VERBOSE = { "0" => nil, "1" => false }.fetch(level, true)
            deprecated = true unless %w[0 1].include?(level)
          when "U" then rubyopt_encodings(":UTF-8")
          when "E"
            rubyopt_encodings(letters.empty? ? words.shift.to_s : letters)
            letters = ""
          else letters = ""
          end
        end
      end
    end
    Warning[:deprecated] = true if deprecated && !categories.key?(:deprecated)
    categories.each { |name, on| Warning[name] = on if Warning.categories.include?(name) }
    nil
  end

  # -E's `external:internal`, either side empty to leave it.
  def self.rubyopt_encodings(names)
    Primitive.attr! :hidden
    external, internal = names.split(":", 2)
    Encoding.send(:store_default, 0, Encoding.find(external)) unless external.to_s.empty?
    return if internal.to_s.empty?

    Encoding.send(:store_default, 1, Encoding.find(internal))
    IO.send(:stdio_encodings)
  end
end

if Primitive.zr_environment_get(+"ZR_RUBYOPT_READ")
  Primitive.zr_environment_set(+"ZR_RUBYOPT_READ", nil)
elsif Primitive.zr_environment_get(+"RUBYOPT")
  Kernel.rubyopt(Primitive.zr_environment_get(+"RUBYOPT"))
end
