# frozen_string_literal: true

# The constants and globals that describe the running program.
RUBY_VERSION = "4.0.7"
RUBY_ENGINE = "ruby"
RUBY_ENGINE_VERSION = "4.0.7"
RUBY_PLATFORM = Primitive.zr_os_ruby_platform.freeze
RUBY_PATCHLEVEL = 0
RUBY_RELEASE_DATE = "2026-09-15"
RUBY_REVISION = "229531a6cfbf07e3caef30dbac24a2a3f3fed482"
RUBY_COPYRIGHT = "ruby - Copyright (C) 1993-2026 Yukihiro Matsumoto"
RUBY_DESCRIPTION = "ruby 4.0.7 (2026-09-15 revision 229531a6cf) +PRISM [#{RUBY_PLATFORM}]".freeze
# rubygems loads rbconfig before the program starts, and rbconfig says
# this ruby is not a cross-compiling one.
CROSS_COMPILING = nil

ARGV = Primitive.zr_program_args
$* = ARGV
$; = nil
$, = nil
$/ = String.default_rs
$\ = nil
$VERBOSE = false
$DEBUG = false
$-w = false
$FILENAME = +"-"
$? = nil
$-a = false
$-l = false
$-p = false
$-i = nil
$$ = Primitive.zr_process_id
$LOAD_PATH = []

# The kind of file that a require of `feature` would read, and its real
# path, or nil when no directory on the path contains it. A name that
# already ends in `.rb` is looked for as it is.
def $LOAD_PATH.resolve_feature_path(feature)
  name = String.try_convert(feature)
  raise TypeError, "no implicit conversion of #{conversion_name(feature)} into String" if name.nil?

  suffixes = name.end_with?(".rb") ? [["", :rb]] : [[".rb", :rb], [".bundle", :so]]
  each do |dir|
    suffixes.each do |suffix, kind|
      path = File.expand_path("#{name}#{suffix}", dir.to_s)
      return [kind, File.realpath(path)] if Primitive.zr_path_kind(path) == 2
    end
  end
  nil
end
# What ruby loads before the program, spelled as ruby records it.
$LOADED_FEATURES = %w[enumerator.so thread.rb fiber.so rational.so complex.so pathname.so ruby2_keywords.rb set.rb]

# The process environment, read and written through libSystem.
ENV = Object.new

class << ENV
  include Enumerable

  # env_str_new: what the environment gives is frozen.
  def [](name)
    Primitive.zr_environment_get(variable_name(name))&.freeze
  end

  def fetch(*args)
    raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 1..2)" unless args.size.between?(1, 2)

    name, *default = args

    Primitive.zr_warn_here_m("block supersedes default value argument") if block_given? && !default.empty?
    value = self[name]
    return value if value
    return yield(name) if block_given?
    return default[0] unless default.empty?

    raise KeyError.new("key not found: #{name.inspect}", receiver: self, key: name)
  end

  # ruby_setenv: a name that setenv(3) refuses raises its error, and an
  # unsetenv(3) that fails is quiet.
  def []=(name, value)
    name = variable_name(name)
    result = Primitive.zr_environment_set(name, value.nil? ? nil : variable_name(value, "value"))
    raise SystemCallError.new("setenv(#{name})", -result) if result.is_a?(Integer)

    value
  end
  alias store []=

  # The value removed; a block gives the value for a name that was not set.
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
    hash = Primitive.zr_environment_list.to_h do |entry|
      i = entry.index("=") || entry.bytesize
      [entry[0, i].freeze, (entry[i + 1..] || +"").freeze]
    end
    block ? hash.to_h(&block) : hash
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
    taken = {}
    names.each do |name|
      value = self[name]
      taken[name] = value unless value.nil?
    end
    taken
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
    others.each do |given|
      other = Hash.try_convert(given) or raise TypeError, "no implicit conversion of #{conversion_name(given)} into Hash"
      other.each do |k, v|
        k = variable_name(k)
        self[k] = block_given? && key?(k) ? yield(k, self[k], v) : v
      end
    end
    self
  end
  alias merge! update

  def clear
    keys.each { |name| delete(name) }
    self
  end

  # A value that is not String-like matches nothing: nil, as env_has_value
  # returns.
  def value?(value)
    value = value.to_str if !value.is_a?(String) && value.respond_to?(:to_str)
    return nil unless value.is_a?(String)

    values.include?(value)
  end
  alias has_value? value?

  def invert = to_h.invert
  def rehash = nil
  def except(*names) = to_h.except(*names)

  def reject!
    return to_enum(:reject!) { size } unless block_given?

    deleted = false
    to_h.each do |name, value|
      next unless yield(name, value)

      delete(name)
      deleted = true
    end
    deleted ? self : nil
  end

  def delete_if(&block)
    return to_enum(:delete_if) { size } unless block

    reject!(&block)
    self
  end

  def select!
    return to_enum(:select!) { size } unless block_given?

    deleted = false
    to_h.each do |name, value|
      next if yield(name, value)

      delete(name)
      deleted = true
    end
    deleted ? self : nil
  end
  alias filter! select!

  def keep_if(&block)
    return to_enum(:keep_if) { size } unless block

    select!(&block)
    self
  end

  # The names that the Hash gives are set, each checked as it is. Every
  # other name is removed, as env_replace leaves the environment.
  def replace(given)
    hash = Hash.try_convert(given) or raise TypeError, "no implicit conversion of #{conversion_name(given)} into Hash"
    names = keys
    hash.each do |name, value|
      self[name] = value
      names.delete(variable_name(name))
    end
    names.each { |name| delete(name) }
    self
  end

  def shift
    pair = to_h.first
    delete(pair[0]) if pair
    pair
  end

  def inspect = to_h.inspect
  def to_s = +"ENV"

  # ENV is the process environment itself, so there is nothing to copy
  # or to hold still.
  def dup = raise(TypeError, +"Cannot dup ENV, use ENV.to_h to get a copy of ENV as a hash")
  def clone(freeze: nil) = raise(TypeError, +"Cannot clone ENV, use ENV.to_h to get a copy of ENV as a hash")
  def freeze = raise(TypeError, +"cannot freeze ENV")

  private

  # A name or a value as the environment stores it: a String with no NUL
  # byte, because the C environment cannot contain one.
  def variable_name(value, role = +"name")
    unless value.is_a?(String)
      raise TypeError, "no implicit conversion of #{value.nil? ? 'nil' : value.class} into String" unless value.respond_to?(:to_str)

      value = value.to_str
    end
    unless value.encoding.ascii_compatible?
      raise ArgumentError, "bad environment variable #{role}: ASCII incompatible encoding: #{value.encoding}"
    end
    raise ArgumentError, "bad environment variable #{role}: contains null byte" if value.include?("\0")

    value
  end
end

module Kernel
  # The directory of the caller's file, absolute.
  def __dir__
    file = Primitive.zr_caller_file
    # An eval with no file has no directory (rb_f_dir).
    return nil if file.nil? || file.start_with?("(eval at ")
    return +"." if file == +"-e"

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

  # rubygems, which ruby loads as it starts, puts its own Ruby method in
  # Kernel#require, and Kernel.require stays the C one.
  def require(path)
    Primitive.attr! :ruby
    Kernel.required(path)
  end
  private :require
end
