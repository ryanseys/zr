# The constants and globals that describe the running program.
RUBY_VERSION = "4.0.6"
RUBY_ENGINE = "ruby"
RUBY_ENGINE_VERSION = "4.0.6"
RUBY_PLATFORM = "arm64-darwin23"
RUBY_PATCHLEVEL = 0
RUBY_RELEASE_DATE = "2026-07-14"
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

# The process environment, read and written through libSystem.
ENV = Object.new

class << ENV
  include Enumerable

  def [](name)
    Primitive.zr_environment_get(variable_name(name))
  end

  def fetch(name, *default)
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

  def delete(name)
    value = self[name]
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
  def key(value) = to_h.key(value)
  def values_at(*names) = names.map { |n| self[n] }
  def slice(*names) = to_h.slice(*names)
  def select(&block) = to_h.select(&block)
  alias filter select
  def reject(&block) = to_h.reject(&block)
  def update(other) = other.each { |k, v| self[k] = v } && self
  alias merge! update
  def inspect = to_h.inspect
  def to_s = "ENV"

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

    path = file.start_with?("/") ? file : "#{Primitive.zr_getcwd}/#{file}"
    parts = path.split("/").reject { |part| part.empty? || part == "." }
    parts.pop
    "/" + parts.join("/")
  end
end

# CRuby's module functions of Kernel: the same methods, public on
# Kernel itself.
module Kernel
  module_function :Array, :Integer, :String, :__callee__, :__dir__, :__method__, :abort, :at_exit, :block_given?, :caller,
                  :caller_locations, :catch, :exit, :fail, :format, :lambda, :loop, :p, :print, :printf, :proc, :puts,
                  :raise, :sleep, :sprintf, :throw, :warn
end
