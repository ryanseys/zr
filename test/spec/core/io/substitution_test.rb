# frozen_string_literal: true

require "spec_helper"

describe "IO: substitution" do
  it "dir glob base keyword" do
    result = ze0(<<~'RUBY')
      require "tmpdir"

      Dir.mktmpdir do |dir|
        Dir.mkdir(File.join(dir, "sub"))
        File.write(File.join(dir, "a.txt"), "x")
        File.write(File.join(dir, "sub", "b.txt"), "y")
        p Dir.glob("**/*.txt", base: dir).sort
        p Dir.glob("*.txt", base: dir).sort
        p Dir.glob("**/*.txt", base: dir).map { |f| File.file?(File.join(dir, f)) }
      end
    RUBY

    _(result).must_answer <<~'OUT'
      ["a.txt", "sub/b.txt"]
      ["a.txt"]
      [true, true]
    OUT
  end

  it "dir glob recursive" do
    result = ze0(<<~'RUBY')
      # Dir.glob with a recursive `**` component walks the subtree; the text before
      # `**` is preserved in each result and a cwd-anchored pattern yields bare
      # relative paths, sorted (Ruby 3.0+). Uses a cwd-relative tree so it works
      # anywhere, and removes everything it creates.
      root = "sptest_glob_rec"
      Dir.mkdir(root) unless Dir.exist?(root)
      Dir.mkdir("#{root}/a") unless Dir.exist?("#{root}/a")
      Dir.mkdir("#{root}/a/b") unless Dir.exist?("#{root}/a/b")
      File.write("#{root}/x.rbs", "")
      File.write("#{root}/a/y.rbs", "")
      File.write("#{root}/a/b/z.rbs", "")
      File.write("#{root}/a/keep.txt", "")

      puts Dir.glob("#{root}/**/*.rbs").join(",")   # all three, prefixed with root
      puts Dir.glob("#{root}/**/*.rbs").length       # 3
      puts Dir.glob("#{root}/*.rbs").join(",")       # only x.rbs (single level)
      puts Dir.glob("#{root}/**/*.txt").join(",")    # keep.txt

      File.delete("#{root}/x.rbs")
      File.delete("#{root}/a/y.rbs")
      File.delete("#{root}/a/b/z.rbs")
      File.delete("#{root}/a/keep.txt")
      Dir.rmdir("#{root}/a/b")
      Dir.rmdir("#{root}/a")
      Dir.rmdir(root)
    RUBY

    _(result).must_answer <<~'OUT'
      sptest_glob_rec/a/b/z.rbs,sptest_glob_rec/a/y.rbs,sptest_glob_rec/x.rbs
      3
      sptest_glob_rec/x.rbs
      sptest_glob_rec/a/keep.txt
    OUT
  end

  it "dir handle objects" do
    result = ze0(<<~'RUBY')
      # Dir.new/Dir.open handles: #read/#each/#each_child/#children/#entries/
      # #path/#rewind/#close, the block form, and Errno::ENOENT on a missing path.
      dir = "/tmp/sp_dirh"
      Dir.mkdir(dir) unless Dir.exist?(dir)
      File.write("#{dir}/x", "")
      File.write("#{dir}/y", "")
      d = Dir.new(dir)
      p d.class
      p d.path
      e = []
      d.each { |n| e << n }
      p e.sort
      d.rewind
      p d.read.class
      d.close
      p Dir.open(dir).class
      r = Dir.open(dir) { |dd| dd.children.sort }
      p r
      p((Dir.new("/nonexistent_zz") rescue $!.class))
      cs = []
      d2 = Dir.new(dir)
      d2.each_child { |n| cs << n }
      p cs.sort
      p d2.entries.sort
      d2.close
      File.delete("#{dir}/x", "#{dir}/y")
      Dir.rmdir(dir)
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      Dir
      "/tmp/sp_dirh"
      [".", "..", "x", "y"]
      String
      Dir
      ["x", "y"]
      Errno::ENOENT
      ["x", "y"]
      [".", "..", "x", "y"]
      done
    OUT
  end

  it "dir methods" do
    result = ze0(<<~'RUBY')
      # Dir singleton methods: mkdir / rmdir / exist? round-trip, glob (sorted
      # in Ruby 3.0+), and home. Uses a cwd-relative directory (not /tmp) so it
      # works on the Windows MinGW build too; the test runs in a fresh temp cwd
      # and removes everything it creates.
      d = "sptest_spinel_dir"
      Dir.mkdir(d) unless Dir.exist?(d)
      puts Dir.exist?(d)
      File.write("#{d}/b.txt", "x")
      File.write("#{d}/a.txt", "y")
      puts Dir.glob("#{d}/*.txt").join(",")
      File.delete("#{d}/a.txt")
      File.delete("#{d}/b.txt")
      Dir.rmdir(d)
      puts Dir.exist?(d)
      puts(Dir.home.length > 0)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      sptest_spinel_dir/a.txt,sptest_spinel_dir/b.txt
      false
      true
    OUT
  end

  it "file dir extended" do
    result = ze0(<<~'RUBY')
      base = "/tmp/zeo_w1i_example"

      # Start clean without external requires: remove any leftover entries.
      if Dir.exist?(base)
        Dir.each_child(base) do |name|
          path = File.join(base, name)
          File.directory?(path) ? Dir.rmdir(path) : File.delete(path)
        end
        Dir.rmdir(base)
      end
      Dir.mkdir(base)

      File.write(File.join(base, "a.txt"), "one\ntwo\nthree\n")
      File.write(File.join(base, "b.log"), "x")
      Dir.mkdir(File.join(base, "sub"))

      # File.ftype distinguishes file vs directory
      p File.ftype(File.join(base, "a.txt"))
      p File.ftype(File.join(base, "sub"))

      # File.foreach yields lines; chomp: strips terminators
      File.foreach(File.join(base, "a.txt")) { |line| print "L:", line }
      p File.foreach(File.join(base, "a.txt"), chomp: true).to_a

      # Dir.foreach yields entries (including . and ..); block form returns nil
      entries = []
      result = Dir.foreach(base) { |e| entries << e }
      p entries.sort
      p result

      # Dir.foreach without a block is an Enumerator
      p Dir.foreach(base).to_a.sort
    RUBY

    _(result).must_answer <<~'OUT'
      "file"
      "directory"
      L:one
      L:two
      L:three
      ["one", "two", "three"]
      [".", "..", "a.txt", "b.log", "sub"]
      nil
      [".", "..", "a.txt", "b.log", "sub"]
    OUT
  end

  it "file mtime" do
    result = ze0(<<~'RUBY')
      filename = "test_mtime_temp.txt"
      File.write(filename, "mtime test")
      begin
        t = File.mtime(filename)
        puts t.class
        # Year should be an integer
        puts t.year.class
      ensure
        File.delete(filename)
      end
    RUBY

    _(result).must_answer "Time\nInteger\n"
  end

  it "file path predicates" do
    result = ze0(<<~'RUBY')
      p File.join("a/", "b")
      p File.join("a", "", "b")
      p File.join("a", "/b")
      p File.join("", "a")
      p File.join("a//", "b")
      p File.join("a//", "//b")
      p File.join(["a", "b"], "c")
      p File.join("a", ["b", ["c"]])
      p File.basename("/a/b/")
      p File.basename("/")
      p File.basename("a/b//")
      p File.basename("///")
      p File.basename("")
      p File.basename("b")
      p File.basename("/a/b/c.rb", ".rb")
      p File.basename("/a/b/c.rb", ".*")
      p File.basename("c.tar.gz", ".*")
      p File.basename("c.rb", ".py")
      File.write("/tmp/sp_file_zero_empty.txt", "")
      p File.size("/tmp/sp_file_zero_empty.txt")
      p File.zero?("/tmp/sp_file_zero_empty.txt")
      p File.empty?("/tmp/sp_file_zero_empty.txt")
      File.delete("/tmp/sp_file_zero_empty.txt")
      p File.zero?("/tmp")
      p File.zero?("/dev/null")
      p File.zero?("/nonexistent_zzz")
      r = (File.exists?("/tmp") rescue $!.class); p r
      r2 = (Dir.exists?("/tmp") rescue $!.class); p r2
      p File::ALT_SEPARATOR
      p File::ALT_SEPARATOR.nil?
    RUBY

    _(result).must_answer <<~'OUT'
      "a/b"
      "a/b"
      "a/b"
      "/a"
      "a//b"
      "a//b"
      "a/b/c"
      "a/b/c"
      "b"
      "/"
      "b"
      "/"
      ""
      "b"
      "c"
      "c"
      "c.tar"
      "c.rb"
      0
      true
      true
      false
      true
      false
      NoMethodError
      NoMethodError
      nil
      true
    OUT
  end

  it "file seek tell rewind" do
    result = ze0(<<~'RUBY')
      path = "spinel_file_seek_test_#{Process.pid}.txt"
      File.open(path, "w") do |f|
        f.write("HELLOWORLDABCDEF")
      end

      f = File.open(path, "r")
      puts f.read(4)
      puts f.tell
      puts f.pos
      f.seek(10)
      puts f.read(3)
      puts f.tell
      f.seek(2, IO::SEEK_CUR)
      puts f.read(1)
      f.seek(-6, IO::SEEK_END)
      puts f.read(6)
      f.seek(5, IO::SEEK_SET)
      puts f.read(5)
      f.rewind
      puts f.tell
      puts f.read(5)
      f.close

      File.delete(path) if File.exist?(path)
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      HELL
      4
      4
      ABC
      13
      F
      ABCDEF
      WORLD
      0
      HELLO
      done
    OUT
  end

  it "file stat io pipe and io read family" do
    result = ze0(<<~'RUBY')
      # File::Stat (class + readers), File.stat/File#stat, IO.pipe
      # (a plain-IO reader/writer pair), the IO instance read family
      # (gets separator/limit/chomp, getc/getbyte, lineno), IO class methods
      # (IO.read/write/copy_stream), and FileTest.

      path = "/tmp/sp_e2e_stat_#{Process.pid}.txt"
      File.write(path, "hello\nworld\n")
      st = File.stat(path)
      p st.class
      p st.size
      p st.file?
      p st.directory?
      File.open(path) { |f| p f.stat.class }
      File.open(path) { |f| p f.gets("o") }
      File.open(path) { |f| p f.gets(3) }
      File.open(path) { |f| p f.gets(chomp: true); p f.lineno }
      File.open(path) { |f| p f.getc; p f.getbyte }
      p FileTest.file?(path)
      p FileTest.directory?(path)
      r, w = IO.pipe
      p r.class
      w.write("ping")
      w.close
      p r.read
      r.close
      p IO.read(path, 5)
      File.delete(path)
    RUBY

    _(result).must_answer <<~'OUT'
      File::Stat
      12
      true
      false
      File::Stat
      "hello"
      "hel"
      "hello"
      1
      "h"
      101
      true
      false
      IO
      "ping"
      "hello"
    OUT
  end

  it "file stat io read family" do
    result = ze0(<<~'RUBY')
      # File::Stat, IO.pipe, the IO instance read family, IO class methods, and
      # FileTest -- the file/IO surface. Output is path-independent so the golden is
      # stable.
      path = "/tmp/sp_ex_stat_#{Process.pid}.txt"
      File.write(path, "hello\nworld\n")

      st = File.stat(path)
      p st.class
      p st.size
      p st.file?
      p st.directory?
      File.open(path) { |f| p f.stat.class }

      File.open(path) { |f| p f.gets("o") }
      File.open(path) { |f| p f.gets(3) }
      File.open(path) { |f| p f.gets(chomp: true); p f.lineno }
      File.open(path) { |f| p f.getc; p f.getbyte }
      File.open(path) { |f| p f.readlines }
      File.open(path) { |f| f.pos = 6; p f.read }

      p FileTest.file?(path)
      p FileTest.directory?(path)

      r, w = IO.pipe
      p r.class
      w.write("ping")
      w.close
      p r.read
      r.close

      p IO.read(path, 5)
      p IO.readlines(path)
      File.delete(path)
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      File::Stat
      12
      true
      false
      File::Stat
      "hello"
      "hel"
      "hello"
      1
      "h"
      101
      ["hello\n", "world\n"]
      "world\n"
      true
      false
      IO
      "ping"
      "hello"
      ["hello\n", "world\n"]
      done
    OUT
  end

  it "file whole file io" do
    result = ze0(<<~'RUBY')
      # Whole-file read/write/readlines, including `chomp: true`.

      dir = File.join(ENV.fetch("TMPDIR", "/tmp"), "zeo_e2e_rw_#{Process.pid}")
      Dir.mkdir(dir)
      begin
        path = File.join(dir, "lines.txt")
        n = File.write(path, "alpha\nbeta\ngamma\n")
        p n
        p File.read(path)
        p File.readlines(path)
        p File.readlines(path, chomp: true)
        File.write(path, "no trailing newline")
        p File.readlines(path)
        File.delete(path)
      ensure
        Dir.rmdir(dir)
      end
    RUBY

    _(result).must_answer <<~'OUT'
      17
      "alpha\nbeta\ngamma\n"
      ["alpha\n", "beta\n", "gamma\n"]
      ["alpha", "beta", "gamma"]
      ["no trailing newline"]
    OUT
  end

  it "file write at tail position" do
    result = ze0(<<~'RUBY')
      # Followup to #549. File.write recognized at expression level
      # (alongside binwrite). Statement-context calls to File.write
      # were already routed through compile_control_call_stmt and
      # emitted sp_file_write directly. Tail-position calls in a
      # method body fall through to compile_expr, which only
      # recognized binwrite; without the alias here, File.write
      # warned "cannot resolve call to 'write' on int" and returned
      # the literal 0, silently dropping the side effect.

      def store(path, data)
        File.write(path, data)
      end

      store("spinel_file_write_test.txt", "ok\n")
      puts File.read("spinel_file_write_test.txt")
      File.delete("spinel_file_write_test.txt")
    RUBY

    _(result).must_answer "ok\n"
  end

  it "gets limit keeps a whole character" do
    result = ze0(<<~'RUBY')
      # A gets limit that falls inside a character reads on to that
      # character's end, so a line never ends in half a character.
      path = "/tmp/ze0_a_gets_limit_keeps_a_whole_character.txt"
      File.write(path, "alpha\nbéta\n日本語\n")
      File.open(path) { |f| p f.gets(nil, 8), f.gets(3), f.gets(1), f.gets(4), f.gets }
      File.open(path) { |f| p f.gets("\n", 7), f.gets(2), f.gets(5) }
      File.delete(path)
    RUBY

    _(result).must_answer <<~'OUT'
      "alpha\nbé"
      "ta\n"
      "日"
      "本語"
      "\n"
      "alpha\n"
      "bé"
      "ta\n"
    OUT
  end

  it "glob directory trailing slash" do
    result = ze0(<<~'RUBY')
      require "tmpdir"

      Dir.mktmpdir do |d|
        Dir.mkdir(File.join(d, "sub"))
        Dir.chdir(d) { p Dir.glob("**/").sort }
      end
    RUBY

    _(result).must_answer "[\"sub/\"]\n"
  end

  it "a file written, closed and read back answers its lines, then nil at the end" do
    result = ze0(<<~'RUBY')
      path = "i1006_tmp.txt"
      File.delete(path) if File.exist?(path)

      f = File.open(path, "w")
      f.write("hello\n")
      f.write("world\n")
      f.close
      puts f.closed?

      g = File.open(path, "r")
      puts g.read
      puts g.eof?
      g.close

      h = File.open(path, "r")
      puts h.gets.chomp
      puts h.gets.chomp
      puts h.gets.nil?
      h.close

      File.delete(path)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      hello
      world
      true
      hello
      world
      true
    OUT
  end

  it "io readiness and dir fd" do
    result = ze0(<<~'RUBY')
      # IO readiness and Dir-from-descriptor coverage, all implemented: IO.select
      # over pipes with a zero timeout, IO#wait_readable/_writable/_priority/#wait,
      # IO.for_fd, Dir.for_fd/fchdir errors, and a Dir singleton NoMethodError.
      p IO.select(nil, nil, nil, 0)
      r, w = IO.pipe
      w.write("x")
      w.flush
      p IO.select([r], nil, nil, 0).class
      p IO.select([r], nil, nil, 0)[0].size
      p IO.select(nil, nil, [r], 0)      # no priority data: nil, not the pipe
      p r.wait_readable(0).class
      p w.wait_writable(0).class
      p r.wait_priority(0).nil?          # a pipe with plain data is not priority-readable
      p r.wait(0, :read).class
      r.close
      w.close

      dir = "spinel_iofd_test_dir"
      Dir.mkdir(dir) unless Dir.exist?(dir)
      path = File.join(dir, "sample.txt")
      File.write(path, "hello\n")

      f = File.open(path)
      i = IO.for_fd(f.fileno, autoclose: false)
      p i.class
      p i.fileno == f.fileno
      f.close
      e = (IO.for_fd(-1) rescue $!.class); p e

      p Dir.exist?(dir)
      n = (Dir.bogus_xyz rescue $!.class); p n
      m = (Dir.bogus_xyz rescue $!.message); p m
      b = (Dir.for_fd(9999) rescue $!.class); p b
      c = (Dir.fchdir(9999) rescue $!.class); p c

      d = Dir.for_fd(File.open(dir).fileno)
      p d.class
      d.close

      File.delete(path)
      Dir.rmdir(dir)
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      Array
      1
      nil
      IO
      IO
      true
      IO
      IO
      true
      Errno::EBADF
      true
      NoMethodError
      "undefined method 'bogus_xyz' for class Dir"
      Errno::EBADF
      Errno::EBADF
      Dir
    OUT
  end

  it "io stat from fd" do
    result = ze0(<<~'RUBY')
      # Ruby has no File.fstat / IO.fstat; the way to a File::Stat from a descriptor
      # is IO.new(fd).stat, which needed three things. IO.new(fd) is the descriptor
      # form of IO.for_fd. A handle opened that way has no path, so its stat has to
      # come from fstat(2) rather than from stat(path). And the stat accessors were
      # gated on the receiver still spelling `sp_file_stat_handle(...)`, so they were
      # lost the moment the stat was stored in a local.
      path = "/tmp/spinel_io_stat_from_fd.txt"
      File.write(path, "hello")

      f = File.open(path)
      st = f.stat
      p st.size
      p st.mode.class
      p st.file?
      p st.directory?
      p st.ftype

      # through the descriptor, with no path behind it
      io = IO.new(f.fileno)
      p io.stat.size
      p io.stat.ftype

      fd_st = io.stat
      p fd_st.size
      p fd_st.mode.class

      # a directory handle still answers by path
      d = File.open("/tmp")
      p d.stat.directory?
      p d.stat.file?
      d.close

      f.close
      File.delete(path)
      puts "ok"
    RUBY

    _(result).must_answer <<~'OUT'
      5
      Integer
      true
      false
      "file"
      5
      "file"
      5
      Integer
      true
      false
      ok
    OUT
  end

  it "wave followups 2833" do
    result = ze0(<<~'RUBY')
      # Wave follow-ups: File.foreach return values (#2833), Dir.open block
      # children (#2834), boolean operator Method objects (#2835), deferred
      # handler captures (#2836), NoMethodError#args (#2837), find_index
      # pair destructuring.
      path = "/tmp/sp_ff"
      File.write(path, "hello\nworld\n")
      v = File.foreach(path) { |line| line }; p v
      fe = File.foreach(path).class;           p fe
      acc = []
      File.foreach(path) { |l| acc << l }
      p acc
      File.delete(path)
      d = "/tmp/sp_dir34"
      Dir.mkdir(d) unless Dir.exist?(d)
      File.write("#{d}/x", "")
      a = []; Dir.open(d) { |dir| a = dir.children }
      p a.sort
      File.delete("#{d}/x"); Dir.rmdir(d)
      r1 = (true.method(:&).call(false) rescue $!.class); p r1
      r2 = (false.method(:|).call(true) rescue $!.class); p r2
      r3 = (true.public_method(:^).call(true) rescue $!.class); p r3
      r4 = (true.method(:nope) rescue $!.class); p r4
      begin; nil.foo(1, 2); rescue NoMethodError => e; p e.args; p e.message; end
      begin; nil.bar; rescue NoMethodError => e; p e.args; end
      x = [1, "s"].sample
      begin; x.zzz(:a, "b") if false; nil.qq(9); rescue NoMethodError => e; p e.args; end
      a = [["x", 1], ["y", 2]]
      p a.find_index { |k, v| k == "y" }
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      Enumerator
      ["hello\n", "world\n"]
      ["x"]
      false
      true
      false
      NameError
      [1, 2]
      "undefined method 'foo' for nil"
      []
      [9]
      1
    OUT
  end
end
