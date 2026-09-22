# frozen_string_literal: true

require "spec_helper"

describe "Pathname programs" do
  it "superclass, subclasses and inherited are Class's, so a Module has none of them" do
    result = ze0(<<~'RUBY')
      # Which CLASS owns a builtin method is part of its behaviour, not a detail of
      # reflection: it decides which receivers answer it. This locks the boundaries
      # the arity census proved zeo had drawn in the wrong place.

      require "pathname"
      require "tmpdir"

      def owner_of(klass, name)
        klass.instance_method(name).owner
      rescue NameError
        "absent"
      end

      # `superclass`/`subclasses`/`inherited` are Class's, so a MODULE has none.
      puts "-- Class, not Module"
      p owner_of(Class, :superclass)
      p owner_of(Class, :subclasses)
      p owner_of(Class, :inherited)
      [:superclass, :subclasses].each do |m|
        begin
          Comparable.public_send(m)
        rescue NoMethodError
          puts "Comparable.#{m}: NoMethodError"
        end
      end

    RUBY

    _(result).must_answer <<~'OUT'
      -- Class, not Module
      Class
      Class
      Class
      Comparable.superclass: NoMethodError
      Comparable.subclasses: NoMethodError
    OUT
  end

  it "__id__ is BasicObject's name for the identity integer, where object_id is Kernel's" do
    result = ze0(<<~'RUBY')
      # Which CLASS owns a builtin method is part of its behaviour, not a detail of
      # reflection: it decides which receivers answer it. This locks the boundaries
      # the arity census proved zeo had drawn in the wrong place.

      require "pathname"
      require "tmpdir"

      def owner_of(klass, name)
        klass.instance_method(name).owner
      rescue NameError
        "absent"
      end

      # `__id__` is the root's name for the identity integer; `object_id` is Kernel's.
      puts "-- BasicObject, not Kernel"
      o = Object.new
      p owner_of(Object, :__id__)
      p owner_of(Object, :object_id)
      p o.__id__ == o.object_id

    RUBY

    _(result).must_answer <<~'OUT'
      -- BasicObject, not Kernel
      BasicObject
      Kernel
      true
    OUT
  end

  it "the open-descriptor surface is File's, not IO's" do
    result = ze0(<<~'RUBY')
      # Which CLASS owns a builtin method is part of its behaviour, not a detail of
      # reflection: it decides which receivers answer it. This locks the boundaries
      # the arity census proved zeo had drawn in the wrong place.

      require "pathname"
      require "tmpdir"

      def owner_of(klass, name)
        klass.instance_method(name).owner
      rescue NameError
        "absent"
      end

      # The open-descriptor surface that needs a real file behind the fd is File's,
      # so a pipe end does not answer it.
      puts "-- File, not IO"
      p owner_of(File, :flock)
      p owner_of(File, :truncate)
      r, w = IO.pipe
      %i[size chmod chown flock lstat mtime truncate pipe?].each do |m|
        begin
          r.public_send(m)
          puts "IO##{m}: answered"
        rescue NoMethodError
          puts "IO##{m}: NoMethodError"
        rescue ArgumentError
          puts "IO##{m}: ArgumentError"
        end
      end
      r.close
      w.close

      Dir.mktmpdir do |d|
        path = File.join(d, "f")
        File.write(path, "hello world")
        File.open(path, "r+") do |f|
          p f.size
          p f.chmod(0o644)
          p f.flock(File::LOCK_EX)
          p f.flock(File::LOCK_UN)
          p f.lstat.class
          p f.mtime.class
          p f.truncate(5)
          p f.size
        end
        p File.read(path)
      end

    RUBY

    _(result).must_answer <<~'OUT'
      -- File, not IO
      File
      File
      IO#size: NoMethodError
      IO#chmod: NoMethodError
      IO#chown: NoMethodError
      IO#flock: NoMethodError
      IO#lstat: NoMethodError
      IO#mtime: NoMethodError
      IO#truncate: NoMethodError
      IO#pipe?: NoMethodError
      11
      0
      0
      0
      File::Stat
      Time
      0
      5
      "hello"
    OUT
  end

  it "max is SizedQueue's, and an unbounded Queue has none" do
    result = ze0(<<~'RUBY')
      # Which CLASS owns a builtin method is part of its behaviour, not a detail of
      # reflection: it decides which receivers answer it. This locks the boundaries
      # the arity census proved zeo had drawn in the wrong place.

      require "pathname"
      require "tmpdir"

      def owner_of(klass, name)
        klass.instance_method(name).owner
      rescue NameError
        "absent"
      end

      # The bound is SizedQueue's; an unbounded Queue has no `max` at all.
      puts "-- SizedQueue, not Queue"
      q = Thread::Queue.new
      [:max, :max=].each do |m|
        begin
          m == :max ? q.max : (q.max = 1)
        rescue NoMethodError
          puts "Queue##{m}: NoMethodError"
        end
      end
      s = Thread::SizedQueue.new(2)
      p s.max
      s.max = 5
      p s.max

    RUBY

    _(result).must_answer <<~'OUT'
      -- SizedQueue, not Queue
      Queue#max: NoMethodError
      Queue#max=: NoMethodError
      2
      5
    OUT
  end

  it "the names zeo used to answer that CRuby has nowhere are gone" do
    result = ze0(<<~'RUBY')
      # Which CLASS owns a builtin method is part of its behaviour, not a detail of
      # reflection: it decides which receivers answer it. This locks the boundaries
      # the arity census proved zeo had drawn in the wrong place.

      require "pathname"
      require "tmpdir"

      def owner_of(klass, name)
        klass.instance_method(name).owner
      rescue NameError
        "absent"
      end

      # Names zeo used to answer that CRuby has nowhere.
      puts "-- not methods at all"
      {
        "Regexp#linear_time?" => -> { /a/.linear_time? },
        "Set#contain?" => -> { require("set") || Set.new([1]).contain?(1) },
        "Set#merge_new" => -> { require("set") || Set.new([1]).merge_new([2]) },
        "Pathname#to_str" => -> { Pathname.new("/tmp").to_str },
        "Pathname#mkdir_p" => -> { Pathname.new("/tmp").mkdir_p },
        "Pathname#rm_rf" => -> { Pathname.new("/tmp").rm_rf },
        "Proc#()" => -> { ->(x) { x }.public_send(:"()", 1) },
        "Struct[]" => -> { Struct[:a] },
      }.each do |label, probe|
        begin
          probe.call
          puts "#{label}: answered"
        rescue NoMethodError
          puts "#{label}: NoMethodError"
        end
      end

    RUBY

    _(result).must_answer <<~'OUT'
      -- not methods at all
      Regexp#linear_time?: NoMethodError
      Set#contain?: NoMethodError
      Set#merge_new: NoMethodError
      Pathname#to_str: NoMethodError
      Pathname#mkdir_p: NoMethodError
      Pathname#rm_rf: NoMethodError
      Proc#(): NoMethodError
      Struct[]: NoMethodError
    OUT
  end

  it "the real spellings of those names still answer" do
    result = ze0(<<~'RUBY')
      # Which CLASS owns a builtin method is part of its behaviour, not a detail of
      # reflection: it decides which receivers answer it. This locks the boundaries
      # the arity census proved zeo had drawn in the wrong place.

      require "pathname"
      require "tmpdir"

      def owner_of(klass, name)
        klass.instance_method(name).owner
      rescue NameError
        "absent"
      end

      # ...while the real spellings still work.
      p Regexp.linear_time?(/a*/)
      p Pathname.new("/tmp").to_s
      p ->(x) { x * 2 }.(3)
      p Struct.new(:a)[1].a
      require "set"
      p Set.new([1]).include?(1)
      p (Set.new([1]) | [2]).to_a.sort
    RUBY

    _(result).must_answer <<~'OUT'
      true
      "/tmp"
      6
      1
      true
      [1, 2]
    OUT
  end

  it "File's readers take an object that answers to_path" do
    result = ze0(<<~'RUBY')
      require "pathname"
      require "stringio"

      dir = "/tmp/spinel_implicit_conversion_protocol_#{Process.pid}"
      if Dir.exist?(dir)
        Dir.children(dir).each { |e| File.delete("#{dir}/#{e}") }
        Dir.rmdir(dir)
      end
      Dir.mkdir(dir)
      file = "#{dir}/a.txt"
      File.write(file, "abcdef\n")

      class Conf
        attr_accessor :path

        def to_path
          @path
        end
      end

      class PathLike
        def initialize(path)
          @path = path
        end

        def to_path
          @path
        end
      end

      class StrLike
        def initialize(path)
          @path = path
        end

        def to_str
          @path
        end
      end

      class Both
        def initialize(path)
          @path = path
        end

        def to_path
          @path
        end

        def to_str
          "/nonexistent/#{@path}"
        end
      end

      pl = PathLike.new(file)
      dl = PathLike.new(dir)
      pn = Pathname.new(file)
      DIR = dir
      class Payload
        def to_s
          "payload"
        end
      end

      class Churn
        def initialize(n)
          @n = n
        end
        def to_path
          2000.times { "z" * 40 }
          "#{DIR}/churn#{@n}.txt"
        end
      end

      p File.exist?(pl)
      p File.file?(pl)
      p File.read(pl)
      p File.basename(pl)
      p File.dirname(pl) == dir
      p File.extname(pl)
      p File.expand_path(PathLike.new("x"), dir) == "#{dir}/x"
      p File.size(pl)
      p File.readlines(pl)
      p File.readlines(pl, chomp: true)
      p IO.read(pl)
      p IO.readlines(pl)
      lines = []
      File.foreach(pl) { |l| lines << l }
      p lines
      p File.open(pl) { |f| f.read(3) }
      p File.open(pl, "r") { |f| f.gets }
      p File.join("a", PathLike.new("b"), "c")
      p File.stat(pl).size
      p File.exist?(StrLike.new(file))
      p File.read(StrLike.new(file))
      p File.exist?(Both.new(file))
      conf = Conf.new
      conf.path = file
      p File.exist?(conf)
      conf.path = nil
      begin
        File.exist?(conf)
      rescue TypeError => e
        p [e.class, e.message]
      end
      p File.atime(pl).class
      p File.owned?(pl)
      p File.realdirpath(PathLike.new("a.txt"), dl) == File.realpath(file)
      p File.expand_path("a.txt", PathLike.new(dir)) == file
      p File.absolute_path("a.txt", PathLike.new(dir)) == file
      p File.utime(Time.at(0), Time.at(0), pl)
      p File.join(["a", PathLike.new("b")], "c")
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      "abcdef\n"
      "a.txt"
      true
      ".txt"
      true
      7
      ["abcdef\n"]
      ["abcdef"]
      "abcdef\n"
      ["abcdef\n"]
      ["abcdef\n"]
      "abc"
      "abcdef\n"
      "a/b/c"
      7
      true
      "abcdef\n"
      true
      true
      [TypeError, "no implicit conversion of nil into String"]
      Time
      true
      true
      true
      true
      1
      "a/b/c"
    OUT
  end

  it "Dir's rows take an object that answers to_path" do
    result = ze0(<<~'RUBY')
      require "pathname"
      require "stringio"

      dir = "/tmp/spinel_implicit_conversion_protocol_#{Process.pid}"
      if Dir.exist?(dir)
        Dir.children(dir).each { |e| File.delete("#{dir}/#{e}") }
        Dir.rmdir(dir)
      end
      Dir.mkdir(dir)
      file = "#{dir}/a.txt"
      File.write(file, "abcdef\n")

      class Conf
        attr_accessor :path

        def to_path
          @path
        end
      end

      class PathLike
        def initialize(path)
          @path = path
        end

        def to_path
          @path
        end
      end

      class StrLike
        def initialize(path)
          @path = path
        end

        def to_str
          @path
        end
      end

      class Both
        def initialize(path)
          @path = path
        end

        def to_path
          @path
        end

        def to_str
          "/nonexistent/#{@path}"
        end
      end

      pl = PathLike.new(file)
      dl = PathLike.new(dir)
      pn = Pathname.new(file)
      DIR = dir
      class Payload
        def to_s
          "payload"
        end
      end

      class Churn
        def initialize(n)
          @n = n
        end
        def to_path
          2000.times { "z" * 40 }
          "#{DIR}/churn#{@n}.txt"
        end
      end

      p Dir.exist?(dl)
      p Dir.entries(dl).sort
      p Dir.children(dl)
      p Dir.glob(PathLike.new("#{dir}/*.txt")).map { |f| File.basename(f) }
      d = Dir.open(dl)
      p d.path == dir
      d.close
      p Dir.empty?(dl)
      sub = Pathname.new("#{dir}/sub")
      p Dir.mkdir(sub)
      p Dir.exist?(sub)
      p Dir.rmdir(sub)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      [".", "..", "a.txt"]
      ["a.txt"]
      ["a.txt"]
      true
      false
      0
      true
      0
    OUT
  end

  it "a Pathname is accepted wherever a to_path object is" do
    result = ze0(<<~'RUBY')
      require "pathname"
      require "stringio"

      dir = "/tmp/spinel_implicit_conversion_protocol_#{Process.pid}"
      if Dir.exist?(dir)
        Dir.children(dir).each { |e| File.delete("#{dir}/#{e}") }
        Dir.rmdir(dir)
      end
      Dir.mkdir(dir)
      file = "#{dir}/a.txt"
      File.write(file, "abcdef\n")

      class Conf
        attr_accessor :path

        def to_path
          @path
        end
      end

      class PathLike
        def initialize(path)
          @path = path
        end

        def to_path
          @path
        end
      end

      class StrLike
        def initialize(path)
          @path = path
        end

        def to_str
          @path
        end
      end

      class Both
        def initialize(path)
          @path = path
        end

        def to_path
          @path
        end

        def to_str
          "/nonexistent/#{@path}"
        end
      end

      pl = PathLike.new(file)
      dl = PathLike.new(dir)
      pn = Pathname.new(file)
      DIR = dir
      class Payload
        def to_s
          "payload"
        end
      end

      class Churn
        def initialize(n)
          @n = n
        end
        def to_path
          2000.times { "z" * 40 }
          "#{DIR}/churn#{@n}.txt"
        end
      end

      pn = Pathname.new(file)
      p File.exist?(pn)
      p File.basename(pn)
      p File.join(Pathname.new("a"), "b")
      p IO.read(pn)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      "a.txt"
      "a/b"
      "abcdef\n"
    OUT
  end

  it "a converting object reaches a typed slot through a method parameter" do
    result = ze0(<<~'RUBY')
      require "pathname"
      require "stringio"

      dir = "/tmp/spinel_implicit_conversion_protocol_#{Process.pid}"
      if Dir.exist?(dir)
        Dir.children(dir).each { |e| File.delete("#{dir}/#{e}") }
        Dir.rmdir(dir)
      end
      Dir.mkdir(dir)
      file = "#{dir}/a.txt"
      File.write(file, "abcdef\n")

      class Conf
        attr_accessor :path

        def to_path
          @path
        end
      end

      class PathLike
        def initialize(path)
          @path = path
        end

        def to_path
          @path
        end
      end

      class StrLike
        def initialize(path)
          @path = path
        end

        def to_str
          @path
        end
      end

      class Both
        def initialize(path)
          @path = path
        end

        def to_path
          @path
        end

        def to_str
          "/nonexistent/#{@path}"
        end
      end

      pl = PathLike.new(file)
      dl = PathLike.new(dir)
      pn = Pathname.new(file)
      DIR = dir
      class Payload
        def to_s
          "payload"
        end
      end

      class Churn
        def initialize(n)
          @n = n
        end
        def to_path
          2000.times { "z" * 40 }
          "#{DIR}/churn#{@n}.txt"
        end
      end

      def size_of(path)
        File.size(path)
      end
      p size_of(file)
      p size_of(pl)
      p size_of(pn)
      p size_of(StrLike.new(file))
      p size_of(Both.new(file))
      p IO.sysopen(pl).class
    RUBY

    _(result).must_answer <<~'OUT'
      7
      7
      7
      7
      7
      Integer
    OUT
  end

  it "copy_stream, reopen, rename, symlink and delete each convert their paths" do
    result = ze0(<<~'RUBY')
      require "pathname"
      require "stringio"

      dir = "/tmp/spinel_implicit_conversion_protocol_#{Process.pid}"
      if Dir.exist?(dir)
        Dir.children(dir).each { |e| File.delete("#{dir}/#{e}") }
        Dir.rmdir(dir)
      end
      Dir.mkdir(dir)
      file = "#{dir}/a.txt"
      File.write(file, "abcdef\n")

      class Conf
        attr_accessor :path

        def to_path
          @path
        end
      end

      class PathLike
        def initialize(path)
          @path = path
        end

        def to_path
          @path
        end
      end

      class StrLike
        def initialize(path)
          @path = path
        end

        def to_str
          @path
        end
      end

      class Both
        def initialize(path)
          @path = path
        end

        def to_path
          @path
        end

        def to_str
          "/nonexistent/#{@path}"
        end
      end

      pl = PathLike.new(file)
      dl = PathLike.new(dir)
      pn = Pathname.new(file)
      DIR = dir
      class Payload
        def to_s
          "payload"
        end
      end

      class Churn
        def initialize(n)
          @n = n
        end
        def to_path
          2000.times { "z" * 40 }
          "#{DIR}/churn#{@n}.txt"
        end
      end

      copy = "#{dir}/b.txt"
      p IO.copy_stream(pl, PathLike.new(copy))
      p File.read(copy)
      io = File.open("/dev/null", "r")
      p io.reopen(PathLike.new(copy), "r").read
      io.close
      moved = "#{dir}/c.txt"
      p File.rename(PathLike.new(copy), PathLike.new(moved))
      p File.exist?(moved)
      link = "#{dir}/link"
      p File.symlink(PathLike.new(moved), PathLike.new(link))
      p File.readlink(PathLike.new(link)) == moved
      p File.delete(PathLike.new(link), PathLike.new(moved))
      p File.exist?(moved)
    RUBY

    _(result).must_answer <<~'OUT'
      7
      "abcdef\n"
      "abcdef\n"
      0
      true
      0
      true
      2
      false
    OUT
  end

  it "the mode and permission arguments convert through to_int and to_str" do
    result = ze0(<<~'RUBY')
      require "pathname"
      require "stringio"

      dir = "/tmp/spinel_implicit_conversion_protocol_#{Process.pid}"
      if Dir.exist?(dir)
        Dir.children(dir).each { |e| File.delete("#{dir}/#{e}") }
        Dir.rmdir(dir)
      end
      Dir.mkdir(dir)
      file = "#{dir}/a.txt"
      File.write(file, "abcdef\n")

      class Conf
        attr_accessor :path

        def to_path
          @path
        end
      end

      class PathLike
        def initialize(path)
          @path = path
        end

        def to_path
          @path
        end
      end

      class StrLike
        def initialize(path)
          @path = path
        end

        def to_str
          @path
        end
      end

      class Both
        def initialize(path)
          @path = path
        end

        def to_path
          @path
        end

        def to_str
          "/nonexistent/#{@path}"
        end
      end

      pl = PathLike.new(file)
      dl = PathLike.new(dir)
      pn = Pathname.new(file)
      DIR = dir
      class Payload
        def to_s
          "payload"
        end
      end

      class Churn
        def initialize(n)
          @n = n
        end
        def to_path
          2000.times { "z" * 40 }
          "#{DIR}/churn#{@n}.txt"
        end
      end

      class ReadMode
        def to_int
          File::RDONLY
        end
      end

      class ModeName
        def to_str
          "r"
        end
      end
      p File.open(pl, ReadMode.new) { |f| f.read(2) }
      p File.open(pl, ModeName.new) { |f| f.read(2) }
      p File.open(pl, mode: ReadMode.new) { |f| f.read(2) }
      class CreateMode
        def to_int
          File::WRONLY | File::CREAT
        end
      end
      made = "#{dir}/made.txt"
      File.open(made, CreateMode.new, 0600) { |f| f.write("m") }
      p format("%o", File.stat(made).mode & 0777)
      File.delete(made)
      File.open(made, "w", 0600) { |f| f.write("m") }
      p format("%o", File.stat(made).mode & 0777)
      File.delete(made)
      File.open(made, "w", perm: 0600) { |f| f.write("m") }
      p format("%o", File.stat(made).mode & 0777)
      File.delete(made)
      File.open(made, mode: "w", perm: 0640) { |f| f.write("m") }
      p format("%o", File.stat(made).mode & 0777)
      File.delete(made)
      File.open(made, File::WRONLY | File::CREAT, perm: 0600) { |f| p f.path == made }
      p format("%o", File.stat(made).mode & 0777)
      File.delete(made)
      def maybe_perm(x)
        x ? 0600 : nil
      end
      File.open(made, "w", maybe_perm(false)) { |f| f.write("m") }
      p format("%o", File.stat(made).mode & 0777)
      File.open(made, "w", nil) { |f| p f.close_on_exec? }
      begin
        File.open(made, "wx", 0600) { |f| f.write("!") }
      rescue SystemCallError => e
        p e.class
      end
      p File.read(made)
      File.delete(made)
      begin
        File.open(made, "+", 0600)
      rescue ArgumentError => e
        p e.message
      end
      begin
        File.open(made, "rx", 0600)
      rescue ArgumentError => e
        p e.message
      end
      begin
        File.open(made, "ax")
      rescue ArgumentError => e
        p e.message
      end
      File.open(made, "wx+", 0600) { |f| f.write("zz"); f.rewind; p f.read }
      File.delete(made)
    RUBY

    _(result).must_answer <<~'OUT'
      "ab"
      "ab"
      "ab"
      "600"
      "600"
      "600"
      "640"
      true
      "600"
      "644"
      true
      Errno::EEXIST
      ""
      "invalid access mode +"
      "invalid access mode rx"
      "invalid access mode ax"
      "zz"
    OUT
  end

  it "to_path is called once for one slot, not once per use of the value" do
    result = ze0(<<~'RUBY')
      require "pathname"
      require "stringio"

      dir = "/tmp/spinel_implicit_conversion_protocol_#{Process.pid}"
      if Dir.exist?(dir)
        Dir.children(dir).each { |e| File.delete("#{dir}/#{e}") }
        Dir.rmdir(dir)
      end
      Dir.mkdir(dir)
      file = "#{dir}/a.txt"
      File.write(file, "abcdef\n")

      class Conf
        attr_accessor :path

        def to_path
          @path
        end
      end

      class PathLike
        def initialize(path)
          @path = path
        end

        def to_path
          @path
        end
      end

      class StrLike
        def initialize(path)
          @path = path
        end

        def to_str
          @path
        end
      end

      class Both
        def initialize(path)
          @path = path
        end

        def to_path
          @path
        end

        def to_str
          "/nonexistent/#{@path}"
        end
      end

      pl = PathLike.new(file)
      dl = PathLike.new(dir)
      pn = Pathname.new(file)
      DIR = dir
      class Payload
        def to_s
          "payload"
        end
      end

      class Churn
        def initialize(n)
          @n = n
        end
        def to_path
          2000.times { "z" * 40 }
          "#{DIR}/churn#{@n}.txt"
        end
      end

      class Counted
        def initialize(path)
          @path = path
          @calls = 0
        end

        attr_reader :calls

        def to_path
          @calls += 1
          @path
        end
      end
      counted = Counted.new(file)
      p [File.file?(counted), counted.calls]
    RUBY

    _(result).must_answer <<~'OUT'
      [true, 1]
    OUT
  end

  it "a zone object converts through to_str at Time's slot" do
    result = ze0(<<~'RUBY')
      require "pathname"
      require "stringio"

      dir = "/tmp/spinel_implicit_conversion_protocol_#{Process.pid}"
      if Dir.exist?(dir)
        Dir.children(dir).each { |e| File.delete("#{dir}/#{e}") }
        Dir.rmdir(dir)
      end
      Dir.mkdir(dir)
      file = "#{dir}/a.txt"
      File.write(file, "abcdef\n")

      class Conf
        attr_accessor :path

        def to_path
          @path
        end
      end

      class PathLike
        def initialize(path)
          @path = path
        end

        def to_path
          @path
        end
      end

      class StrLike
        def initialize(path)
          @path = path
        end

        def to_str
          @path
        end
      end

      class Both
        def initialize(path)
          @path = path
        end

        def to_path
          @path
        end

        def to_str
          "/nonexistent/#{@path}"
        end
      end

      pl = PathLike.new(file)
      dl = PathLike.new(dir)
      pn = Pathname.new(file)
      DIR = dir
      class Payload
        def to_s
          "payload"
        end
      end

      class Churn
        def initialize(n)
          @n = n
        end
        def to_path
          2000.times { "z" * 40 }
          "#{DIR}/churn#{@n}.txt"
        end
      end

      class Zone
        def to_str
          "+01:00"
        end
      end
      p Time.at(0).getlocal(Zone.new).utc_offset
      p Time.at(0).localtime(Zone.new).utc_offset
      t = Time.at(0)
      t.localtime(Zone.new)
      p t.utc_offset
    RUBY

    _(result).must_answer <<~'OUT'
      3600
      3600
      3600
    OUT
  end

  it "a write slot converts its payload through to_s" do
    result = ze0(<<~'RUBY')
      require "pathname"
      require "stringio"

      dir = "/tmp/spinel_implicit_conversion_protocol_#{Process.pid}"
      if Dir.exist?(dir)
        Dir.children(dir).each { |e| File.delete("#{dir}/#{e}") }
        Dir.rmdir(dir)
      end
      Dir.mkdir(dir)
      file = "#{dir}/a.txt"
      File.write(file, "abcdef\n")

      class Conf
        attr_accessor :path

        def to_path
          @path
        end
      end

      class PathLike
        def initialize(path)
          @path = path
        end

        def to_path
          @path
        end
      end

      class StrLike
        def initialize(path)
          @path = path
        end

        def to_str
          @path
        end
      end

      class Both
        def initialize(path)
          @path = path
        end

        def to_path
          @path
        end

        def to_str
          "/nonexistent/#{@path}"
        end
      end

      pl = PathLike.new(file)
      dl = PathLike.new(dir)
      pn = Pathname.new(file)
      DIR = dir
      class Payload
        def to_s
          "payload"
        end
      end

      class Churn
        def initialize(n)
          @n = n
        end
        def to_path
          2000.times { "z" * 40 }
          "#{DIR}/churn#{@n}.txt"
        end
      end

      sio = StringIO.new
      p sio.write(Payload.new)
      p (sio << Payload.new).equal?(sio)
      p sio.write(42)
      p (sio << :sym).equal?(sio)
      p sio.print(Payload.new, 1)
      p sio.puts(Payload.new)
      p sio.puts
      result = sio.puts("assigned")
      p result
      class Nul
        def to_s
          "a\0b"
        end
      end
      p sio.print(Nul.new)
      p sio.print(:sym, [1, 2])
      class Plain
      end
      sio.puts(Plain.new)
      p sio.string.sub(/0x[0-9a-f]+/, "0xADDR")
      mixed = StringIO.new
      [1, "a", :b].each { |x| mixed.puts(x) }
      p mixed.string
      File.open(file, "r+") { |f| p [f.pwrite(Payload.new, 1), File.read(file)] }
      File.open(file, "w") { |f| p f.write_nonblock(Payload.new) }
      p File.read(file)
      p File.write(pl, Payload.new)
      p File.write(pl, 42, mode: "a")
      p File.write(pl, :sym, 2)
      p File.read(file)
      def payload(nul)
        nul ? "a\0b" : Payload.new
      end
      p File.write(pl, payload(true))
      p File.size(file)
      p File.write(pl, payload(false))
    RUBY

    _(result).must_answer <<~'OUT'
      7
      true
      2
      true
      nil
      nil
      nil
      nil
      nil
      nil
      "payloadpayload42sympayload1payload\n\nassigned\na\u0000bsym[1, 2]#<Plain:0xADDR>\n"
      "1\na\nb\n"
      [7, "apayload"]
      7
      "payload"
      7
      2
      3
      "pasymad42"
      3
      3
      7
    OUT
  end

  it "a converter that allocates heavily still answers the same path" do
    result = ze0(<<~'RUBY')
      require "pathname"
      require "stringio"

      dir = "/tmp/spinel_implicit_conversion_protocol_#{Process.pid}"
      if Dir.exist?(dir)
        Dir.children(dir).each { |e| File.delete("#{dir}/#{e}") }
        Dir.rmdir(dir)
      end
      Dir.mkdir(dir)
      file = "#{dir}/a.txt"
      File.write(file, "abcdef\n")

      class Conf
        attr_accessor :path

        def to_path
          @path
        end
      end

      class PathLike
        def initialize(path)
          @path = path
        end

        def to_path
          @path
        end
      end

      class StrLike
        def initialize(path)
          @path = path
        end

        def to_str
          @path
        end
      end

      class Both
        def initialize(path)
          @path = path
        end

        def to_path
          @path
        end

        def to_str
          "/nonexistent/#{@path}"
        end
      end

      pl = PathLike.new(file)
      dl = PathLike.new(dir)
      pn = Pathname.new(file)
      DIR = dir
      class Payload
        def to_s
          "payload"
        end
      end

      class Churn
        def initialize(n)
          @n = n
        end
        def to_path
          2000.times { "z" * 40 }
          "#{DIR}/churn#{@n}.txt"
        end
      end

      class Fresh
        def initialize(n)
          @n = n
        end
        def to_path
          "seg" + @n.to_s
        end
      end
      bad = 0
      2000.times do |i|
        r = File.join(Fresh.new(i), Fresh.new(i + 1), Fresh.new(i + 2))
        bad += 1 unless r == "seg#{i}/seg#{i + 1}/seg#{i + 2}"
      end
      p bad

      class Loud
        def to_s
          2000.times { "z" * 40 }
          "PAY"
        end
      end

      p File.write(Churn.new(1), Loud.new)
      File.rename(Churn.new(1), Churn.new(2))
      p [File.exist?("#{dir}/churn1.txt"), File.exist?("#{dir}/churn2.txt")]
      p File.expand_path(Churn.new(1), Churn.new(2)) == "#{dir}/churn2.txt#{dir}/churn1.txt"
      File.delete("#{dir}/churn2.txt")
      class Built
        def to_path
          b = ""
          50.times { b = b + "ab" }
          b
        end
      end
      bad = 0
      2000.times { bad += 1 unless File.join(Built.new) == "ab" * 50 }
      p bad
      loop_a = ["x"]
      loop_a << loop_a
      begin
        File.join(loop_a)
      rescue ArgumentError => e
        p e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      0
      3
      [false, true]
      false
      0
      "recursive array"
    OUT
  end

  it "a converter that prints shows where in the argument order it runs" do
    result = ze0(<<~'RUBY')
      require "pathname"
      require "stringio"

      dir = "/tmp/spinel_implicit_conversion_protocol_#{Process.pid}"
      if Dir.exist?(dir)
        Dir.children(dir).each { |e| File.delete("#{dir}/#{e}") }
        Dir.rmdir(dir)
      end
      Dir.mkdir(dir)
      file = "#{dir}/a.txt"
      File.write(file, "abcdef\n")

      class Conf
        attr_accessor :path

        def to_path
          @path
        end
      end

      class PathLike
        def initialize(path)
          @path = path
        end

        def to_path
          @path
        end
      end

      class StrLike
        def initialize(path)
          @path = path
        end

        def to_str
          @path
        end
      end

      class Both
        def initialize(path)
          @path = path
        end

        def to_path
          @path
        end

        def to_str
          "/nonexistent/#{@path}"
        end
      end

      pl = PathLike.new(file)
      dl = PathLike.new(dir)
      pn = Pathname.new(file)
      DIR = dir
      class Payload
        def to_s
          "payload"
        end
      end

      class Churn
        def initialize(n)
          @n = n
        end
        def to_path
          2000.times { "z" * 40 }
          "#{DIR}/churn#{@n}.txt"
        end
      end

      # The rows below read this file, which the write rows left holding
      # a converted payload rather than the bytes the setup wrote.
      File.write(file, "payload")
      sio = StringIO.new
      class Noisy
        def initialize(n)
          @n = n
        end
        def to_s
          $stdout.print("[c#{@n}]")
          "<#{@n}>"
        end
      end
      $stdout.write(Noisy.new(5), Noisy.new(6))
      puts
      def named
        puts "named"
        "#{DIR}/named.txt"
      end
      File.write(named, Payload.new)
      File.write("#{dir}/churn1.txt", "x")
      File.rename(Churn.new(1), named)
      p [File.exist?("#{dir}/churn1.txt"), File.read("#{dir}/named.txt")]
      File.delete("#{dir}/named.txt")
      class Wide
        def initialize(s)
          @s = s
        end
        def to_path
          ("y" * 3000).sub("y", @s)[0, 3]
        end
      end
      letters = ("a".."t").to_a
      bad = 0
      100.times do
        r = File.join(Wide.new("a"), Wide.new("b"), Wide.new("c"), Wide.new("d"), Wide.new("e"),
                      Wide.new("f"), Wide.new("g"), Wide.new("h"), Wide.new("i"), Wide.new("j"),
                      Wide.new("k"), Wide.new("l"), Wide.new("m"), Wide.new("n"), Wide.new("o"),
                      Wide.new("p"), Wide.new("q"), Wide.new("r"), Wide.new("s"), Wide.new("t"))
        bad += 1 unless r == letters.map { |x| x + "yy" }.join("/")
      end
      p bad

      def trace(label, value)
        puts label
        value
      end
      def trace_io(label, io)
        puts label
        io
      end
      p File.exist?(trace("arg", pl))
      p trace_io("recv", sio).write(trace("arg", Payload.new))
      class Announced
        def initialize(path)
          @path = path
        end
        def to_path
          puts "convert"
          @path
        end
      end
      def sideff(n)
        puts "sibling"
        n
      end
      announced = Announced.new(file)
      p File.read(announced, sideff(4))
      class Offset
        def to_int
          puts "convert"
          2
        end
      end
      off = Offset.new
      p "abcdef"[off, sideff(3)]
      class Spoken
        def to_s
          puts "convert"
          "payl"
        end
      end
      spoken = Spoken.new
      File.open(file, "w") { |f| p f.write(spoken, sideff("Z")) }
      p File.read(file)
    RUBY

    _(result).must_answer <<~'OUT'
      [c5]<5>[c6]<6>
      named
      named
      [false, "x"]
      0
      arg
      true
      recv
      arg
      7
      sibling
      convert
      "payl"
      sibling
      convert
      "cde"
      sibling
      convert
      5
      "paylZ"
    OUT
  end

  it "the tree the setup built is removed again" do
    result = ze0(<<~'RUBY')
      require "pathname"
      require "stringio"

      dir = "/tmp/spinel_implicit_conversion_protocol_#{Process.pid}"
      if Dir.exist?(dir)
        Dir.children(dir).each { |e| File.delete("#{dir}/#{e}") }
        Dir.rmdir(dir)
      end
      Dir.mkdir(dir)
      file = "#{dir}/a.txt"
      File.write(file, "abcdef\n")

      class Conf
        attr_accessor :path

        def to_path
          @path
        end
      end

      class PathLike
        def initialize(path)
          @path = path
        end

        def to_path
          @path
        end
      end

      class StrLike
        def initialize(path)
          @path = path
        end

        def to_str
          @path
        end
      end

      class Both
        def initialize(path)
          @path = path
        end

        def to_path
          @path
        end

        def to_str
          "/nonexistent/#{@path}"
        end
      end

      pl = PathLike.new(file)
      dl = PathLike.new(dir)
      pn = Pathname.new(file)
      DIR = dir
      class Payload
        def to_s
          "payload"
        end
      end

      class Churn
        def initialize(n)
          @n = n
        end
        def to_path
          2000.times { "z" * 40 }
          "#{DIR}/churn#{@n}.txt"
        end
      end

      File.delete(file)
      Dir.rmdir(dir)
      p Dir.exist?(dl)
    RUBY

    _(result).must_answer <<~'OUT'
      false
    OUT
  end

  it "native pathname path operations match the oracle" do
    result = ze0(<<~'RUBY')
      # `Pathname`: path manipulation (`+`/`join` resolve `..` lexically like
      # CRuby's `plus`), predicates, and reflection. The last line pins that it
      # does NOT include Comparable, however much its `#<=>` suggests it.

      require "pathname"
      p = Pathname.new("/usr/local/bin/ruby")
      puts p.to_s
      puts p.basename
      puts p.dirname
      puts p.extname.inspect
      puts p.absolute?
      puts (p + "..").to_s
      puts (Pathname.new("/usr") / "bin").to_s
      puts p.basename(".rb")
      puts Pathname.new("foo/bar.txt").sub_ext(".md")
      puts Pathname.new("/a/b/c").relative_path_from(Pathname.new("/a")).to_s
      puts p == Pathname.new("/usr/local/bin/ruby")
      puts p.is_a?(Comparable)
    RUBY

    _(result).must_answer <<~'OUT'
      /usr/local/bin/ruby
      ruby
      /usr/local/bin
      ""
      true
      /usr/local/bin
      /usr/bin
      ruby
      foo/bar.md
      b/c
      true
      false
    OUT
  end

  it "needs no require" do
    result = ze0(<<~'RUBY')
      # ruby 4.0 loads `pathname.so` before the first line, so the class and
      # `Kernel#Pathname` are there with no require at all.

      puts Pathname.new("/x")
      puts Pathname("/y").class
    RUBY

    _(result).must_answer "/x\nPathname\n"
  end

  it "the private path-algebra helpers answer the shapes pathname_builtin declares" do
    result = ze0(<<~'RUBY')
      # Pathname's private path-algebra helpers -- the exact surface
      # pathname_builtin.rb declares, oracle-pinned shapes.
      pn = Pathname.new("x")

      p pn.send(:chop_basename, "a/b/c")
      p pn.send(:chop_basename, "a/b/")
      p pn.send(:chop_basename, "//")
      p pn.send(:chop_basename, "")
      p pn.send(:split_names, "/a/b/c")
      p pn.send(:split_names, "a//b/")
      p pn.send(:prepend_prefix, "", "a/b")
      p pn.send(:prepend_prefix, "/", "a/b")
      p pn.send(:prepend_prefix, "/x/", "a")
      p pn.send(:prepend_prefix, "/", "")
      p pn.send(:has_trailing_separator?, "a/")
      p pn.send(:has_trailing_separator?, "a")
      p pn.send(:has_trailing_separator?, "/")
      p pn.send(:add_trailing_separator, "a")
      p pn.send(:add_trailing_separator, "a/")
      p pn.send(:add_trailing_separator, "")
      p pn.send(:del_trailing_separator, "a//")
      p pn.send(:del_trailing_separator, "///")
      p pn.send(:del_trailing_separator, "")
      p pn.send(:same_paths?, "A", "a")
      p pn.send(:same_paths?, "a", "a")
      p pn.send(:plus, "a/b/c", "../../d")
      p pn.send(:plus, "a", "/z")
      p pn.send(:plus, "..", "..")
      p Pathname.new("a/../b/./c").send(:cleanpath_aggressive)
      p Pathname.new("/../a").send(:cleanpath_aggressive)
      p Pathname.new("a/.").send(:cleanpath_conservative)
      p Pathname.new("a/b/").send(:cleanpath_conservative)
      p Pathname.new("./").send(:cleanpath_conservative)

      # The `.` tail survives the PUBLIC conservative cleanpath too.
      p Pathname.new("a/.").cleanpath(true)

      # All ten are private.
      priv = Pathname.private_instance_methods(false)
      p %i[chop_basename split_names prepend_prefix has_trailing_separator?
           add_trailing_separator del_trailing_separator same_paths? plus
           cleanpath_aggressive cleanpath_conservative].all? { |m| priv.include?(m) }
    RUBY

    _(result).must_answer <<~'OUT'
      ["a/b/", "c"]
      ["a/", "b"]
      nil
      nil
      ["/", ["a", "b", "c"]]
      ["", ["a", "b"]]
      "a/b"
      "/a/b"
      "/a"
      "/"
      true
      false
      false
      "a/"
      "a/"
      ""
      "a"
      "/"
      ""
      false
      true
      "a/d"
      "/z"
      "../.."
      #<Pathname:b/c>
      #<Pathname:/a>
      #<Pathname:a/.>
      #<Pathname:a/b/>
      #<Pathname:.>
      #<Pathname:a/.>
      true
    OUT
  end

  it "Pathname is there with no require, and its ancestry and surface are fixed" do
    result = ze0(<<~'RUBY')
      # `Pathname` is reachable with NO require: ruby 4.0 loads `pathname.so` before
      # the first line. This covers the whole surface -- the path ALGEBRA, which is
      # pure string work and never touches disk, and the delegations, which must
      # answer exactly what the same `File`/`Dir` call answers.

      require "pathname"   # a no-op here and in ruby 4.0: the class is already there
      require "tmpdir"

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      show("ancestors") { Pathname.ancestors }
      show("own singleton") { Pathname.singleton_methods(false).sort }
      show("own instance count") { Pathname.instance_methods(false).size }
      show("constants") { Pathname.constants.sort }
      show("VERSION") { Pathname::VERSION }
      show("SEPARATOR_PAT") { Pathname::SEPARATOR_PAT }
      # `#path` is PROTECTED in ruby; see tests/gaps/builtin_protected_rows.rb.
      show("Kernel#Pathname is private") { Kernel.private_instance_methods(false).include?(:Pathname) }

    RUBY

    _(result).must_answer <<~'OUT'
      ancestors: [Pathname, Object, Kernel, BasicObject]
      own singleton: [:getwd, :glob, :mktmpdir, :pwd]
      own instance count: 98
      constants: [:SEPARATOR_PAT, :VERSION]
      VERSION: "0.4.0"
      SEPARATOR_PAT: /\//
      Kernel#Pathname is private: true
    OUT
  end

  it "a Pathname is built from a String, from another Pathname and from a frozen argument" do
    result = ze0(<<~'RUBY')
      # `Pathname` is reachable with NO require: ruby 4.0 loads `pathname.so` before
      # the first line. This covers the whole surface -- the path ALGEBRA, which is
      # pure string work and never touches disk, and the delegations, which must
      # answer exactly what the same `File`/`Dir` call answers.

      require "pathname"   # a no-op here and in ruby 4.0: the class is already there
      require "tmpdir"

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      # Construction.
      show("new") { Pathname.new("/a/b").to_s }
      show("new from Pathname") { Pathname.new(Pathname.new("a")).to_s }
      show("new frozen arg") { Pathname.new("a".freeze).to_s }
      show("new null byte") { Pathname.new("a\0b") }
      show("new Integer") { Pathname.new(1) }
      show("new no args") { Pathname.new }
      show("Kernel#Pathname") { Pathname("/x").class }

    RUBY

    _(result).must_answer <<~'OUT'
      new: "/a/b"
      new from Pathname: "a"
      new frozen arg: "a"
      new null byte: ArgumentError: path name contains null byte
      new Integer: TypeError: Pathname.new requires a String, #to_path or #to_str
      new no args: ArgumentError: wrong number of arguments (given 0, expected 1)
      Kernel#Pathname: Pathname
    OUT
  end

  it "to_s answers a fresh unfrozen String, and Pathname does not include Comparable" do
    result = ze0(<<~'RUBY')
      # `Pathname` is reachable with NO require: ruby 4.0 loads `pathname.so` before
      # the first line. This covers the whole surface -- the path ALGEBRA, which is
      # pure string work and never touches disk, and the delegations, which must
      # answer exactly what the same `File`/`Dir` call answers.

      require "pathname"   # a no-op here and in ruby 4.0: the class is already there
      require "tmpdir"

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      # Identity and ordering. `Pathname` does NOT include Comparable, however much
      # its `#<=>` suggests otherwise.
      show("to_s") { Pathname.new("a").to_s }
      show("to_s is a fresh String") { p1 = Pathname.new("a"); !p1.to_s.equal?(p1.to_s) }
      show("to_s is unfrozen") { Pathname.new("a").to_s.frozen? }
      show("mutating to_s leaves self") { p1 = Pathname.new("a"); p1.to_s << "X"; p1.to_s }
      show("inspect") { Pathname.new("/a/b").inspect }
      show("== self") { Pathname.new("a") == Pathname.new("a") }
      show("== String") { Pathname.new("a") == "a" }
      show("===") { Pathname.new("a") === Pathname.new("a") }
      show("eql?") { Pathname.new("a").eql?(Pathname.new("a")) }
      show("hash agrees with ==") { Pathname.new("a").hash == Pathname.new("a").hash }
      show("<=>") { Pathname.new("a") <=> Pathname.new("b") }
      show("<=> String") { Pathname.new("a") <=> "a" }
      show("no Comparable") { Pathname.new("a") < Pathname.new("b") }
      show("freeze") { p1 = Pathname.new("a"); p1.freeze; p1.frozen? }
      show("fresh is unfrozen") { Pathname.new("a").frozen? }

    RUBY

    _(result).must_answer <<~'OUT'
      to_s: "a"
      to_s is a fresh String: true
      to_s is unfrozen: false
      mutating to_s leaves self: "a"
      inspect: "#<Pathname:/a/b>"
      == self: true
      == String: false
      ===: true
      eql?: true
      hash agrees with ==: true
      <=>: -1
      <=> String: nil
      no Comparable: NoMethodError: undefined method '<' for an instance of Pathname
      freeze: true
      fresh is unfrozen: false
    OUT
  end

  it "#+ resolves . and .. against the left operand without touching the disk" do
    result = ze0(<<~'RUBY')
      # `Pathname` is reachable with NO require: ruby 4.0 loads `pathname.so` before
      # the first line. This covers the whole surface -- the path ALGEBRA, which is
      # pure string work and never touches disk, and the delegations, which must
      # answer exactly what the same `File`/`Dir` call answers.

      require "pathname"   # a no-op here and in ruby 4.0: the class is already there
      require "tmpdir"

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      # `#+` resolves `.` and `..` against the LEFT operand's components, without
      # ever asking the filesystem.
      show("plus") { (Pathname.new("/a") + "b").to_s }
      show("plus absolute") { (Pathname.new("/a") + "/b").to_s }
      show("plus dot") { (Pathname.new("a") + ".").to_s }
      show("plus dotdot") { (Pathname.new("a/b") + "..").to_s }
      show("plus dotdot deep") { (Pathname.new("a/b/c") + "../../d").to_s }
      show("plus empty left") { (Pathname.new("") + "b").to_s }
      show("plus root") { (Pathname.new("/") + "a").to_s }
      show("plus trailing sep") { (Pathname.new("a/") + "b").to_s }
      show("plus both relative") { (Pathname.new("a/b") + "c/d").to_s }
      show("div") { (Pathname.new("a") / "b").to_s }
      show("plus Pathname") { (Pathname.new("a") + Pathname.new("b")).to_s }
      show("join") { Pathname.new("/a").join("b", "c").to_s }
      show("join none") { Pathname.new("/a").join.to_s }
      show("join absolute wins") { Pathname.new("/a").join("b", "/c").to_s }
      show("parent") { Pathname.new("/a/b").parent.to_s }
      show("parent relative") { Pathname.new("a").parent.to_s }
      show("parent root") { Pathname.new("/").parent.to_s }

    RUBY

    _(result).must_answer <<~'OUT'
      plus: "/a/b"
      plus absolute: "/b"
      plus dot: "a"
      plus dotdot: "a"
      plus dotdot deep: "a/d"
      plus empty left: "b"
      plus root: "/a"
      plus trailing sep: "a/b"
      plus both relative: "a/b/c/d"
      div: "a/b"
      plus Pathname: "a/b"
      join: "/a/b/c"
      join none: "/a"
      join absolute wins: "/c"
      parent: "/a"
      parent relative: "."
      parent root: "/"
    OUT
  end

  it "cleanpath removes what it can, and its conservative form keeps a .. it cannot" do
    result = ze0(<<~'RUBY')
      # `Pathname` is reachable with NO require: ruby 4.0 loads `pathname.so` before
      # the first line. This covers the whole surface -- the path ALGEBRA, which is
      # pure string work and never touches disk, and the delegations, which must
      # answer exactly what the same `File`/`Dir` call answers.

      require "pathname"   # a no-op here and in ruby 4.0: the class is already there
      require "tmpdir"

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      show("cleanpath") { Pathname.new("a/../b/./c//d").cleanpath.to_s }
      show("cleanpath conservative") { Pathname.new("a/../b/./c//d").cleanpath(true).to_s }
      show("cleanpath dot") { Pathname.new(".").cleanpath.to_s }
      show("cleanpath empty") { Pathname.new("").cleanpath.to_s }
      show("cleanpath dotdot") { Pathname.new("..").cleanpath.to_s }
      show("cleanpath above root") { Pathname.new("/../a").cleanpath.to_s }
      show("cleanpath trailing") { Pathname.new("a/").cleanpath.to_s }
      show("cleanpath root") { Pathname.new("/").cleanpath.to_s }

    RUBY

    _(result).must_answer <<~'OUT'
      cleanpath: "b/c/d"
      cleanpath conservative: "a/../b/c/d"
      cleanpath dot: "."
      cleanpath empty: "."
      cleanpath dotdot: ".."
      cleanpath above root: "/a"
      cleanpath trailing: "a"
      cleanpath root: "/"
    OUT
  end

  it "relative_path_from answers the route from one path to another" do
    result = ze0(<<~'RUBY')
      # `Pathname` is reachable with NO require: ruby 4.0 loads `pathname.so` before
      # the first line. This covers the whole surface -- the path ALGEBRA, which is
      # pure string work and never touches disk, and the delegations, which must
      # answer exactly what the same `File`/`Dir` call answers.

      require "pathname"   # a no-op here and in ruby 4.0: the class is already there
      require "tmpdir"

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      show("relative_path_from") { Pathname.new("/a/b/c").relative_path_from("/a/d").to_s }
      show("relative_path_from same") { Pathname.new("/a/b").relative_path_from("/a/b").to_s }
      show("relative_path_from below") { Pathname.new("a/b").relative_path_from("a").to_s }
      show("relative_path_from above") { Pathname.new("a").relative_path_from("a/b/c").to_s }
      show("relative_path_from mixed") { Pathname.new("a").relative_path_from("/b") }
      show("relative_path_from dotdot base") { Pathname.new("a").relative_path_from("../b") }

    RUBY

    _(result).must_answer <<~'OUT'
      relative_path_from: "../b/c"
      relative_path_from same: "."
      relative_path_from below: "b"
      relative_path_from above: "../.."
      relative_path_from mixed: ArgumentError: different prefix: "" and "/b"
      relative_path_from dotdot base: ArgumentError: base_directory has ..: "../b"
    OUT
  end

  it "each_filename walks the components, .. included" do
    result = ze0(<<~'RUBY')
      # `Pathname` is reachable with NO require: ruby 4.0 loads `pathname.so` before
      # the first line. This covers the whole surface -- the path ALGEBRA, which is
      # pure string work and never touches disk, and the delegations, which must
      # answer exactly what the same `File`/`Dir` call answers.

      require "pathname"   # a no-op here and in ruby 4.0: the class is already there
      require "tmpdir"

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      show("each_filename") { Pathname.new("/a/b/c").each_filename.to_a }
      show("each_filename dotdot") { Pathname.new("a/b/../c").each_filename.to_a }
      show("ascend") { Pathname.new("/a/b/c").ascend.map(&:to_s) }
      show("ascend relative") { Pathname.new("a/b").ascend.map(&:to_s) }
      show("ascend block") { r = []; Pathname.new("a/b").ascend { |x| r << x.to_s }; r }
      show("descend") { Pathname.new("/a/b/c").descend.map(&:to_s) }
      show("descend relative") { Pathname.new("a/b").descend.map(&:to_s) }

    RUBY

    _(result).must_answer <<~'OUT'
      each_filename: ["a", "b", "c"]
      each_filename dotdot: ["a", "b", "..", "c"]
      ascend: ["/a/b/c", "/a/b", "/a", "/"]
      ascend relative: ["a/b", "a"]
      ascend block: ["a/b", "a"]
      descend: ["/", "/a", "/a/b", "/a/b/c"]
      descend relative: ["a", "a/b"]
    OUT
  end

  it "basename, dirname and extname split a path into its parts" do
    result = ze0(<<~'RUBY')
      # `Pathname` is reachable with NO require: ruby 4.0 loads `pathname.so` before
      # the first line. This covers the whole surface -- the path ALGEBRA, which is
      # pure string work and never touches disk, and the delegations, which must
      # answer exactly what the same `File`/`Dir` call answers.

      require "pathname"   # a no-op here and in ruby 4.0: the class is already there
      require "tmpdir"

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      show("basename") { Pathname.new("/a/b.rb").basename.to_s }
      show("basename suffix") { Pathname.new("/a/b.rb").basename(".rb").to_s }
      show("dirname") { Pathname.new("/a/b.rb").dirname.to_s }
      show("extname") { Pathname.new("/a/b.rb").extname }
      show("sub_ext") { Pathname.new("a/b.rb").sub_ext(".txt").to_s }
      show("sub_ext none") { Pathname.new("a/b").sub_ext(".txt").to_s }
      show("sub_ext empty") { Pathname.new("a/b.rb").sub_ext("").to_s }
      show("split") { Pathname.new("/a/b").split.map(&:to_s) }
      show("split root") { Pathname.new("/").split.map(&:to_s) }
      show("sub") { Pathname.new("/a/b").sub("a", "z").to_s }
      show("sub block") { Pathname.new("/a/b").sub(/a/) { |m| m.upcase }.to_s }
      show("expand_path") { Pathname.new("b").expand_path("/a").to_s }
      show("fnmatch") { Pathname.new("a/b.rb").fnmatch("*/*.rb") }
      show("fnmatch?") { Pathname.new("a/b.rb").fnmatch?("*.rb") }

    RUBY

    _(result).must_answer <<~'OUT'
      basename: "b.rb"
      basename suffix: "b"
      dirname: "/a"
      extname: ".rb"
      sub_ext: "a/b.txt"
      sub_ext none: "a/b.txt"
      sub_ext empty: "a/b"
      split: ["/a", "b"]
      split root: ["/", "/"]
      sub: "/z/b"
      sub block: "/A/b"
      expand_path: "/a/b"
      fnmatch: true
      fnmatch?: true
    OUT
  end

  it "absolute?, relative? and root? read the path's shape" do
    result = ze0(<<~'RUBY')
      # `Pathname` is reachable with NO require: ruby 4.0 loads `pathname.so` before
      # the first line. This covers the whole surface -- the path ALGEBRA, which is
      # pure string work and never touches disk, and the delegations, which must
      # answer exactly what the same `File`/`Dir` call answers.

      require "pathname"   # a no-op here and in ruby 4.0: the class is already there
      require "tmpdir"

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      show("absolute?") { [Pathname.new("/a").absolute?, Pathname.new("a").absolute?] }
      show("relative?") { [Pathname.new("/a").relative?, Pathname.new("a").relative?] }
      show("root?") { [Pathname.new("/").root?, Pathname.new("/a").root?, Pathname.new("").root?] }

    RUBY

    _(result).must_answer <<~'OUT'
      absolute?: [true, false]
      relative?: [false, true]
      root?: [true, false, false]
    OUT
  end

  it "the delegations read and write a tree this program builds" do
    result = ze0(<<~'RUBY')
      # `Pathname` is reachable with NO require: ruby 4.0 loads `pathname.so` before
      # the first line. This covers the whole surface -- the path ALGEBRA, which is
      # pure string work and never touches disk, and the delegations, which must
      # answer exactly what the same `File`/`Dir` call answers.

      require "pathname"   # a no-op here and in ruby 4.0: the class is already there
      require "tmpdir"

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      # The delegations, over a tree this program builds.
      Dir.mktmpdir do |tmp|
        root = Pathname.new(tmp)
        file = root + "hello.txt"
        file.write("hello\nworld\n")
        sub = root + "sub"
        sub.mkpath
        (sub + "deep").mkpath
        (sub + "deep" + "leaf.txt").write("leaf")

        show("write returns count") { (root + "w.txt").write("abcd") }
        show("read") { file.read }
        show("read n") { file.read(5) }
        show("binread") { file.binread(5) }
        show("readlines") { file.readlines }
        show("each_line") { r = []; file.each_line { |l| r << l }; r }
        show("open block") { file.open { |f| f.read(5) } }
        show("size") { file.size }
        show("size?") { [file.size?, (root + "empty").tap { |p| p.write("") }.size?] }
        show("zero?") { (root + "empty").zero? }
        show("empty? file") { (root + "empty").empty? }
        show("empty? dir") { [(root + "sub" + "deep").empty?, sub.empty?] }
        show("exist?") { [file.exist?, (root + "nope").exist?] }
        show("file?") { [file.file?, sub.file?] }
        show("directory?") { [file.directory?, sub.directory?] }
        show("ftype") { [file.ftype, sub.ftype] }
        show("readable?") { file.readable? }
        show("writable?") { file.writable? }
        show("executable?") { file.executable? }
        show("symlink?") { file.symlink? }
        show("stat class") { file.stat.class }
        show("lstat class") { file.lstat.class }
        show("mtime class") { file.mtime.class }
        show("atime class") { file.atime.class }
        show("ctime class") { file.ctime.class }
        show("chmod") { file.chmod(0o600) }
        show("mode after chmod") { format("%o", file.stat.mode & 0o777) }
        show("truncate") { f = (root + "t.txt"); f.write("abcdef"); f.truncate(3); f.read }
        show("rename") do
          f = (root + "old.txt")
          f.write("x")
          f.rename((root + "new.txt").to_s)
          [(root + "old.txt").exist?, (root + "new.txt").read]
        end
        show("delete") { f = (root + "gone.txt"); f.write("x"); f.delete; f.exist? }
        show("make_symlink") do
          link = root + "link"
          link.make_symlink(file.to_s)
          [link.symlink?, link.readlink.to_s == file.to_s]
        end
        show("make_link") do
          link = root + "hard"
          link.make_link(file.to_s)
          [link.exist?, link.symlink?]
        end
        show("realpath class") { file.realpath.class }
        show("realdirpath class") { file.realdirpath.class }
        show("children classes") { root.children.map(&:class).uniq }
        show("children sorted") { sub.children.map { |c| c.basename.to_s }.sort }
        show("children bare") { sub.children(false).map(&:to_s).sort }
        show("each_child") { r = []; sub.each_child { |c| r << c.basename.to_s }; r.sort }
        show("entries sorted") { sub.entries.map(&:to_s).sort }
        show("each_entry") { r = []; sub.each_entry { |c| r << c.to_s }; r.sort }
        show("glob") { root.glob("*.txt").map { |p| p.basename.to_s }.sort }
        show("glob block") do
          r = []
          root.glob("*.txt") { |p| r << p.basename.to_s }
          r.sort
        end
        show("find") { root.find.map { |p| p.relative_path_from(root).to_s }.sort }
        show("mkdir") { d = (root + "fresh"); d.mkdir; d.directory? }
        show("mkdir twice") { (root + "fresh").mkdir rescue "#{$!.class}: #{$!.message[/\A[^@]*/].strip}" }
        show("rmdir") { d = (root + "fresh"); d.rmdir; d.exist? }
        show("mkpath deep") { d = (root + "x" + "y" + "z"); d.mkpath; d.directory? }
        show("rmtree") { d = (root + "x"); d.rmtree; d.exist? }
        show("opendir") { root.opendir { |d| d.class } }
        show("mountpoint? tmp") { root.mountpoint? }
        show("mountpoint? root") { Pathname.new("/").mountpoint? }
      end

    RUBY

    _(result).must_answer <<~'OUT'
      write returns count: 4
      read: "hello\nworld\n"
      read n: "hello"
      binread: "hello"
      readlines: ["hello\n", "world\n"]
      each_line: ["hello\n", "world\n"]
      open block: "hello"
      size: 12
      size?: [12, nil]
      zero?: true
      empty? file: true
      empty? dir: [false, false]
      exist?: [true, false]
      file?: [true, false]
      directory?: [false, true]
      ftype: ["file", "directory"]
      readable?: true
      writable?: true
      executable?: false
      symlink?: false
      stat class: File::Stat
      lstat class: File::Stat
      mtime class: Time
      atime class: Time
      ctime class: Time
      chmod: 1
      mode after chmod: "600"
      truncate: "abc"
      rename: [false, "x"]
      delete: false
      make_symlink: [true, true]
      make_link: [true, false]
      realpath class: Pathname
      realdirpath class: Pathname
      children classes: [Pathname]
      children sorted: ["deep"]
      children bare: ["deep"]
      each_child: ["deep"]
      entries sorted: [".", "..", "deep"]
      each_entry: [".", "..", "deep"]
      glob: ["hello.txt", "new.txt", "t.txt", "w.txt"]
      glob block: ["hello.txt", "new.txt", "t.txt", "w.txt"]
      find: [".", "empty", "hard", "hello.txt", "link", "new.txt", "sub", "sub/deep", "sub/deep/leaf.txt", "t.txt", "w.txt"]
      mkdir: true
      mkdir twice: "Errno::EEXIST: File exists"
      rmdir: false
      mkpath deep: true
      rmtree: false
      opendir: Dir
      mountpoint? tmp: false
      mountpoint? root: true
    OUT
  end

  it "getwd and pwd answer a Pathname that agrees with Dir" do
    result = ze0(<<~'RUBY')
      # `Pathname` is reachable with NO require: ruby 4.0 loads `pathname.so` before
      # the first line. This covers the whole surface -- the path ALGEBRA, which is
      # pure string work and never touches disk, and the delegations, which must
      # answer exactly what the same `File`/`Dir` call answers.

      require "pathname"   # a no-op here and in ruby 4.0: the class is already there
      require "tmpdir"

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      show("getwd class") { Pathname.getwd.class }
      show("pwd agrees with Dir") { Pathname.pwd.to_s == Dir.pwd }
      show("Pathname.glob class") { Pathname.glob("*").class }
    RUBY

    _(result).must_answer <<~'OUT'
      getwd class: Pathname
      pwd agrees with Dir: true
      Pathname.glob class: Array
    OUT
  end

  it "poly string methods" do
    result = ze0(<<~'RUBY')
      # String methods on a poly receiver: a String that reached a slot the compiler
      # could only type as poly (a container read, a parameter two call sites
      # disagree about).
      #
      # #lines and #each_char had no poly arm at all, and #split lost its String arm
      # whenever a user class owned the name -- the bundled Pathname does, so
      # `require "pathname"` alone was enough to take it away. All three raised
      # NoMethodError naming String, on a value that is a String.

      require "pathname"

      mixed = ["one two\nthree\n", 1]
      s = mixed[0]

      p s.lines
      p s.split
      p s.split(" ")
      p s.split(nil)
      p s.split(/\s+/)

      acc = []
      s.each_char { |ch| acc.push(ch) if ch == "o" }
      p acc
      p s.each_char { |ch| }.class

      # the same names through a parameter two call sites disagree about
      def widened(x)
        x
      end
      p widened("a b").split(nil)
      p widened(1)

      module Util
        module_function

        def wrap(str, columns = 0)
          str.split(nil).join("-")
        end

        def chars_of(str)
          out = []
          str.each_char { |c| out << c }
          out
        end

        def lines_of(str)
          str.lines
        end
      end

      def poly_seed
        t = {}
        Util.wrap(t)
      end

      p Util.wrap("one two")
      p Util.chars_of("ab")
      p Util.lines_of("x\ny\n")

      # a Pathname still answers its own #split
      pn = Pathname.new("/a/b")
      p pn.split.map { |q| q.to_s }
    RUBY

    _(result).must_answer <<~'OUT'
      ["one two\n", "three\n"]
      ["one", "two", "three"]
      ["one", "two", "three"]
      ["one", "two", "three"]
      ["one", "two", "three"]
      ["o", "o"]
      String
      ["a", "b"]
      1
      "one-two"
      ["a", "b"]
      ["x\n", "y\n"]
      ["/a", "b"]
    OUT
  end
end
