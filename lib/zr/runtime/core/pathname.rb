# frozen_string_literal: true

# The Pathname class, which ruby 4.0 includes as a builtin: it works
# without a require, and `require "pathname"` adds the Find and rmtree
# part that ruby keeps on the load path.
#
# This is ruby 4.0.7's pathname_builtin.rb, with `<=>` and `sub`, which
# its pathname.c writes in C, in Ruby here. A Pathname is only a string:
# it never touches the file system for an operation on the name itself,
# and every operation on the file goes to File, Dir or FileTest.
#
class Pathname
  Primitive.attr! :ivars

  # path_cmp: byte order, with a separator below every other byte.
  def <=>(other)
    return nil unless Pathname === other

    @path.tr("/", "\0") <=> other.path.tr("/", "\0")
  end

  # path_sub: String#sub over the path, the block and all.
  def sub(*args, &block)
    self.class.new(block ? @path.sub(*args, &block) : @path.sub(*args))
  end
end

# The rest is also Ruby in CRuby, and reports its parameters by name.
class Pathname
  Primitive.attr! :ruby
  Primitive.attr! :sends_each
  Primitive.attr! :ivars

  VERSION = "0.4.0"

  # Darwin's file names match case-sensitively as far as File::FNM_SYSCASE
  # says.
  private def same_paths?(a, b) = a == b

  protected def path = @path

  def initialize(path)
    @path = File.path(path).dup
  rescue TypeError => e
    raise e.class, "Pathname.new requires a String, #to_path or #to_str", cause: nil
  end

  def freeze
    super
    @path.freeze
    self
  end

  def ==(other)
    return false unless Pathname === other

    other.path == @path
  end
  alias === ==
  alias eql? ==

  def hash = @path.hash

  def to_s = @path.dup

  alias to_path to_s

  def inspect = "#<#{self.class}:#{@path}>"

  def sub_ext(repl)
    ext = File.extname(@path)
    ext = @path[@path.rindex(ext)..] unless @path.end_with?(ext)
    self.class.new(@path.chomp(ext) + repl)
  end

  # The separator is `/` on every target; written as literals, the
  # patterns compile when first used and not as the runtime boots,
  # where the two interpolated ones cost 0.5 ms of a 9 ms start.
  SEPARATOR_LIST = "/"
  SEPARATOR_PAT = /\//
  ABSOLUTE_PATH = /\A\//
  private_constant :SEPARATOR_LIST, :ABSOLUTE_PATH

  def mkpath(mode: nil)
    path = @path == "/" ? @path : @path.chomp("/")

    stack = []
    until File.directory?(path) || File.dirname(path) == path
      stack.push(path)
      path = File.dirname(path)
    end

    stack.reverse_each do |dir|
      dir = dir == "/" ? dir : dir.chomp("/")
      if mode
        Dir.mkdir(dir, mode)
        File.chmod(mode, dir)
      else
        Dir.mkdir(dir)
      end
    rescue SystemCallError
      raise unless File.directory?(dir)
    end

    self
  end

  def cleanpath(consider_symlink = false)
    consider_symlink ? cleanpath_conservative : cleanpath_aggressive
  end

  def parent = self + ".."

  def mountpoint?
    stat1 = lstat
    stat2 = parent.lstat
    stat1.dev != stat2.dev || stat1.ino == stat2.ino
  rescue Errno::ENOENT
    false
  end

  def root? = chop_basename(@path).nil? && SEPARATOR_PAT.match?(@path)

  def absolute? = ABSOLUTE_PATH.match?(@path)

  def relative? = !absolute?

  def each_filename
    return to_enum(__method__) unless block_given?

    _, names = split_names(@path)
    names.each { |filename| yield filename }
    nil
  end

  def descend
    return to_enum(__method__) unless block_given?

    vs = []
    ascend { |v| vs << v }
    vs.reverse_each { |v| yield v }
    nil
  end

  def ascend
    return to_enum(__method__) unless block_given?

    path = @path
    yield self
    while (r = chop_basename(path))
      path, = r
      break if path.empty?

      yield self.class.new(del_trailing_separator(path))
    end
  end

  def +(other)
    other = Pathname.new(other) unless Pathname === other
    Pathname.new(plus(@path, other.path))
  end
  alias / +

  def join(*args)
    return self if args.empty?

    result = args.pop
    result = Pathname.new(result) unless Pathname === result
    return result if result.absolute?

    args.reverse_each do |arg|
      arg = Pathname.new(arg) unless Pathname === arg
      result = arg + result
      return result if result.absolute?
    end
    self + result
  end

  def children(with_directory = true)
    with_directory = false if @path == "."
    result = []
    Dir.foreach(@path) do |e|
      next if e == "." || e == ".."

      result << (with_directory ? self.class.new(File.join(@path, e)) : self.class.new(e))
    end
    result
  end

  def each_child(with_directory = true, &b) = children(with_directory).each(&b)

  def relative_path_from(base_directory)
    base_directory = Pathname.new(base_directory) unless base_directory.is_a?(Pathname)
    dest_directory = cleanpath.path
    base_directory = base_directory.cleanpath.path
    dest_prefix = dest_directory
    dest_names = []
    while (r = chop_basename(dest_prefix))
      dest_prefix, basename = r
      dest_names.unshift(basename) if basename != "."
    end
    base_prefix = base_directory
    base_names = []
    while (r = chop_basename(base_prefix))
      base_prefix, basename = r
      base_names.unshift(basename) if basename != "."
    end
    unless same_paths?(dest_prefix, base_prefix)
      raise ArgumentError, "different prefix: #{dest_prefix.inspect} and #{base_directory.inspect}"
    end

    while !dest_names.empty? && !base_names.empty? && same_paths?(dest_names.first, base_names.first)
      dest_names.shift
      base_names.shift
    end
    raise ArgumentError, "base_directory has ..: #{base_directory.inspect}" if base_names.include?("..")

    base_names.fill("..")
    relpath_names = base_names + dest_names
    relpath_names.empty? ? Pathname.new(".") : Pathname.new(File.join(*relpath_names))
  end

  private

  def chop_basename(path)
    base = File.basename(path)
    return nil if /\A#{SEPARATOR_PAT}?\z/o.match?(base)

    [path[0, path.rindex(base)], base]
  end

  def split_names(path)
    names = []
    while (r = chop_basename(path))
      path, basename = r
      names.unshift(basename)
    end
    [path, names]
  end

  def prepend_prefix(prefix, relpath)
    if relpath.empty?
      File.dirname(prefix)
    elsif SEPARATOR_PAT.match?(prefix)
      prefix = File.dirname(prefix)
      prefix = File.join(prefix, "") if File.basename(prefix + "a") != "a"
      prefix + relpath
    else
      prefix + relpath
    end
  end

  def cleanpath_aggressive
    path = @path
    names = []
    pre = path
    while (r = chop_basename(pre))
      pre, base = r
      case base
      when "."
      when ".."
        names.unshift(base)
      else
        if names[0] == ".."
          names.shift
        else
          names.unshift(base)
        end
      end
    end
    names.shift while names[0] == ".." if SEPARATOR_PAT.match?(File.basename(pre))
    self.class.new(prepend_prefix(pre, File.join(*names)))
  end

  def has_trailing_separator?(path)
    r = chop_basename(path) or return false
    pre, basename = r
    pre.length + basename.length < path.length
  end

  def add_trailing_separator(path)
    File.basename(path + "a") == "a" ? path : File.join(path, "")
  end

  def del_trailing_separator(path)
    if (r = chop_basename(path))
      pre, basename = r
      pre + basename
    elsif /#{SEPARATOR_PAT}+\z/o =~ path
      $` + File.dirname(path)[/#{SEPARATOR_PAT}*\z/o]
    else
      path
    end
  end

  def cleanpath_conservative
    path = @path
    names = []
    pre = path
    while (r = chop_basename(pre))
      pre, base = r
      names.unshift(base) if base != "."
    end
    names.shift while names[0] == ".." if SEPARATOR_PAT.match?(File.basename(pre))
    return self.class.new(File.dirname(pre)) if names.empty?

    names << "." if names.last != ".." && File.basename(path) == "."
    result = prepend_prefix(pre, File.join(*names))
    if /\A(?:\.|\.\.)\z/ !~ names.last && has_trailing_separator?(path)
      self.class.new(add_trailing_separator(result))
    else
      self.class.new(result)
    end
  end

  def plus(path1, path2)
    prefix2 = path2
    index_list2 = []
    basename_list2 = []
    while (r2 = chop_basename(prefix2))
      prefix2, basename2 = r2
      index_list2.unshift(prefix2.length)
      basename_list2.unshift(basename2)
    end
    return path2 if prefix2 != ""

    prefix1 = path1
    while true
      while !basename_list2.empty? && basename_list2.first == "."
        index_list2.shift
        basename_list2.shift
      end
      break unless (r1 = chop_basename(prefix1))

      prefix1, basename1 = r1
      next if basename1 == "."

      if basename1 == ".." || basename_list2.empty? || basename_list2.first != ".."
        prefix1 += basename1
        break
      end
      index_list2.shift
      basename_list2.shift
    end
    r1 = chop_basename(prefix1)
    if !r1 && (r1 = SEPARATOR_PAT.match?(File.basename(prefix1)))
      while !basename_list2.empty? && basename_list2.first == ".."
        index_list2.shift
        basename_list2.shift
      end
    end
    if basename_list2.empty?
      r1 ? prefix1 : File.dirname(prefix1)
    else
      suffix2 = path2[index_list2.first..]
      r1 ? File.join(prefix1, suffix2) : prefix1 + suffix2
    end
  end
end

# The file's own questions, each one call to File.
class Pathname
  Primitive.attr! :ruby
  Primitive.attr! :ivars

  def each_line(...) = File.foreach(@path, ...)
  def read(...) = File.read(@path, ...)
  def binread(...) = File.binread(@path, ...)
  def readlines(...) = File.readlines(@path, ...)
  def sysopen(...) = File.sysopen(@path, ...)
  def write(...) = File.write(@path, ...)
  def binwrite(...) = File.binwrite(@path, ...)
  def atime = File.atime(@path)
  def birthtime = File.birthtime(@path)
  def ctime = File.ctime(@path)
  def mtime = File.mtime(@path)
  def chmod(mode) = File.chmod(mode, @path)
  def lchmod(mode) = File.lchmod(mode, @path)
  def chown(owner, group) = File.chown(owner, group, @path)
  def lchown(owner, group) = File.lchown(owner, group, @path)
  def fnmatch(pattern, ...) = File.fnmatch(pattern, @path, ...)
  def fnmatch?(pattern, ...) = File.fnmatch?(pattern, @path, ...)
  def ftype = File.ftype(@path)
  def make_link(old) = File.link(old, @path)
  def open(...) = File.open(@path, ...)
  def readlink = self.class.new(File.readlink(@path))
  def rename(to) = File.rename(@path, to)
  def stat = File.stat(@path)
  def lstat = File.lstat(@path)
  def make_symlink(old) = File.symlink(old, @path)
  def truncate(length) = File.truncate(@path, length)
  def utime(atime, mtime) = File.utime(atime, mtime, @path)
  def lutime(atime, mtime) = File.lutime(atime, mtime, @path)
  def basename(...) = self.class.new(File.basename(@path, ...))
  def dirname = self.class.new(File.dirname(@path))
  def extname = File.extname(@path)
  def expand_path(...) = self.class.new(File.expand_path(@path, ...))

  def split
    array = File.split(@path)
    raise TypeError, "wrong argument type nil (expected Array)" unless Array === array

    array.map { |f| self.class.new(f) }
  end

  def realpath(...) = self.class.new(File.realpath(@path, ...))
  def realdirpath(...) = self.class.new(File.realdirpath(@path, ...))
end

# The FileTest questions.
class Pathname
  Primitive.attr! :ruby
  Primitive.attr! :ivars

  def blockdev? = FileTest.blockdev?(@path)
  def chardev? = FileTest.chardev?(@path)
  def empty? = FileTest.directory?(@path) ? Dir.empty?(@path) : File.empty?(@path)
  def executable? = FileTest.executable?(@path)
  def executable_real? = FileTest.executable_real?(@path)
  def exist? = FileTest.exist?(@path)
  def grpowned? = FileTest.grpowned?(@path)
  def directory? = FileTest.directory?(@path)
  def file? = FileTest.file?(@path)
  def pipe? = FileTest.pipe?(@path)
  def socket? = FileTest.socket?(@path)
  def owned? = FileTest.owned?(@path)
  def readable? = FileTest.readable?(@path)
  def world_readable? = File.world_readable?(@path)
  def readable_real? = FileTest.readable_real?(@path)
  def setuid? = FileTest.setuid?(@path)
  def setgid? = FileTest.setgid?(@path)
  def size = FileTest.size(@path)
  def size? = FileTest.size?(@path)
  def sticky? = FileTest.sticky?(@path)
  def symlink? = FileTest.symlink?(@path)
  def writable? = FileTest.writable?(@path)
  def world_writable? = File.world_writable?(@path)
  def writable_real? = FileTest.writable_real?(@path)
  def zero? = FileTest.zero?(@path)
end

# The directory's questions.
class Pathname
  Primitive.attr! :ruby
  Primitive.attr! :ivars

  def self.glob(*args, **kwargs)
    return Dir.glob(*args, **kwargs).map { |f| new(f) } unless block_given?

    Dir.glob(*args, **kwargs) { |f| yield new(f) }
  end

  def glob(*args, **kwargs)
    return Dir.glob(*args, **kwargs, base: @path).map { |f| self + f } unless block_given?

    Dir.glob(*args, **kwargs, base: @path) { |f| yield self + f }
  end

  def self.getwd = new(Dir.getwd)

  class << self
    alias pwd getwd
  end

  def entries = Dir.entries(@path).map { |f| self.class.new(f) }

  def each_entry(&block)
    return to_enum(__method__) unless block_given?

    Dir.foreach(@path) { |f| yield self.class.new(f) }
  end

  def mkdir(...) = Dir.mkdir(@path, ...)
  def rmdir = Dir.rmdir(@path)
  def opendir(&block) = Dir.open(@path, &block)

  def unlink
    Dir.unlink(@path)
  rescue Errno::ENOTDIR
    File.unlink(@path)
  end
  alias delete unlink
end

module Kernel
  def Pathname(path)
    Primitive.attr! :ruby
    return path if Pathname === path

    Pathname.new(path)
  end
  module_function :Pathname
end
