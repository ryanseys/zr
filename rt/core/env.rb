# The constants and globals that describe the running program.
RUBY_VERSION = "4.0.6"
RUBY_ENGINE = "ruby"
RUBY_ENGINE_VERSION = "4.0.6"
RUBY_PLATFORM = "arm64-darwin23"
RUBY_PATCHLEVEL = 0
RUBY_RELEASE_DATE = "2026-07-14"
RUBY_REVISION = "03b6d3f8898a28604fe6cb00eae3226b821168f4"
RUBY_COPYRIGHT = "ruby - Copyright (C) 1993-2026 Yukihiro Matsumoto"
RUBY_DESCRIPTION = "ruby 4.0.6 (2026-07-14 revision 03b6d3f889) +PRISM [arm64-darwin23]"

ARGV = Primitive.zr_program_args
$* = ARGV
$; = nil
$, = nil
$/ = "\n"
$\ = nil
$VERBOSE = false
$DEBUG = false
$-w = false
$FILENAME = "-"
$$ = Primitive.zr_process_id
$LOAD_PATH = []
# What ruby loads before the program, spelled as ruby records it.
$LOADED_FEATURES = %w[enumerator.so thread.rb fiber.so rational.so complex.so pathname.so ruby2_keywords.rb set.rb]

# The process environment, read and written through libSystem.
ENV = Object.new

class << ENV
  include Enumerable

  def [](name)
    Primitive.zr_environment_get(variable_name(name))
  end

  def fetch(name, *default)
    Primitive.zr_warn_here_m("block supersedes default value argument") if block_given? && !default.empty?
    value = self[name]
    return value if value
    return yield(name) if block_given?
    return default[0] unless default.empty?

    raise KeyError.new("key not found: #{name.inspect}", receiver: self, key: name)
  end

  def []=(name, value)
    Primitive.zr_environment_set(variable_name(name), value.nil? ? nil : variable_name(value))
  end
  alias store []=

  # The value removed; a block answers for a name that was not set.
  def delete(name)
    value = self[name]
    return yield(name) if value.nil? && block_given?

    self[name] = nil
    value
  end

  def key?(name) = !self[name].nil?
  alias has_key? key?
  alias include? key?
  alias member? key?

  def each
    return to_enum(:each) { size } unless block_given?

    to_h.each { |k, v| yield k, v }
    self
  end
  alias each_pair each

  def each_key(&block)
    return to_enum(:each_key) { size } unless block

    keys.each(&block)
    self
  end

  def each_value(&block)
    return to_enum(:each_value) { size } unless block

    values.each(&block)
    self
  end

  def to_h(&block)
    pairs = Primitive.zr_environment_list.map do |entry|
      i = entry.index("=") || entry.bytesize
      [entry[0, i], entry[i + 1..] || ""]
    end
    block ? pairs.to_h(&block) : pairs.to_h
  end
  alias to_hash to_h

  def keys = to_h.keys
  def values = to_h.values
  def size = to_h.size
  alias length size
  def empty? = to_h.empty?
  def key(value) = to_h.key(variable_name(value))
  def values_at(*names) = names.map { |n| self[n] }

  # Each name is read as a name, so a Symbol refuses here rather than
  # quietly missing.
  def slice(*names)
    names.each_with_object({}) do |name, taken|
      value = self[name]
      taken[name] = value unless value.nil?
    end
  end

  def assoc(name)
    name = variable_name(name)
    value = self[name]
    value && [name, value]
  end

  # A value that is not a String names nothing, which is not an error.
  def rassoc(value)
    value = value.to_str if !value.is_a?(String) && value.respond_to?(:to_str)
    return nil unless value.is_a?(String)

    pair = to_h.find { |_, held| held == value }
    pair && [pair[0], value]
  end
  def select(&block) = to_h.select(&block)
  alias filter select
  def reject(&block) = to_h.reject(&block)
  def update(*others)
    others.each do |other|
      other.each do |k, v|
        k = variable_name(k)
        self[k] = block_given? && key?(k) ? yield(k, self[k], v) : v
      end
    end
    self
  end
  alias merge! update
  def inspect = to_h.inspect
  def to_s = "ENV"

  # ENV is the process environment itself, so there is nothing to copy
  # or to hold still.
  def dup = raise(TypeError, "Cannot dup ENV, use ENV.to_h to get a copy of ENV as a hash")
  def clone(freeze: nil) = raise(TypeError, "Cannot clone ENV, use ENV.to_h to get a copy of ENV as a hash")
  def freeze = raise(TypeError, "cannot freeze ENV")

  private

  def variable_name(value)
    return value if value.is_a?(String)
    return value.to_str if value.respond_to?(:to_str)

    raise TypeError, "no implicit conversion of #{value.nil? ? 'nil' : value.class} into String"
  end
end

module Kernel
  # The directory of the caller's file, absolute.
  def __dir__
    file = Primitive.zr_caller_file
    return nil if file.nil?
    return "." if file == "-e"

    File.dirname(File.expand_path(file))
  end
end

# CRuby's module functions of Kernel: the same methods, public on
# Kernel itself.
module Kernel
  module_function :Array, :Float, :Hash, :Integer, :String, :__callee__, :__dir__, :__method__, :abort, :at_exit,
                  :autoload, :autoload?, :binding, :block_given?, :caller, :caller_locations, :catch, :eval, :exec,
                  :exit, :exit!, :fail, :format, :gets, :global_variables, :iterator?, :lambda, :load,
                  :local_variables, :loop, :open, :p, :print, :printf, :proc, :putc, :puts, :raise, :readline,
                  :readlines, :require, :require_relative, :sleep, :spawn, :sprintf, :system, :throw, :trap, :warn,
                  :`
end
