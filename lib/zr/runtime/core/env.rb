# frozen_string_literal: true

# The globals that describe the running program. The constants that name
# its ruby (RUBY_VERSION and the rest) come just before, from the
# generated core/ruby_version.rb.
# rubygems loads rbconfig before the program starts, and rbconfig says
# this ruby is not a cross-compiling one.
CROSS_COMPILING = nil

# ruby gives the arguments the locale's encoding.
ARGV = Primitive.zr_program_args.each { |arg| arg.force_encoding(Encoding.find("locale")) }
$* = ARGV
$; = nil
$, = nil
$/ = String.default_rs
$\ = nil
$VERBOSE = false
$DEBUG = false
$-w = false
$-W = 1
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
# already ends in `.rb` is looked for as it is. The library that the
# program was compiled with counts as on the path, as require finds it
# there; a port of a C extension is the `.so` kind, under the name that
# ruby's own extension has.
def $LOAD_PATH.resolve_feature_path(feature)
  name = String.try_convert(feature)
  raise TypeError, no_implicit_conversion(feature, "String") if name.nil?

  path = Kernel.send(:search, name.end_with?(".rb") ? name : "#{name}.rb")
  unless path
    return nil if name.end_with?(".rb")

    native = map { |dir| File.expand_path("#{name}.bundle", dir.to_s) }.find { |file| Primitive.zr_path_kind(file) == 2 }
    return native && [:so, File.realpath(native)]
  end
  ext = Primitive.zr_load_names(3)
  return [:so, "#{path.delete_suffix('.rb')}.bundle"] if !name.end_with?(".rb") && path.start_with?("#{ext}/")

  [:rb, path]
end
# What ruby loads before the program, spelled as ruby records it. IO's
# init provides io/wait, whose methods are IO's own.
$LOADED_FEATURES = %w[enumerator.so monitor.so thread.rb fiber.so rational.so complex.so pathname.so ruby2_keywords.rb set.rb
                      io/wait.rb io/wait.so]

# The process environment, read and written through libSystem. It is one
# for every ractor, so it is shareable, and it takes no instance variable.
ENV = Primitive.zr_set_shareable_m(Object.new)

