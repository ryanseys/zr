# frozen_string_literal: true

require "spec_helper"

describe "IO: regressions" do
  it "file binread directory error" do
    result = zr(<<~'RUBY')
      begin
        File.binread(".")
        puts "binread string succeeded"
      rescue => e
        puts e.class
        puts e.message.include?("Is a directory")
      end

      begin
        File.binread(".").bytes
        puts "binread bytes succeeded"
      rescue => e
        puts e.class
        puts e.message.include?("Is a directory")
      end
    RUBY

    _(result).must_answer <<~'OUT'
      Errno::EISDIR
      true
      Errno::EISDIR
      true
    OUT
  end

  it "file class methods int recv" do
    result = zr(<<~'RUBY')
      # `File.readable?` and `File.binwrite`, plus `Array#pack("C*")`
      # on an Integer array, which is the inverse of `String#bytes`.
      #
      # The shape comes from optcarrot's battery-save code path:
      #   `return unless File.readable?(sav)` and
      #   `File.binwrite(sav, @wrk.pack("C*"))`.
      #
      # The test uses a cwd-relative path so that zr and the CRuby
      # reference resolve the same place. `/tmp/...` can land in different
      # directories on the two sides (see bundle_io_sys.rb).

      path = "spinel_file_class_test"

      File.binwrite(path, [72, 105, 33].pack("C*"))   # "Hi!"
      puts File.readable?(path)
      puts File.read(path)
      File.delete(path)
      puts File.exist?(path)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      Hi!
      false
    OUT
  end

  it "file directory predicates" do
    result = zr(<<~'RUBY')
      path = "spinel_file_predicate_test.txt"
      File.write(path, "x")

      puts File.directory?(".")
      puts File.directory?("./")
      puts File.directory?(path)
      puts File.file?(path)
      puts File.file?(".")
      puts File.directory?("spinel_missing_predicate_path")
      puts File.file?("spinel_missing_predicate_path")

      File.delete(path)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      true
      false
      false
      false
    OUT
  end

  it "file read directory error" do
    result = zr(<<~'RUBY')
      begin
        File.read(".")
        puts "read succeeded"
      rescue => e
        puts e.class
        puts e.message.include?("Is a directory")
      end
    RUBY

    _(result).must_answer "Errno::EISDIR\ntrue\n"
  end

  it "file write binary string" do
    result = zr(<<~'RUBY')
      path = "spinel_file_write_binary_string.bin"

      payload = "A" + 0.chr + "B"

      File.write(path, payload)
      bytes = File.binread(path).bytes

      puts bytes.length
      if bytes.length == 3
        puts bytes[0]
        puts bytes[1]
        puts bytes[2]
      end
      puts payload.inspect.include?("B")

      File.delete(path) if File.exist?(path)
    RUBY

    _(result).must_answer <<~'OUT'
      3
      65
      0
      66
      true
    OUT
  end

  it "file write directory error" do
    result = zr(<<~'RUBY')
      begin
        File.write(".", "hello")
        puts "write succeeded"
      rescue => e
        puts e.class
        puts e.message.include?("Is a directory")
      end
    RUBY

    _(result).must_answer "Errno::EISDIR\ntrue\n"
  end

  it "file binread" do
    result = zr(<<~'RUBY')
      # `File.binread(path).bytes` gives every byte of binary data, also
      # a 0x00 byte in the middle (as in .nes ROM files).
      #
      # Uses a cwd-relative path so that zr and the CRuby reference resolve
      # to the same file (the harness runs each test from the project
      # root). `/tmp/...` can land in different places on the two sides.

      # Set up a binary file with embedded NULs via a shell command.
      path = "spinel_binread_test.bin"
      `printf 'AB\\000CD\\000EF' > #{path}`

      # The byte count is the file size, NULs included.
      arr = File.binread(path).bytes
      puts arr.length               # 8
      puts arr[0]                   # 65 (A)
      puts arr[1]                   # 66 (B)
      puts arr[2]                   # 0  (NUL)
      puts arr[3]                   # 67 (C)
      puts arr[4]                   # 68 (D)
      puts arr[5]                   # 0  (NUL)
      puts arr[6]                   # 69 (E)
      puts arr[7]                   # 70 (F)

      # `File.binread` alone returns a String of the file's bytes.
      puts File.binread(path)[0, 2] # AB

      File.delete(path) if File.exist?(path)
    RUBY

    _(result).must_answer <<~'OUT'
      8
      65
      66
      0
      67
      68
      0
      69
      70
      AB
    OUT
  end

  it "fileio" do
    result = zr(<<~'RUBY')
      # Test basic File I/O.
      # Uses cwd-relative paths so the harness (which runs each test from
      # the project root) and the CRuby reference both write to the same
      # place on every platform — `/tmp/...` does not resolve the same
      # way on all platforms.

      # Write a file
      File.write("spinel_test.txt", "Hello from Spinel!\nLine 2\n")

      # Read the file
      content = File.read("spinel_test.txt")
      puts content

      # File.exist?
      puts File.exist?("spinel_test.txt")  # true
      puts File.exist?("spinel_nonexistent.txt")  # false

      # Clean up
      File.delete("spinel_test.txt")
      puts File.exist?("spinel_test.txt")  # false

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      Hello from Spinel!
      Line 2
      true
      false
      false
      done
    OUT
  end

  it "fileopen" do
    result = zr(<<~'RUBY')
      # Test File.open with block.
      # Uses a cwd-relative path for the same reason as test/fileio.rb.

      # Write with block
      File.open("spinel_fopen_test.txt", "w") do |f|
        f.puts "line 1"
        f.puts "line 2"
        f.puts "line 3"
      end

      # Read with block
      File.open("spinel_fopen_test.txt", "r") do |f|
        f.each_line do |line|
          puts line
        end
      end

      # File.open without block (returns file object)
      # Skip — needs explicit close, less common

      # Cleanup
      File.delete("spinel_fopen_test.txt")
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      line 1
      line 2
      line 3
      done
    OUT
  end

  it "fileops" do
    result = zr(<<~'RUBY')
      puts File.join("home", "user")      # home/user
      puts File.basename("/path/to/file") # file
      puts "".empty?                      # true
      puts "hi".empty?                    # false
      puts 5.clamp(1, 10)                 # 5
      puts 15.clamp(1, 10)                # 10
      puts "hello".to_sym                 # hello
      puts "a".ord                        # 97
      puts "42".to_i + 1                  # 43
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      home/user
      file
      true
      false
      5
      10
      hello
      97
      43
      done
    OUT
  end

  it "system" do
    result = zr(<<~'RUBY')
      # Test system features needed for ccm

      # system()
      system("echo hello_from_system")  # hello_from_system

      # ENV
      puts ENV['HOME'] != nil  # true

      # Dir.home
      home = Dir.home
      puts home.length > 0  # true

      # backtick
      result = `echo backtick_test`.strip
      puts result  # backtick_test

      # trap (just register, don't trigger)
      trap('INT') { }
      puts "trap set"

      # $stdin — skip interactive test
      # File.readlink — skip (needs symlink)

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      hello_from_system
      true
      true
      backtick_test
      trap set
      done
    OUT
  end

  it "system expr" do
    result = zr(<<~'RUBY')
      ok = system("echo hello_from_expr")
      puts ok
      puts($? == 0)
      ok = system("false")
      puts ok
      puts($? == 0)
    RUBY

    _(result).must_answer <<~'OUT'
      hello_from_expr
      true
      true
      false
      false
    OUT
  end

  it "process clock gettime" do
    result = zr(<<~'RUBY')
      # Process.clock_gettime(Process::CLOCK_MONOTONIC) returns a Float.
      # The test cannot assert an exact value. It checks that the call
      # returns a Float that does not decrease across two samples.

      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      # t1 and t2 are Floats, so arithmetic on them works.
      diff = t2 - t1
      if diff >= 0
        puts "monotonic"
      end
    RUBY

    _(result).must_answer "monotonic\n"
  end

  it "time" do
    result = zr(<<~'RUBY')
      t = Time.now
      puts t.to_f - t.to_i > 0.0
      puts t.to_i > 1_000_000_000
      puts t.to_i < 2_000_000_000
      puts t.to_f > 1_000_000_000.0
      puts t.to_i == t.to_f.to_i || t.to_i + 1 == t.to_f.to_i

      puts Time.at(1234567890).to_i == 1234567890
      puts Time.at(0).to_i == 0
      puts Time.at(-1).to_i == -1

      t2 = Time.at(1234567890.5)
      puts t2.to_i == 1234567890
      puts (t2.to_f - 1234567890.5).abs < 0.001

      a = Time.at(1000.5)
      b = Time.at(500.25)
      puts ((a - b) - 500.25).abs < 0.0001

      puts (Time.at(0) - Time.at(0)).abs < 0.0001

      puts ((Time.at(100) - Time.at(200)) + 100.0).abs < 0.0001

      # A negative fraction rounds the seconds down
      puts Time.at(-0.5).to_i == -1

      puts Time.at(0.0).to_i == 0

      # Time#to_f has millisecond precision
      puts Time.now.to_f * 1000 > 1_000_000_000_000.0

      puts Time.at(1).to_i + Time.at(2).to_i == 3

      puts (Time.at(1.5).to_f * 1000 - 1500.0).abs < 1.0

      puts (Time.at(2000) - Time.at(1000)).to_i == 1000

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
      done
    OUT
  end

  it "Dir#seek answers the Dir, and #fileno an Integer" do
    result = zr(<<~'RUBY')
      d = "/tmp/sp_dir_2967_#{Process.pid}"
      Dir.mkdir(d) unless Dir.exist?(d)
      dd = Dir.new(d)
      p (dd.seek(0).class rescue $!.class)
      p (dd.fileno.class rescue $!.class)
      dd.close
      Dir.rmdir(d)
    RUBY

    _(result).must_answer "Dir\nInteger\n"
  end

  it "Dir#pos= answers the position it was given" do
    result = zr(<<~'RUBY')
      d = "/tmp/sp_dir_2968_#{Process.pid}"
      Dir.mkdir(d) unless Dir.exist?(d)
      dd = Dir.new(d)
      r = ((dd.pos = 0) rescue $!.class); p r
      dd.close
      Dir.rmdir(d)
    RUBY

    _(result).must_answer "0\n"
  end

  it "File.birthtime answers a Time" do
    result = zr(<<~'RUBY')
      path = "/tmp/spinel_issue_2985.txt"
      File.write(path, "hello")
      t = File.birthtime(path)
      puts t.class
      puts t.is_a?(Time)
      File.delete(path)
    RUBY

    _(result).must_answer "Time\ntrue\n"
  end

  it "lstat reports the link itself where stat follows it" do
    result = zr(<<~'RUBY')
      p001 = "sp_issue_2986.tmp"
      File.write(p001, "xyz")
      s001 = File.lstat(p001)
      p s001.class
      p s001.size
      p s001.ftype
      File.symlink(p001, "sp_issue_2986.link") rescue nil
      l = File.lstat("sp_issue_2986.link")
      p l.ftype
      p File.stat("sp_issue_2986.link").ftype
      File.open(p001) { |f| p f.lstat.class }
      File.delete("sp_issue_2986.link")
      File.delete(p001)
    RUBY

    _(result).must_answer <<~'OUT'
      File::Stat
      3
      "file"
      "link"
      "file"
      File::Stat
    OUT
  end

  it "File.absolute_path? is true only for a path that starts at the root" do
    result = zr(<<~'RUBY')
      p File.absolute_path?("/a/b")
      p File.absolute_path?("a/b")
      p File.absolute_path?("./x")
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      false
    OUT
  end

  it "the FileTest predicates answer for a file just written" do
    result = zr(<<~'RUBY')
      f = "/tmp/sp_ft_2997_#{Process.pid}"
      File.write(f, "hi")
      p FileTest.owned?(f)
      p FileTest.exist?(f)
      p FileTest.file?(f)
      p FileTest.directory?(f)
      p FileTest.symlink?(f)
      p FileTest.zero?(f)
      p FileTest.setuid?(f)
      File.delete(f)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      false
      false
      false
      false
    OUT
  end

  it "the File predicates, symlink, link, utime and umask over one file" do
    result = zr(<<~'RUBY')
      dir = "/tmp/sp_issue_3005_#{Process.pid}"
      Dir.mkdir(dir) unless File.directory?(dir)
      f = File.join(dir, "f")
      File.write(f, "hello")
      File.chmod(0644, f)

      p File.owned?(f)
      # grpowned? is platform-dependent: on Linux a new file gets the process egid,
      # but on macOS a /tmp file inherits the directory's group, so assert only that
      # it answers a boolean rather than its exact value.
      p [true, false].include?(File.grpowned?(f))
      p File.setuid?(f)
      p File.setgid?(f)
      p File.sticky?(f)
      p File.socket?(f)
      p File.blockdev?(f)
      p File.chardev?(f)
      p File.world_readable?(f)
      p File.world_writable?(f)

      link = File.join(dir, "lnk")
      File.symlink("f", link)
      p File.symlink?(link)
      p File.readlink(link)

      hard = File.join(dir, "hard")
      p File.link(f, hard)
      p File.read(hard)

      p File.utime(1000000000, 1000000000, f)
      p File.mtime(f).to_i

      p File.umask.is_a?(Integer)

      File.delete(link)
      File.delete(hard)
      File.delete(f)
      Dir.rmdir(dir)
      puts "ok"
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      false
      false
      false
      false
      false
      420
      nil
      true
      "f"
      0
      "hello"
      1
      1000000000
      true
      ok
    OUT
  end

  it "the IO tail: readbyte, ungetbyte, pread, pwrite, advise and each_codepoint" do
    result = zr(<<~'RUBY')
      pth = "sp_issue_3038.tmp"
      File.write(pth, "hi\n")
      File.open(pth) do |f|
        p f.readbyte
        f.ungetbyte(104)
        p f.readbyte
        p f.binmode?
        p f.to_io.equal?(f)
        p f.close_on_exec?
        p f.pread(2, 0)
        p f.advise(:normal)
        p((f.autoclose = true))
        p((f.close_write rescue $!.class))
        p((f.close_read rescue $!.class))
      end
      File.open(pth, "r+") { |f| p f.pwrite("X", 0) }
      p File.read(pth)
      File.open(pth) { |f| cps = []; f.each_codepoint { |cp| cps << cp }; p cps }
      File.delete(pth)
    RUBY

    _(result).must_answer <<~'OUT'
      104
      104
      false
      true
      true
      "hi"
      nil
      true
      IOError
      nil
      1
      "Xi\n"
      [88, 105, 10]
    OUT
  end

  it "IO#stat answers a File::Stat with the file's size" do
    result = zr(<<~'RUBY')
      p001 = "/tmp/sp_io_stat_repro.txt"
      File.write(p001, "hello world\n")
      File.open(p001) { |f| p f.stat.class }
      File.open(p001) { |f| p f.stat.size }
      File.open(p001) do |f|
        a001 = f.stat
        p a001.class
        p a001.size
      end
      File.delete(p001)
    RUBY

    _(result).must_answer <<~'OUT'
      File::Stat
      12
      File::Stat
      12
    OUT
  end

  it "IO#chown with nil for both owner and group leaves the file alone" do
    result = zr(<<~'RUBY')
      path = "/tmp/spinel_issue_3104.txt"
      File.write(path, "x")
      File.open(path) { |f| p f.chown(nil, nil) }
      File.delete(path)
    RUBY

    _(result).must_answer "0\n"
  end

  it "warn writes each of its arguments to $stderr on its own line" do
    result = zr(<<~'RUBY')
      require "stringio"
      out = StringIO.new
      $stderr = out
      warn "x"
      warn "y", "z"
      raise if out.string.empty?
      p out.string
    RUBY

    _(result).must_answer "\"x\\ny\\nz\\n\"\n"
  end

  it "File.mkfifo creates a named pipe that File.exist? finds" do
    result = zr(<<~'RUBY')
      p001 = "/tmp/sp_mkfifo_3118_#{Process.pid}"
      File.delete(p001) if File.exist?(p001)
      r = begin; File.mkfifo(p001); rescue => e; e.class; end
      p r
      p File.exist?(p001)
      File.delete(p001)
      p File.exist?(p001)
      p File.exist?("/tmp")
    RUBY

    _(result).must_answer <<~'OUT'
      0
      true
      false
      true
    OUT
  end

  it "IO#fcntl answers the flags the descriptor holds" do
    result = zr(<<~'RUBY')
      p001 = "sp_io_3130.tmp"
      File.write(p001, "hi")
      File.open(p001) { |f| r001 = (f.fcntl(1, 0) rescue $!.class); p r001 }
      File.delete(p001)
    RUBY

    _(result).must_answer "1\n"
  end

  it "binmode, autoclose=, pread with a buffer and reopen on an open File" do
    result = zr(<<~'RUBY')
      p001 = "sp_io_3131.tmp"
      File.write(p001, "hi")
      File.open(p001) { |f| f.binmode; p f.binmode? }
      File.open(p001) { |f| f.autoclose = false; p f.autoclose? }
      File.open(p001) { |f| buf = +""; f.pread(2, 0, buf); p buf }
      File.write("sp_io_3131b.tmp", "other")
      File.open(p001) { |f| File.open("sp_io_3131b.tmp") { |g| f.reopen(g); p f.read } }
      File.delete(p001); File.delete("sp_io_3131b.tmp")
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      "hi"
      "other"
    OUT
  end

  it "IO.copy_stream copies from the source's current position and answers the count" do
    result = zr(<<~'RUBY')
      require 'stringio'

      def http_resp(dst, src)
        src.rewind
        IO.copy_stream(src, dst)
      end

      src = StringIO.new("hello world")
      dst = StringIO.new
      n = http_resp(dst, src)
      p n
      p dst.string

      # partial copy respects the source position
      src2 = StringIO.new("abcdef")
      src2.read(2)
      dst2 = StringIO.new
      IO.copy_stream(src2, dst2)
      p dst2.string
    RUBY

    _(result).must_answer <<~'OUT'
      11
      "hello world"
      "cdef"
    OUT
  end

  it "IO.copy_stream copies between a StringIO and a File either way" do
    result = zr(<<~'RUBY')
      require 'stringio'
      io = StringIO.new("hello world")
      File.open("/tmp/spinel_issue_3217_out.txt", "w") do |f|
        n = IO.copy_stream(io, f)
        p n
      end
      puts File.read("/tmp/spinel_issue_3217_out.txt")
      File.write("/tmp/spinel_issue_3217_in.txt", "abc123")
      sink = StringIO.new
      File.open("/tmp/spinel_issue_3217_in.txt") do |f|
        IO.copy_stream(f, sink)
      end
      puts sink.string
    RUBY

    _(result).must_answer <<~'OUT'
      11
      hello world
      abc123
    OUT
  end

  it "Dir#inspect names the path it was opened on" do
    result = zr(<<~'RUBY')
      p(Dir.new(".").inspect)
      p(Dir.new(".").to_path)
      d = Dir.new(".")
      puts d.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      "#<Dir:.>"
      "."
      #<Dir:.>
    OUT
  end

  it "extname, basename and dirname take a path that may be nil" do
    result = zr(<<~'RUBY')
      def content_type(path)
        File.extname(path)
      end
      def get_path(str)
        x = str.split(" ")
        return x[1] if x[0] == "GET"
        nil
      end
      p content_type(get_path("GET /index.html"))
      p File.basename(get_path("GET /a/b/c.txt"))
      p File.dirname(get_path("GET /a/b/c.txt"))
    RUBY

    _(result).must_answer <<~'OUT'
      ".html"
      "c.txt"
      "/a/b"
    OUT
  end

  it "$LOAD_PATH is already an array when the program's first statement runs" do
    result = zr(<<~'RUBY')
      # `$LOAD_PATH` is still nil when the program's first statement runs: zr's
      # preamble initializes it after user code rather than before it, so `unshift`
      # raises on a nil receiver. ruby has it populated before line 1 executes.
      $:.unshift File.dirname(__FILE__)
      $LOAD_PATH.unshift(File.expand_path("../lib", __FILE__))
      $LOAD_PATH << File.dirname(__FILE__)
      $:.push File.dirname(__FILE__)
      puts 1
    RUBY

    _(result).must_answer "1\n"
  end

  it "a reopened Dir takes a constant and a singleton method" do
    result = zr(<<~'RUBY')
      class Dir
        VERSION = '1.0.0'
        def self.dot?(name)
          name == "." || name == ".."
        end
      end
      puts Dir::VERSION
      p Dir.dot?(".")
      p Dir.dot?("x")
    RUBY

    _(result).must_answer <<~'OUT'
      1.0.0
      true
      false
    OUT
  end

  it "read and pread answer the bytes even when the output buffer is frozen" do
    result = zr(<<~'RUBY')
      path = "/tmp/sp_frozen_outbuf.txt"
      File.write(path, "hello world")
      File.open(path) { |f| b = ""; r = (f.read(3, b) rescue $!.class); p r }
      File.open(path) { |f| b = ""; r = (f.pread(5, 0, b) rescue $!.class); p r }
      File.delete(path)
    RUBY

    _(result).must_answer <<~'OUT'
      "hel"
      "hello"
    OUT
  end

  it "sysread and readpartial fill the buffer they are given and answer it" do
    result = zr(<<~'RUBY')
      # A read given an explicit output-buffer argument returns the data but leaves
      # the supplied buffer empty. ruby fills that buffer in place and returns the
      # same object, so the caller can read the bytes back out of it.
      path = "/tmp/sp_outbuf_ignored.txt"
      File.write(path, "hello world")
      File.open(path) { |f| b = +""; r = f.sysread(3, b); p r; p b; p r.equal?(b) }
      File.open(path) { |f| b = +""; r = f.readpartial(3, b); p r; p b; p r.equal?(b) }
      File.delete(path)
    RUBY

    _(result).must_answer <<~'OUT'
      "hel"
      "hel"
      true
      "hel"
      "hel"
      true
    OUT
  end
end
