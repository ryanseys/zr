# frozen_string_literal: true

# The Pathname class, which ruby 4.0 carries as a builtin: it stands
# without a require, and `require "pathname"` adds the Find and glob half
# ruby keeps on the load path.
#
# A Pathname is a string and nothing more: it never touches the file
# system to answer a question about the name itself, and every question
# about the file goes straight to File, Dir or IO.
class Pathname
  SEPARATOR = "/"
  SEPARATOR_PAT = %r{/}
  TO_PATH = :to_path

  attr_reader :path
  protected :path

  def initialize(path)
    path = path.to_path if path.respond_to?(:to_path)
    path = path.to_str unless path.is_a?(String)
    raise ArgumentError, "path name contains null byte" if path.include?("\0")

    @path = path.dup
    @path.freeze if frozen?
  end

  def initialize_copy(other)
    super
    @path = other.to_s.dup
    self
  end

  def freeze
    @path.freeze
    super
  end

  def to_s = @path.dup

  alias to_path to_s

  def inspect = "#<Pathname:#{@path}>"

  def hash = @path.hash

  def ==(other) = other.is_a?(Pathname) && other.to_s == @path

  alias === ==
  alias eql? ==

  def <=>(other)
    return nil unless other.is_a?(Pathname)

    left = @path.tr("/", "\0")
    right = other.to_s.tr("/", "\0")
    left <=> right
  end

  include Comparable

  def sub(*args, &block)
    self.class.new(@path.sub(*args, &block))
  end

  def sub_ext(ext)
    self.class.new(@path.chomp(File.extname(@path)) + ext)
  end

  def +(other)
    other = self.class.new(other) unless other.is_a?(Pathname)
    self.class.new(plus(@path, other.to_s))
  end

  alias / +

  # `a + b`: b wins when it is absolute, and `..` in b eats a trailing
  # name of a, as ruby's own does without asking the file system.
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
    loop do
      while !basename_list2.empty? && basename_list2.first == "."
        index_list2.shift
        basename_list2.shift
      end
      break unless (r1 = chop_basename(prefix1))

      prefix1, basename1 = r1
      next if basename1 == "."

      if basename1 == ".." || basename_list2.empty? || basename_list2.first != ".."
        prefix1 = prefix1 + basename1
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
    unless basename_list2.empty?
      suffix2 = path2[index_list2.first..]
      return r1 ? File.join(prefix1, suffix2) : prefix1 + suffix2
    end
    r1 ? prefix1 : File.dirname(prefix1)
  end
  private :plus

  # `[prefix, basename]`, or nil where the path holds no basename at all
  # (the root, or an empty path).
  def chop_basename(path)
    base = File.basename(path)
    return nil if /\A#{SEPARATOR_PAT}?\z/o.match?(base)

    [path[0, path.rindex(base)], base]
  end
  private :chop_basename

  def absolute? = !relative?

  def relative?
    path = @path
    while (r = chop_basename(path))
      path = r.first
    end
    path == ""
  end

  def root?
    %r{\A/+\z}.match?(@path)
  end

  def parent = self + ".."

  def cleanpath(consider_symlink: false)
    consider_symlink ? cleanpath_conservative : cleanpath_aggressive
  end

  def each_filename(&block)
    return to_enum(:each_filename) unless block

    _prefix, names = split_names(@path)
    names.each(&block)
    nil
  end

  # Every prefix of the path, longest first.
  def descend(&block)
    return to_enum(:descend) unless block

    vs = []
    ascend { |v| vs << v }
    vs.reverse_each(&block)
    nil
  end

  def ascend(&block)
    return to_enum(:ascend) unless block

    path = @path
    yield self
    while (r = chop_basename(path))
      path = r.first
      break if path.empty?

      yield self.class.new(del_trailing_separator(path))
    end
  end

  def join(*args)
    return self if args.empty?

    result = args.pop
    result = Pathname.new(result) unless result.is_a?(Pathname)
    return result if result.absolute?

    args.reverse_each do |arg|
      arg = Pathname.new(arg) unless arg.is_a?(Pathname)
      result = arg + result
      return result if result.absolute?
    end
    self + result
  end

  # The path this one names, read from `base_directory`. Both are cleaned
  # first, and neither is looked up: `..` is taken at its word.
  def relative_path_from(base_directory)
    base_directory = Pathname.new(base_directory) unless base_directory.is_a?(Pathname)
    dest_prefix, dest_names = split_names(cleanpath.to_s)
    base_prefix, base_names = split_names(base_directory.cleanpath.to_s)
    dest_names = dest_names.reject { |n| n == "." }
    base_names = base_names.reject { |n| n == "." }
    raise ArgumentError, "different prefix: #{dest_prefix.inspect} and #{base_directory.to_s.inspect}" unless dest_prefix == base_prefix

    while !dest_names.empty? && !base_names.empty? && dest_names.first == base_names.first
      dest_names.shift
      base_names.shift
    end
    raise ArgumentError, "base_directory has ..: #{base_directory.to_s.inspect}" if base_names.include?("..")

    base_names.fill("..")
    relpath_names = base_names + dest_names
    return self.class.new(".") if relpath_names.empty?

    self.class.new(File.join(*relpath_names))
  end

  # Every question about the file itself, in the order ruby answers them.
  def read(*args, **opts) = File.read(@path, *args, **opts)

  def binread(*args) = File.binread(@path, *args)

  def readlines(*args, **opts) = File.readlines(@path, *args, **opts)

  def write(*args, **opts) = File.write(@path, *args, **opts)

  def binwrite(*args, **opts) = File.binwrite(@path, *args, **opts)

  def open(*args, **opts, &block) = File.open(@path, *args, **opts, &block)

  def each_line(*args, **opts, &block) = File.foreach(@path, *args, **opts, &block)

  def atime = File.atime(@path)

  def birthtime = File.birthtime(@path)

  def ctime = File.ctime(@path)

  def mtime = File.mtime(@path)

  def chmod(mode) = File.chmod(mode, @path)

  def lchmod(mode) = File.lchmod(mode, @path)

  def chown(owner, group) = File.chown(owner, group, @path)

  def lchown(owner, group) = File.lchown(owner, group, @path)

  def fnmatch(pattern, *args) = File.fnmatch(pattern, @path, *args)

  def fnmatch?(pattern, *args) = File.fnmatch?(pattern, @path, *args)

  def ftype = File.ftype(@path)

  def make_link(old) = File.link(old, @path)

  def readlink = self.class.new(File.readlink(@path))

  def rename(to) = File.rename(@path, to)

  def stat = File.stat(@path)

  def lstat = File.lstat(@path)

  def make_symlink(old) = File.symlink(old, @path)

  def truncate(length) = File.truncate(@path, length)

  def utime(atime, mtime) = File.utime(atime, mtime, @path)

  def lutime(atime, mtime) = File.lutime(atime, mtime, @path)

  def basename(*args) = self.class.new(File.basename(@path, *args))

  def dirname = self.class.new(File.dirname(@path))

  def extname = File.extname(@path)

  def expand_path(*args) = self.class.new(File.expand_path(@path, *args))

  def split = File.split(@path).map { |f| self.class.new(f) }

  def blockdev? = FileTest.blockdev?(@path)

  def chardev? = FileTest.chardev?(@path)

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

  def world_readable? = FileTest.world_readable?(@path)

  def readable_real? = FileTest.readable_real?(@path)

  def setuid? = FileTest.setuid?(@path)

  def setgid? = FileTest.setgid?(@path)

  def size = FileTest.size(@path)

  def size? = FileTest.size?(@path)

  def sticky? = FileTest.sticky?(@path)

  def symlink? = FileTest.symlink?(@path)

  def writable? = FileTest.writable?(@path)

  def world_writable? = FileTest.world_writable?(@path)

  def writable_real? = FileTest.writable_real?(@path)

  def zero? = FileTest.zero?(@path)

  def empty? = FileTest.directory?(@path) ? Dir.empty?(@path) : FileTest.empty?(@path)

  def self.glob(*args, **opts)
    return Dir.glob(*args, **opts).map { |f| new(f) } unless block_given?

    Dir.glob(*args, **opts) { |f| yield new(f) }
  end

  def self.getwd = new(Dir.getwd)

  class << self
    alias pwd getwd
  end

  def glob(pattern, flags = 0, flags2 = nil, &block)
    flags = flags2 if flags2
    return Dir.glob(pattern, flags, base: @path).map { |f| self + f } unless block

    Dir.glob(pattern, flags, base: @path) { |f| yield(self + f) }
  end

  def entries = Dir.entries(@path).map { |f| self.class.new(f) }

  def mkdir(*args) = Dir.mkdir(@path, *args)

  def rmdir = Dir.rmdir(@path)

  def opendir(&block) = Dir.open(@path, &block)

  def each_entry(&block)
    return to_enum(:each_entry) unless block

    Dir.foreach(@path) { |f| yield self.class.new(f) }
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

  def each_child(with_directory = true, &block)
    children(with_directory).each(&block)
  end

  def realpath(*args) = self.class.new(File.realpath(@path, *args))

  def realdirpath(*args) = self.class.new(File.realdirpath(@path, *args))

  def delete = File.unlink(@path)

  alias unlink delete

  def mountpoint?
    stat1 = lstat
    stat2 = parent.lstat
    stat1.dev != stat2.dev || stat1.ino == stat2.ino
  rescue Errno::ENOENT
    false
  end

  private

  # `["/", ["a", "b"]]` for `/a/b`: the root, if any, then the names.
  def split_names(path)
    names = []
    while (r = chop_basename(path))
      path, basename = r
      names.unshift(basename)
    end
    [path, names]
  end

  # `/a/b/` reads as `/a/b`, but `/` keeps its one separator.
  def del_trailing_separator(path)
    %r{(.)/+\z}.match?(path) ? path.sub(%r{/+\z}, "") : path
  end

  def cleanpath_aggressive
    prefix, names = split_names(@path)
    out = []
    names.each do |name|
      case name
      when "." then next
      when ".."
        if out.empty? || out.last == ".."
          out << ".." if prefix.empty?
        else
          out.pop
        end
      else out << name
      end
    end
    return self.class.new(prefix) if out.empty? && !prefix.empty?
    return self.class.new(".") if out.empty?

    self.class.new(prefix + out.join("/"))
  end

  def cleanpath_conservative
    prefix, names = split_names(@path)
    out = []
    names.each do |name|
      case name
      when "." then next
      when ".." then out << ".."
      else out << name
      end
    end
    return self.class.new(prefix) if out.empty? && !prefix.empty?
    return self.class.new(".") if out.empty?

    self.class.new(prefix + out.join("/"))
  end
end

module Kernel
  # `Pathname(path)`, as ruby's own builtin gives it.
  def Pathname(path)
    Primitive.attr! :ruby
    path.is_a?(Pathname) ? path : Pathname.new(path)
  end
  module_function :Pathname
end