class << ENV
  include Enumerable

  # env_str_new: what the environment gives is frozen.
  def [](name)
    value = Primitive.zr_environment_get(variable_name(name))
    value && external(value)
  end

  def fetch(*args)
    raise ArgumentError, wrong_arity(args.size, 1..2) unless args.size.between?(1, 2)

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
    # The name converts once, as env_delete_m converts it.
    name = variable_name(name)
    value = self[name]
    return yield(name) if value.nil? && block_given?

    self[name] = nil
    value
  end

  def key?(name) = !self[name].nil?
  alias has_key? key?
  alias include? key?
  alias member? key?

  # ENV's walks run in C in CRuby, so a block runs under the method's
  # frame alone. env_each_pair and its kin read every pair first.
  def each
    return to_enum(:each) { size } unless block_given?

    Primitive.zr_hash_foreach(to_h) { |k, v| yield k, v }
    self
  end
  alias each_pair each

  def each_key
    return to_enum(:each_key) { size } unless block_given?

    Primitive.zr_hash_foreach(to_h) { |k, _| yield k }
    self
  end

  def each_value
    return to_enum(:each_value) { size } unless block_given?

    Primitive.zr_hash_foreach(to_h) { |_, v| yield v }
    self
  end

  def to_h(&block)
    hash = Primitive.zr_environment_list.to_h do |entry|
      i = entry.index("=") || entry.bytesize
      [external(entry[0, i]), external(entry[(i + 1)..] || +"")]
    end
    # rb_hash_to_h_block, in C.
    block ? hash.send(:mapped_to_h, &block) : hash
  end
  alias to_hash to_h

  def keys = to_h.keys
  def values = to_h.values
  def size = to_h.size
  alias length size
  def empty? = to_h.empty?
  # env_key compares the value's bytes, so any String is asked for.
  def key(value) = to_h.key(Primitive.zr_str_operand(value))
  def values_at(*names) = names.map { |n| self[n] }

  # env_fetch_values (ruby 4.1): each name's value as a fetch of one
  # argument gives it: the block's value for a name that is not set, else
  # a KeyError.
  def fetch_values(*names)
    names.map do |name|
      value = self[name]
      next value if value
      next yield(name) if block_given?

      raise KeyError.new("key not found: #{name.inspect}", receiver: self, key: name)
    end
  end

  # env_to_a: ENV's own, not Enumerable's through each.
  def to_a = to_h.to_a

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

    # The name is a new String, not the frozen one that ENV hands out.
    pair = to_h.find { |_, held| held == value }
    pair && [+pair[0], value]
  end

  # Without a block, an Enumerator that reads the variables when it runs.
  def select
    return to_enum(:select) { size } unless block_given?

    taken = {}
    each_variable { |name, value| taken[name] = value if yield(name, value) }
    taken
  end

  def filter
    return to_enum(:filter) { size } unless block_given?

    taken = {}
    each_variable { |name, value| taken[name] = value if yield(name, value) }
    taken
  end

  def reject
    return to_enum(:reject) { size } unless block_given?

    taken = {}
    each_variable { |name, value| taken[name] = value unless yield(name, value) }
    taken
  end

  # The names as env_keys reads them, then each value read again at its
  # turn, as env_select, env_reject and the bang forms walk them: a
  # variable that the block removed is skipped.
  def each_variable
    Primitive.attr! :hidden
    names = keys
    i = 0
    while i < names.size
      name = names[i]
      value = self[name]
      yield name, value unless value.nil?
      i += 1
    end
  end

  # env_update walks the arguments and each Hash's pairs in C, so the
  # block runs under this frame alone.
  def update(*others)
    i = 0
    while i < others.size
      other = Primitive.zr_convert_type(others[i], Hash, :to_hash)
      Primitive.zr_hash_foreach(other) do |k, v|
        k = variable_name(k)
        self[k] = block_given? && key?(k) ? yield(k, self[k], v) : v
      end
      i += 1
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

  def reject!(&block)
    return to_enum(:reject!) { size } unless block

    remove_where(false, &block) ? self : nil
  end

  def delete_if(&block)
    return to_enum(:delete_if) { size } unless block

    remove_where(false, &block)
    self
  end

  def select!(&block)
    return to_enum(:select!) { size } unless block

    remove_where(true, &block) ? self : nil
  end
  alias filter! select!

  def keep_if(&block)
    return to_enum(:keep_if) { size } unless block

    remove_where(true, &block)
    self
  end

  # env_reject_bang and env_select_bang: each variable for which the
  # block's answer is not `kept` goes. Whether any went.
  def remove_where(kept)
    Primitive.attr! :hidden
    removed = false
    each_variable do |name, value|
      next if (yield(name, value) ? true : false) == kept

      delete(name)
      removed = true
    end
    removed
  end

  # The names that the Hash gives are set, each checked as it is. Every
  # other name is removed, as env_replace leaves the environment.
  def replace(given)
    hash = Primitive.zr_convert_type(given, Hash, :to_hash)
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
  # env_clone: the freeze: keyword is checked first.
  def clone(freeze: nil)
    raise ArgumentError, "unexpected value for freeze: #{conversion_name(freeze)}" unless freeze.nil? || freeze == true || freeze == false

    raise TypeError, +"Cannot clone ENV, use ENV.to_h to get a copy of ENV as a hash"
  end
  def freeze = raise(TypeError, +"cannot freeze ENV")

  private

  # A name or a value as the environment stores it: a String with no NUL
  # byte, because the C environment cannot contain one.
  # env_str_new: the locale's encoding, transcoded to
  # Encoding.default_internal when that is set, and frozen.
  def external(text) = Dir.send(:external_name, text, Encoding.find("locale")).freeze

  def variable_name(value, role = +"name")
    unless value.is_a?(String)
      raise TypeError, no_implicit_conversion(value, "String") unless value.respond_to?(:to_str)

      value = value.to_str
    end
    unless value.encoding.ascii_compatible?
      raise ArgumentError, "bad environment variable #{role}: ASCII incompatible encoding: #{value.encoding}"
    end
    raise ArgumentError, "bad environment variable #{role}: contains null byte" if value.include?("\0")

    value
  end
end

# `zr run` names the zr that runs the program in ZR_RUBY, for RbConfig.ruby
# (ext/rbconfig.rb). The program's environment does not have it, as a ruby
# program's environment has no such variable.
Primitive.zr_hidden_set(ENV, :__zr_ruby__, Primitive.zr_environment_get(+"ZR_RUBY"))
Primitive.zr_environment_set(+"ZR_RUBY", nil)

