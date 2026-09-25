# frozen_string_literal: true

require "spec_helper"

describe "Builtins: reading and writing" do
  it "dir full surface" do
    result = zr(<<~'RUBY')
      # Dir surface: foreach and each_child yield the same names as entries and
      # children. A chdir block restores the old directory and returns the
      # block's value. A bare chdir goes home. getwd, Dir[], delete and unlink
      # are aliases. empty? raises ENOENT for a missing path. home(user) reads
      # the passwd db, and glob takes an Array of patterns.
      dir = "/tmp/sp_t_dir1"
      Dir.mkdir(dir) unless Dir.exist?(dir)
      File.write("#{dir}/x", "")
      a = []; Dir.foreach(dir) { |e| a << e }; p a.sort
      b = []; Dir.each_child(dir) { |e| b << e }; p b
      p Dir.empty?(dir)
      File.delete("#{dir}/x")
      p Dir.empty?(dir)
      r0 = (Dir.empty?("/tmp/sp_no_such_dir_xyz") rescue $!.class); p r0
      File.write("/tmp/sp_t_dir1_file", "x")
      p Dir.empty?("/tmp/sp_t_dir1_file") rescue p :file_missing
      File.delete("/tmp/sp_t_dir1_file")
      g = []; File.write("#{dir}/a1", ""); File.write("#{dir}/a2", "")
      Dir.glob("#{dir}/*") { |e| g << e.sub("#{dir}/", "") }; p g.sort
      p Dir.glob(["#{dir}/a1", "#{dir}/a2"]).sort.map { |x| x.sub("#{dir}/", "") }
      p(Dir.chdir("/tmp") { 42 })
      p Dir.getwd.class
      p Dir["#{dir}/*"].sort.length
      Dir.mkdir("#{dir}/del")
      r = (Dir.delete("#{dir}/del") rescue $!.class); p r
      p Dir.exist?("#{dir}/del")
      o = Dir.pwd
      Dir.chdir
      p Dir.pwd == ENV["HOME"]
      Dir.chdir(o)
      p Dir.home(ENV["USER"]).class
      File.delete("#{dir}/a1"); File.delete("#{dir}/a2"); Dir.rmdir(dir)
      d001 = "/tmp/sp_t_glob_multi"
      Dir.mkdir(d001) unless Dir.exist?(d001)
      Dir.mkdir("#{d001}/sub") unless Dir.exist?("#{d001}/sub")
      File.write("#{d001}/top.txt", "")
      File.write("#{d001}/sub/deep.txt", "")
      p Dir.glob(["#{d001}/*.txt", "#{d001}/sub/*.txt"]).sort.map { |x| x.sub("#{d001}/", "") }
      p Dir.glob("#{d001}/*", File::FNM_DOTMATCH).sort.map { |x| x.sub("#{d001}/", "") }
      File.delete("#{d001}/top.txt"); File.delete("#{d001}/sub/deep.txt")
      Dir.rmdir("#{d001}/sub"); Dir.rmdir(d001)
    RUBY

    _(result).must_answer <<~'OUT'
      [".", "..", "x"]
      ["x"]
      false
      true
      Errno::ENOENT
      false
      ["a1", "a2"]
      ["a1", "a2"]
      42
      String
      2
      0
      false
      true
      String
      ["sub/deep.txt", "top.txt"]
      [".", "sub", "top.txt"]
    OUT
  end

  it "file and dir surface gaps" do
    result = zr(<<~'RUBY')
      # Dir.glob with an ABSOLUTE-path pattern + a `*` wildcard finds the files
      # under that path; FNM_DOTMATCH yields "." and
      # dotfiles but never ".."; File.mkfifo returns 0 and creates a FIFO;
      # File#lstat returns a File::Stat; File.exists? was removed in Ruby 3.2.

      d = "/tmp/sp_e2e_fdir_#{Process.pid}"
      Dir.mkdir(d) unless Dir.exist?(d)
      File.write("#{d}/a1", ""); File.write("#{d}/a2", ""); File.write("#{d}/.hid", "")
      p Dir.glob("#{d}/*").map { |x| x.sub("#{d}/", "") }.sort
      p Dir.glob("#{d}/*", File::FNM_DOTMATCH).map { |x| x.sub("#{d}/", "") }.sort
      fifo = "#{d}/f"
      p File.mkfifo(fifo)
      p File.stat(fifo).ftype
      p File.open("#{d}/a1") { |f| f.lstat.class }
      r = (begin; File.exists?("#{d}"); rescue => e; e.class; end); p r
      File.delete("#{d}/a1"); File.delete("#{d}/a2"); File.delete("#{d}/.hid"); File.delete(fifo)
      Dir.rmdir(d)
    RUBY

    _(result).must_answer <<~'OUT'
      ["a1", "a2"]
      [".", ".hid", "a1", "a2"]
      0
      "fifo"
      File::Stat
      NoMethodError
    OUT
  end

  it "file open is ios own row" do
    result = zr(<<~'RUBY')
      # `open`, `new`, `for_fd` and `sysopen` are IO's rows, and File INHERITS them.
      #
      # CRuby defines all four on IO's singleton class alone (`io.c`'s `Init_IO`; the
      # `rb_define_singleton_method(rb_cFile, "open", ...)` beside them sits inside an
      # `#if 0` that exists only to make RDoc document `File::open`). The RECEIVER
      # then decides what the first argument means, because `rb_io_s_open` calls
      # `klass.new`, which reaches `rb_file_initialize` for a File and
      # `rb_io_initialize` for an IO.
      #
      # That one indirection decides four separate answers, and zr -- which declared
      # `File.open` in File's own block -- got each of them wrong: `#owner` named
      # File, `File.for_fd` and `File.sysopen` did not exist at all, a subclass
      # receiver lost its class, and one method could not report `1..3` to File and
      # `1..2` to IO.
      require "tmpdir"
      require "fileutils"

      DIR = Dir.mktmpdir("zr_io_rows")
      SRC = File.join(DIR, "src.txt")
      File.binwrite(SRC, "hello\n")

      def row(name)
        puts "#{name}\t#{yield.inspect}"
      rescue StandardError => e
        puts "#{name}\t#{e.class}: #{e.message}"
      end

      # --- where the rows live -----------------------------------------------------
      %w[open new for_fd sysopen].each do |m|
        [IO, File].each { |k| row("#{k}.#{m} owner") { k.method(m).owner.to_s } }
      end
      row("File declares open")   { File.singleton_class.instance_methods(false).include?(:open) }
      row("IO declares open")     { IO.singleton_class.instance_methods(false).include?(:open) }
      row("File responds to open"){ File.respond_to?(:open) }
      row("one method, not two")  { File.method(:open).owner == IO.method(:open).owner }

      # --- the receiver decides the arity, because it decides the `initialize` -----
      row("IO.new range")    { IO.new }
      row("File.new range")  { File.new }
      row("IO.open range")   { IO.open }
      row("File.open range") { File.open }
      row("IO#initialize owner")   { IO.instance_method(:initialize).owner.to_s }
      row("File#initialize owner") { File.instance_method(:initialize).owner.to_s }

      # --- ...and what the first argument means -----------------------------------
      row("File.open takes a path") { File.open(SRC) { |f| [f.class.to_s, f.read(5)] } }
      row("IO.new takes a path")    { IO.new(SRC) }
      row("File.new takes an fd")   { fd = IO.sysopen(SRC); io = File.new(fd); r = [io.class.to_s, io.read(5)]; io.close; r }
      # `rb_io_s_for_fd` calls `rb_io_initialize` BY NAME rather than dispatching, so
      # a File receiver reads a descriptor here where `File.new` would still be
      # asking File what its argument means.
      row("File.for_fd takes an fd") { fd = IO.sysopen(SRC); io = File.for_fd(fd); r = [io.class.to_s, io.read(5)]; io.close; r }
      row("File.sysopen answers an fd") { fd = File.sysopen(SRC); io = IO.for_fd(fd); r = io.read(5); io.close; r }

      # --- a subclass receiver gets an instance of ITSELF --------------------------
      class Journal < File; end
      row("named File subclass") { Journal.open(SRC) { |f| f.class.to_s } }
      row("named subclass new")  { f = Journal.new(SRC); r = f.class.to_s; f.close; r }
      row("anonymous subclass")  { c = Class.new(File); c.open(SRC) { |f| f.class == c } }
      class Wire < IO; end
      row("named IO subclass")   { io = Wire.new(IO.sysopen(SRC)); r = io.class.to_s; io.close; r }
      row("File.for_fd subclass"){ io = Journal.for_fd(IO.sysopen(SRC)); r = io.class.to_s; io.close; r }

      # --- `new` never yields, so a block there is a mistake CRuby warns about ----
      f = File.new(SRC) { |x| :never_yielded }
      p [f.class.to_s, f.read(5)]
      f.close

      FileUtils.remove_entry(DIR)
      puts "ran to the end"
    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR'
      IO.open owner	"#<Class:IO>"
      File.open owner	"#<Class:IO>"
      IO.new owner	"#<Class:IO>"
      File.new owner	"#<Class:IO>"
      IO.for_fd owner	"#<Class:IO>"
      File.for_fd owner	"#<Class:IO>"
      IO.sysopen owner	"#<Class:IO>"
      File.sysopen owner	"#<Class:IO>"
      File declares open	false
      IO declares open	true
      File responds to open	true
      one method, not two	true
      IO.new range	ArgumentError: wrong number of arguments (given 0, expected 1..2)
      File.new range	ArgumentError: wrong number of arguments (given 0, expected 1..3)
      IO.open range	ArgumentError: wrong number of arguments (given 0, expected 1..2)
      File.open range	ArgumentError: wrong number of arguments (given 0, expected 1..3)
      IO#initialize owner	"IO"
      File#initialize owner	"File"
      File.open takes a path	["File", "hello"]
      IO.new takes a path	TypeError: no implicit conversion of String into Integer
      File.new takes an fd	["File", "hello"]
      File.for_fd takes an fd	["File", "hello"]
      File.sysopen answers an fd	"hello"
      named File subclass	"Journal"
      named subclass new	"Journal"
      anonymous subclass	true
      named IO subclass	"Wire"
      File.for_fd subclass	"Journal"
      ["File", "hello"]
      ran to the end
    OUT
      compiler/builtins/io_test.rb:65: warning: File::new() does not take block; use File::open() instead
    ERR
  end

  it "file stat surface" do
    result = zr(<<~'RUBY')
      path = "/tmp/sp_stat_surface_#{Process.pid}"
      File.write(path, "hello")
      st = File.stat(path)
      p st.size == 5
      p st.size? == 5
      p st.zero?
      p(st.nlink >= 1)
      p st.pipe?
      p st.readable?
      p st.writable?
      p st.blockdev?
      p st.chardev?
      p(st.ino > 0)
      p(st.blksize > 0)
      p(st.uid == Process.uid)
      st2 = File::Stat.new(path)
      p st2.size == 5
      p st2.file?
      File.delete(path)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      true
      false
      true
      true
      false
      false
      true
      true
      true
      true
      true
    OUT
  end

  it "file surface extended" do
    result = zr(<<~'RUBY')
      File.write("/tmp/sp_f2", "hello world")
      p File.ftype("/tmp/sp_f2")
      Dir.mkdir("/tmp/sp_f2dir") unless Dir.exist?("/tmp/sp_f2dir")
      p File.ftype("/tmp/sp_f2dir")
      p((File.ftype("/nonex") rescue $!.class))
      p File.writable?("/tmp/sp_f2")
      p File.executable?("/tmp/sp_f2")
      p File.size?("/tmp/sp_f2")
      p File.size?("/nonex")
      File.write("/tmp/sp_f0", "")
      p File.size?("/tmp/sp_f0")
      p File.pipe?("/tmp/sp_f2")
      p File.identical?("/tmp/sp_f2", "/tmp/sp_f2")
      p File.identical?("/tmp/sp_f2", "/tmp/sp_f2dir")
      p File.atime("/tmp/sp_f2").class
      p File.ctime("/tmp/sp_f2").class
      p File.realpath("/tmp/../tmp/sp_f2") == File.join(File.realpath("/tmp"), "sp_f2")
      p File.read("/tmp/sp_f2", 5)
      p File.read("/tmp/sp_f2", 500)
      p File.chmod(0644, "/tmp/sp_f2")
      p File.truncate("/tmp/sp_f2", 5)
      p File.read("/tmp/sp_f2")
      File.write("/tmp/sp_f2", "hello")
      File.write("/tmp/sp_f2", "XY", 1)
      p File.read("/tmp/sp_f2")
      p File.write("/tmp/sp_f2", "AB", mode: "a")
      p File.read("/tmp/sp_f2")
      File.foreach("/tmp/sp_f2") { |line| p line }
      p File.split("/a/b/c.rb")
      p File.absolute_path("c.rb", "/a/b")
      p File.path("/a/b")
      p File.fnmatch("*.rb", "c.rb")
      p File.fnmatch("a*", "bc")
      p File.fnmatch?("*.rb", "x.rb")
      f = File.new("/tmp/sp_f2")
      p f.read
      f.close
      f2 = File.open("/tmp/sp_f2")
      p f2.size
      p f2.mtime.class
      p f2.chmod(0644)
      f2.close
      st = File.stat("/tmp/sp_f2")
      p st.size
      p st.mtime.class
      p001 = "/tmp/sp_bug_open_intmode"
      File.open(p001, File::WRONLY | File::CREAT | File::TRUNC) { |f| f.write("x") }
      p File.read(p001)
      File.delete(p001)
      r001 = (begin; File.open("/tmp/sp_modekw", mode: "w") { |f| f.write("x") }; File.read("/tmp/sp_modekw"); rescue => e001; e001.class; end)
      p r001
      File.delete("/tmp/sp_modekw") if File.exist?("/tmp/sp_modekw")
      p FileTest.exist?("/tmp/sp_f2")
      p FileTest.file?("/tmp/sp_f2")
      p FileTest.directory?("/tmp/sp_f2dir")
      p File.dirname("/a/b/c", 2)
      p File.dirname("a/b/c/d", 3)
      p File.dirname("/a", 5)
      File.delete("/tmp/sp_f2", "/tmp/sp_f0")
      Dir.rmdir("/tmp/sp_f2dir")
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      "file"
      "directory"
      Errno::ENOENT
      true
      false
      11
      nil
      nil
      false
      true
      false
      Time
      Time
      true
      "hello"
      "hello world"
      1
      0
      "hello"
      "hXYlo"
      2
      "hXYloAB"
      "hXYloAB"
      ["/a/b", "c.rb"]
      "/a/b/c.rb"
      "/a/b"
      true
      false
      true
      "hXYloAB"
      7
      Time
      0
      7
      Time
      "x"
      "x"
      true
      true
      true
      "/a"
      "a"
      "/"
      done
    OUT
  end

  it "io class methods surface" do
    result = zr(<<~'RUBY')
      # IO class methods (read/write/readlines/foreach/pipe/copy_stream/sysopen),
      # Kernel#open, read-into-buffer, puts with an Array, readlines separators.
      File.write("/tmp/sp_io4.txt", "one\ntwo\n")
      p IO.read("/tmp/sp_io4.txt")
      p IO.readlines("/tmp/sp_io4.txt")
      IO.write("/tmp/sp_io4.txt", "abc")
      p IO.read("/tmp/sp_io4.txt")
      IO.foreach("/tmp/sp_io4.txt") { |l| p l }
      rw = IO.pipe
      p rw.class
      w = rw[1]
      r = rw[0]
      w.write("ping")
      w.close
      p r.read
      r.close
      File.write("/tmp/sp_io4.txt", "hello")
      p IO.copy_stream("/tmp/sp_io4.txt", "/tmp/sp_io4b.txt")
      p File.read("/tmp/sp_io4b.txt")
      fd = IO.sysopen("/tmp/sp_io4.txt")
      p fd.class
      open("/tmp/sp_io4.txt") { |f| p f.read }
      File.open("/tmp/sp_io4.txt") do |f|
        b001 = ""
        f.read(5, b001)
        p b001
      end
      File.open("/tmp/sp_io4.txt", "w") { |f| f.puts([1, 2, 3]) }
      p File.read("/tmp/sp_io4.txt")
      File.write("/tmp/sp_io4.txt", "foo\nbar\n")
      p File.readlines("/tmp/sp_io4.txt", "o")
      File.open("/tmp/sp_io4.txt") { |f| p f.readlines("o") }
      File.open("/tmp/sp_io4.txt") { |f| p f.readlines(chomp: true) }
      File.delete("/tmp/sp_io4.txt", "/tmp/sp_io4b.txt")
    RUBY

    _(result).must_answer <<~'OUT'
      "one\ntwo\n"
      ["one\n", "two\n"]
      "abc"
      "abc"
      Array
      "ping"
      5
      "hello"
      Integer
      "hello"
      "hello"
      "1\n2\n3\n"
      ["fo", "o", "\nbar\n"]
      ["fo", "o", "\nbar\n"]
      ["foo", "bar"]
    OUT
  end

  it "io file stat rows", only: "macos" do
    result = zr(<<~'RUBY')

      # The `IO`, `File` and `File::Stat` rows that answer facts the runtime already
      # holds: the timestamp trio off one fstat, the device-number split, the
      # real-uid access predicates, and the raw ioctl/syswrite pair.

      require "tmpdir"

      Dir.mktmpdir do |dir|
        path = File.join(dir, "sample.txt")
        File.write(path, "hello\n")

        File.open(path) do |f|
          puts "atime: #{f.atime.class}"
          puts "ctime: #{f.ctime.class}"
          puts "birthtime: #{f.birthtime.class}"
          puts "mtime == stat.mtime: #{f.mtime == f.stat.mtime}"
          puts "size: #{f.size}"
          puts "timeout default: #{f.timeout.inspect}"
          f.timeout = 5
          puts "timeout set: #{f.timeout.inspect}"
        end

        st = File.stat(path)
        puts "dev split: #{st.dev_major.is_a?(Integer) && st.dev_minor.is_a?(Integer)}"
        puts "rdev on a regular file: #{[st.rdev_major, st.rdev_minor].inspect}"
        puts "readable_real?: #{st.readable_real?}"
        puts "writable_real?: #{st.writable_real?}"
        puts "executable_real?: #{st.executable_real?}"

        File.chmod(0o755, path)
        puts "executable_real? after chmod: #{File.stat(path).executable_real?}"

        # `chown` to the ids the file already has is a no-op that still reports the
        # count, so it works without privileges.
        puts "chown: #{File.chown(st.uid, st.gid, path)}"
        puts "lchown: #{File.lchown(nil, nil, path)}"
        puts "lutime: #{File.lutime(Time.at(1_000_000), Time.at(1_000_000), path)}"
        puts "mtime after lutime: #{File.stat(path).mtime.to_i}"

        # `syswrite` answers the byte count.
        File.open(path, "w") { |f| puts "syswrite: #{f.syswrite("abcd")}" }
        puts "content: #{File.read(path).inspect}"

        # A leading BOM names the stream's external encoding; without one, nothing
        # changes and the answer is nil.
        bom = File.join(dir, "bom.txt")
        File.binwrite(bom, "\xEF\xBB\xBFhi")
        File.open(bom, "rb") do |f|
          puts "binmode?: #{f.binmode?}"
          puts "bom: #{f.set_encoding_by_bom.inspect}"
          puts "after bom: #{f.read.inspect}"
        end
        File.open(path, "rb") do |f|
          puts "no bom: #{f.set_encoding_by_bom.inspect}"
        end
      end

      # `IO#puts`/`#print` are public methods of IO -- not Kernel's private pair.
      puts "IO#puts listed: #{IO.instance_methods(false).include?(:puts)}"
      puts "IO#print listed: #{IO.instance_methods(false).include?(:print)}"
      puts "Kernel#puts hidden: #{Kernel.instance_methods(false).include?(:puts)}"
      puts "Kernel#puts private: #{Kernel.private_instance_methods(false).include?(:puts)}"
      STDOUT.print "print to a stream\n"
      STDOUT.puts "puts to a stream"

      # `ioctl` reaches the kernel: FIONREAD on a pipe reports the bytes waiting.
      r, w = IO.pipe
      w.write("1234")
      w.flush
      buf = [0].pack("l!")
      r.ioctl(0x4004667F, buf)
      puts "fionread: #{buf.unpack1("l!")}"
      r.close
      w.close
    RUBY

    _(result).must_answer <<~'OUT'
      atime: Time
      ctime: Time
      birthtime: Time
      mtime == stat.mtime: true
      size: 6
      timeout default: nil
      timeout set: 5
      dev split: true
      rdev on a regular file: [0, 0]
      readable_real?: true
      writable_real?: true
      executable_real?: false
      executable_real? after chmod: true
      chown: 1
      lchown: 1
      lutime: 1
      mtime after lutime: 1000000
      syswrite: 4
      content: "abcd"
      binmode?: true
      bom: #<Encoding:UTF-8>
      after bom: "hi"
      no bom: nil
      IO#puts listed: true
      IO#print listed: true
      Kernel#puts hidden: false
      Kernel#puts private: true
      print to a stream
      puts to a stream
      fionread: 4
    OUT
  end

  it "io handle value surface" do
    result = zr(<<~'RUBY')
      # IO handle values: #class discrimination, sync, write capture, flush self,
      # close nil, << through an alias, and $stdout as a first-class IO value.
      File.write("/tmp/sp_io1.txt", "hi")
      File.open("/tmp/sp_io1.txt") { |f| p f.fileno.class }
      File.open("/tmp/sp_io1.txt") { |f| p f.class }
      p $stdout.class
      p STDOUT.sync
      File.open("/tmp/sp_io1.txt", "w") do |f|
        n = f.write("hi")
        p n
        p f.flush.equal?(f)
      end
      f = File.open("/tmp/sp_io1.txt")
      p f.close
      File.open("/tmp/sp_io1.txt", "w") do |f|
        h = f
        h << "a"
        h << "b"
      end
      p File.read("/tmp/sp_io1.txt")
      File.delete("/tmp/sp_io1.txt")
    RUBY

    _(result).must_answer <<~'OUT'
      Integer
      File
      IO
      false
      2
      true
      nil
      "ab"
    OUT
  end

  it "io instance method surface" do
    result = zr(<<~'RUBY')
      # ungetbyte pushes a byte back for the next read; binmode/binmode?,
      # autoclose=/autoclose?, to_io (self), close_on_exec?, pread/pwrite at a
      # fixed offset, advise (nil), close_write on a read-only file (IOError),
      # reopen (rebinds to another file), each_codepoint.

      pth = "/tmp/sp_e2e_io_#{Process.pid}.tmp"
      File.write(pth, "hi\n")
      File.open(pth) do |f|
        p f.readbyte
        f.ungetbyte(104)
        p f.readbyte
        p f.binmode?
        f.binmode
        p f.binmode?
        p f.to_io.equal?(f)
        p f.close_on_exec?
        p f.pread(2, 0)
        p f.advise(:normal)
        p((f.autoclose = false))
        p f.autoclose?
        r = (begin; f.close_write; rescue => e; e.class; end); p r
      end
      File.open(pth, "r+") { |f| p f.pwrite("X", 0) }
      p File.read(pth)
      File.write("/tmp/sp_e2e_io2_#{Process.pid}.tmp", "other")
      File.open(pth) { |f| File.open("/tmp/sp_e2e_io2_#{Process.pid}.tmp") { |g| f.reopen(g); p f.read } }
      File.open(pth) { |f| cps = []; f.each_codepoint { |c| cps << c }; p cps }
      File.delete(pth); File.delete("/tmp/sp_e2e_io2_#{Process.pid}.tmp")
    RUBY

    _(result).must_answer <<~'OUT'
      104
      104
      false
      true
      true
      true
      "hi"
      nil
      false
      false
      IOError
      1
      "Xi\n"
      "other"
      [88, 105, 10]
    OUT
  end

  it "io instance read surface" do
    result = zr(<<~'RUBY')
      # IO instance reads: gets separator/limit/chomp, readline EOFError, lineno,
      # getc/readchar/getbyte, each_line separator + fresh strings, printf/putc,
      # pos=, readpartial, flock, each_char/each_byte, multi-arg write, sysseek.
      File.write("/tmp/sp_io3.txt", "hello\nworld\n")
      File.open("/tmp/sp_io3.txt") { |f| p f.gets("o") }
      File.open("/tmp/sp_io3.txt") { |f| p f.gets(3) }
      File.open("/tmp/sp_io3.txt") { |f| p f.gets(chomp: true) }
      File.open("/tmp/sp_io3.txt") do |f|
        f.read
        r = (f.readline rescue $!.class)
        p r
      end
      File.open("/tmp/sp_io3.txt") { |f| f.gets; p f.lineno }
      File.open("/tmp/sp_io3.txt") { |f| p f.getc }
      File.open("/tmp/sp_io3.txt") { |f| p f.readchar }
      File.open("/tmp/sp_io3.txt") { |f| p f.getbyte }
      File.open("/tmp/sp_io3.txt") { |f| f.each_line("o") { |l| p l } }
      File.write("/tmp/sp_io3b.txt", "one\ntwo\nthree\n")
      File.open("/tmp/sp_io3b.txt") do |f|
        lines = []
        f.each_line { |l| lines << l }
        p lines
      end
      File.open("/tmp/sp_io3.txt", "w") { |f| f.printf("%03d-%s", 7, "x") }
      p File.read("/tmp/sp_io3.txt")
      File.open("/tmp/sp_io3.txt", "w") { |f| p f.putc(65); f.putc("bc") }
      p File.read("/tmp/sp_io3.txt")
      File.write("/tmp/sp_io3.txt", "hello")
      File.open("/tmp/sp_io3.txt") { |f| f.pos = 2; p f.read }
      File.open("/tmp/sp_io3.txt") { |f| p f.readpartial(3) }
      File.open("/tmp/sp_io3.txt") { |f| p f.flock(File::LOCK_EX) }
      File.open("/tmp/sp_io3.txt") { |f| cs = []; f.each_char { |ch| cs << ch }; p cs }
      File.open("/tmp/sp_io3.txt") { |f| bs = []; f.each_byte { |bb| bs << bb }; p bs }
      File.open("/tmp/sp_io3.txt", "w") { |f| p f.write("a", "b", "c") }
      p File.read("/tmp/sp_io3.txt")
      File.open("/tmp/sp_io3.txt") { |f| p f.sysseek(2) }
      File.delete("/tmp/sp_io3.txt", "/tmp/sp_io3b.txt")
    RUBY

    _(result).must_answer <<~'OUT'
      "hello"
      "hel"
      "hello"
      EOFError
      1
      "h"
      "h"
      104
      "hello"
      "\nwo"
      "rld\n"
      ["one\n", "two\n", "three\n"]
      "007-x"
      65
      "Ab"
      "llo"
      "hel"
      0
      ["h", "e", "l", "l", "o"]
      [104, 101, 108, 108, 111]
      3
      "abc"
      2
    OUT
  end
end