# The install prefix of RbConfig and $LOAD_PATH, fixed at start as ruby's
# is: ZR_PREFIX when the user gives one, else ZR_HOME, the home of the zr
# that runs the program (its vendored ruby tree, laid out as an installed
# ruby's prefix, as JRuby and TruffleRuby use their home), else ~/.zr.
# RbConfig::TOPDIR is the prefix only when its library directory exists
# (ext/rbconfig.rb), so a program that no zr ran has none, as a ruby that
# is not installed has none. Like ZR_RUBY, ZR_HOME leaves the program's
# environment.
Primitive.zr_hidden_set(ENV, :__zr_home__, Primitive.zr_environment_get(+"ZR_HOME"))
Primitive.zr_environment_set(+"ZR_HOME", nil)
Primitive.zr_hidden_set(ENV, :__zr_home__, nil) if Primitive.zr_hidden_get(ENV, :__zr_home__)&.empty?
Primitive.zr_hidden_set(
  ENV, :__zr_prefix__,
  Primitive.zr_environment_get(+"ZR_PREFIX") || Primitive.zr_hidden_get(ENV, :__zr_home__) ||
    "#{Primitive.zr_environment_get(+"HOME") || "/tmp"}/.zr"
)

# Paths that the system gives take the locale's encoding from the start.
Encoding.send(:follow_paths) unless Encoding.locale_charmap == +"UTF-8"

module Kernel
  # Each file's directory once asked, from the working directory as the
  # program started. ruby fixes a file's real path as it loads, so a later
  # chdir does not move __dir__.
  FILE_DIRS = {}
  private_constant :FILE_DIRS

  # The directory of the caller's file, absolute.
  def __dir__
    file = Primitive.zr_caller_file
    # An eval with no file has no directory (rb_f_dir).
    return nil if file.nil? || file.start_with?("(eval at ")
    return +"." if file == +"-e"
    # An eval given a file name has that name as its path and no real
    # path, so rb_current_realfilepath gives the name as it is.
    return File.dirname(file) if Primitive.zr_caller_eval_p

    # The directory is in the encoding of the file's name: the main
    # file's is a path from the command line (`zr_meta_file`).
    dir = Kernel.send(:file_dir, file)
    dir.encoding == file.encoding ? dir : dir.dup.force_encoding(file.encoding)
  end

  # The real directory of `file`, a name from the starting directory.
  def self.file_dir(file)
    Primitive.attr! :hidden
    start = Primitive.zr_start_dir
    FILE_DIRS[file] ||= begin
      path = File.expand_path(file, start.is_a?(String) ? start : "/")
      File.dirname(File.realpath(path))
    rescue SystemCallError
      File.dirname(path)
    end
  end
end

# ruby_init_loadpath: the site, vendor and library directories of the
# install layout (lib/zr/runtime/ext/rbconfig.rb), in ruby's order. None
# of them needs to exist.
$LOAD_PATH.concat(
  lambda do
    lib = "#{Primitive.zr_hidden_get(ENV, :__zr_prefix__)}/lib/ruby"
    arch = RUBY_PLATFORM
    version = Primitive.zr_hidden_get(Kernel, :__zr_ruby_lib_version__)
    %W[site_ruby/#{version} site_ruby/#{version}/#{arch} site_ruby
       vendor_ruby/#{version} vendor_ruby/#{version}/#{arch} vendor_ruby
       #{version} #{version}/#{arch}].map do |dir|
      # ruby_init_loadpath marks each default entry with itself, which
      # rubygems reads to put gem paths in front of them.
      path = "#{lib}/#{dir}"
      path.instance_variable_set(:@gem_prelude_index, path)
      path
    end
  end.call
)

# CRuby's module functions of Kernel: the same methods, public on
# Kernel itself.
module Kernel
  module_function :Array, :Float, :Hash, :Integer, :String, :__callee__, :__dir__, :__method__, :abort, :at_exit,
                  :autoload, :autoload?, :autoload_relative, :binding, :block_given?, :caller, :caller_locations,
                  :catch, :eval, :exec, :exit, :exit!, :fail, :format, :gets, :global_variables, :iterator?, :lambda,
                  :load, :local_variables, :loop, :open, :p, :print, :printf, :proc, :putc, :puts, :raise, :readline,
                  :readlines, :require_relative, :sleep, :spawn, :sprintf, :system, :throw, :trap, :warn, :`
end
