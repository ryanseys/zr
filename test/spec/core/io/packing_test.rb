# frozen_string_literal: true

require "spec_helper"

describe "IO: packing and unpacking" do
  it "file line and dir name the file the code was written in" do
    result = ze0(<<~'RUBY', files: beside("file_line_dir/helper.rb", "file_line_dir/main.rb"))
      # The point of the SOURCE_FILE stack: `require` merges every file's
      # statements into one Program, so by codegen time nothing tells them
      # apart -- these have to be resolved at LOWERING time, per file. A
      # `__FILE__` inside a required file must name THAT file, not the main
      # one, and the main file's own `__FILE__` after the require must be
      # itself again.
      #
      # Only basenames are compared: the harness compiles from a per-test
      # temp dir, so the absolute paths differ per run.
      # helper_line is 2 (the `def helper_line` line); the main file's
      # `__LINE__` is on its own 6th line counting the leading newline.
      #
      # `__dir__` is only checked for absoluteness and for agreeing between
      # the two files, NOT compared against `File.expand_path(__FILE__)`:
      # `__dir__` is baked at COMPILE time while `expand_path` of a relative
      # `__FILE__` resolves against the RUNTIME cwd, and this harness runs
      # the binary from a different directory than it compiled in. The two
      # agree whenever the program is run from its own directory, which is
      # verified against the oracle separately.

      require_relative "file_line_dir/main"
    RUBY

    _(result).must_answer <<~'OUT'
      helper.rb
      2
      main.rb
      5
      true
      true
    OUT
  end

  it "file read to eof" do
    result = ze0(<<~'RUBY')
      # File.read / IO#read must read to EOF, not to the size the stream reports.
      #
      # The size was used as the length: a file that reports 0 bytes and still yields
      # them -- every /proc and /sys entry, a FIFO, a character device -- came back as
      # "". Silently, since a short read is indistinguishable from an empty file.
      # File.readlines on the same file was correct, which is what made it look like a
      # File.read problem rather than a shared one.
      #
      # The size is a hint for the initial buffer now, and every stream reads to EOF
      # through one reader.

      # an ordinary file still round-trips, in one allocation and one read
      path = "spinel_read_eof_#{Process.pid}.tmp"
      File.write(path, "abc\ndef\n")
      p File.read(path).length
      p File.read(path)
      p File.readlines(path).length

      # empty really is empty
      File.write(path, "")
      p File.read(path)
      p File.read(path).length

      # a file larger than any plausible initial buffer
      big = "x" * 40000
      File.write(path, big)
      p File.read(path).length
      p File.read(path) == big

      # a handle read from a non-zero offset answers the remainder
      f = File.open(path, "r")
      f.read(10)
      p f.read.length
      f.close

      File.delete(path)

      # a pipe: not seekable, so the size is not even a hint
      r, w = IO.pipe
      w.write("through a pipe\n")
      w.close
      p r.read
      r.close

      # a stream whose reported size is zero but which yields bytes. /proc is the
      # case that surfaced it; elsewhere the pipe above already covers the shape, so
      # assert the property only where such a file exists.
      status = "/proc/self/status"
      if File.exist?(status)
        p File.read(status).length > 0
        p File.read(status).length == File.readlines(status).join.length
      else
        p true
        p true
      end
    RUBY

    _(result).must_answer <<~'OUT'
      8
      "abc\ndef\n"
      2
      ""
      0
      40000
      true
      39990
      "through a pipe\n"
      true
      true
    OUT
  end

  it "file size" do
    result = ze0(<<~'RUBY')
      # File.size(path): byte count (stat-based, so embedded NUL bytes are
      # counted, unlike a strlen); a missing path raises Errno::ENOENT, matching
      # MRI and the other stat/open-based File class methods.
      filename = "test_size_temp.bin"
      begin
        File.write(filename, "ABC")
        puts File.size(filename)
        File.write(filename, [65, 0, 66, 0, 67].pack("C*"))   # 5 bytes incl 2 NULs
        puts File.size(filename)
        begin
          File.size("definitely_missing_size_test")
          puts "no-raise"
        rescue => e
          puts e.class
        end
      ensure
        File.delete(filename) if File.exist?(filename)
      end
    RUBY

    _(result).must_answer <<~'OUT'
      3
      5
      Errno::ENOENT
    OUT
  end

  it "read, write, pread and pwrite repeat the system call until length bytes moved" do
    result = ze0(<<~'RUBY')
      # IO::Buffer#read, #write, #pread and #pwrite make the system call over
      # the rest of the buffer until at least `length` bytes moved, and answer
      # the count or the negative errno.
      require "tmpdir"
      require "io/nonblock"
      Warning[:experimental] = false
      r, w = IO.pipe
      b = IO::Buffer.new(8)
      p b.write(w, 0), IO::Buffer.for("hey").write(w, 2, 1)
      w.write("abc")
      p b.read(r, 3), b.get_string(0, 5)
      p b.read(r, 0), b.get_string(0, 5)
      r.nonblock = true
      p b.read(r, 0) == -Errno::EAGAIN::Errno
      w.close
      p b.read(r, 0), (b.read(r, 1, 9) rescue $!), (b.read(r, 20) rescue $!), (b.read(r, -1) rescue $!)
      p (IO::Buffer.for("x").read(r, 1) rescue $!.class), (b.read(3, 1) rescue $!)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "bytes")
        File.write(path, "0123456789")
        File.open(path, "r+") do |f|
          c = IO::Buffer.new(4)
          p c.pread(f, 3, 4), c.get_string, f.pos
          p IO::Buffer.for("ZZ").pwrite(f, 8), f.pos
        end
        p File.read(path)
      end


    RUBY

    _(result).must_answer <<~'OUT'
      8
      2
      8
      "\x00\x00\x00\x00\x00"
      5
      "eyabc"
      true
      0
      #<ArgumentError: Specified offset+length is bigger than the buffer size!>
      #<ArgumentError: Specified offset+length is bigger than the buffer size!>
      #<ArgumentError: Length can't be negative!>
      IO::Buffer::AccessError
      #<TypeError: no implicit conversion of Integer into IO>
      4
      "3456"
      0
      2
      0
      "01234567ZZ"
    OUT
  end

  it "STDOUT and $stdout both write, and write answers the byte count" do
    result = ze0(<<~'RUBY')
      # STDOUT/STDERR (constants) and $stdout/$stderr (globals) must actually write.
      # Previously STDOUT.write / .puts / .print silently produced no output, and
      # $stdout.write was a no-op returning nil. write returns the byte count.

      n = STDOUT.write("hi\n")
      p n                       # 3

      STDOUT.puts "viaputs"     # viaputs
      STDOUT.print "noeol"      # noeol
      STDOUT.print "\n"

      # Non-string args are stringified (Kernel#puts/#write coercion).
      STDOUT.puts 42            # 42
      m = STDOUT.write(99)
      STDOUT.write("\n")
      p m                       # 2

      # The global forms behave the same.
      g = $stdout.write("global\n")
      p g                       # 7

      # Multi-arg write returns the total bytes written.
      t = $stdout.write("a", "b", "c")
      $stdout.write("\n")
      p t                       # 3

      # STDERR goes to stderr (asserted against the .err.expected sidecar).
      STDERR.write("err\n")     # err
      $stderr.puts "gerr"       # gerr
    RUBY

    _(result).must_answer <<~'OUT', stderr: "err\ngerr\n"
      hi
      3
      viaputs
      noeol
      42
      99
      2
      global
      7
      abc
      3
    OUT
  end

  it "line of multibyte text reads whole" do
    result = ze0(<<~'RUBY')
      # gets and each_line find the separator by bytes, so a line of
      # multibyte characters comes back whole, newline and all.
      path = "/tmp/ze0_a_line_of_multibyte_text_reads_whole.txt"
      File.write(path, "héllo\nwörld ünïcode\n日本語\nplain\n")
      File.open(path) { |f| f.each_line { |l| p l } }
      File.open(path) { |f| p f.gets, f.gets("ö"), f.gets(nil) }
      File.open(path) { |f| p f.readlines(chomp: true) }
      File.delete(path)
    RUBY

    _(result).must_answer <<~'OUT'
      "héllo\n"
      "wörld ünïcode\n"
      "日本語\n"
      "plain\n"
      "héllo\n"
      "wö"
      "rld ünïcode\n日本語\nplain\n"
      ["héllo", "wörld ünïcode", "日本語", "plain"]
    OUT
  end

  it "select sees the bytes a stream already holds" do
    result = ze0(<<~'RUBY')
      # A read takes from the descriptor everything it can and holds what
      # the program did not ask for. Those bytes make the stream ready: a
      # select that asked the descriptor alone would wait for data that is
      # already in hand.
      r, w = IO.pipe
      w.write "ab"
      p r.getc
      p IO.select([r], nil, nil, 0)&.first&.map { |io| io.equal?(r) }
      p IO.select(nil, [w], nil, 0)&.at(1)&.map { |io| io.equal?(w) }
      p r.read(1)
      p IO.select([r], nil, nil, 0)
      w.write "c"
      p IO.select([r], nil, nil, 0)&.first&.size
      w.close
      p r.read
      r.close

    RUBY

    _(result).must_answer <<~'OUT'
      "a"
      [true]
      [true]
      "b"
      nil
      1
      "c"
    OUT
  end

  it "stdout survives falling off the end" do
    result = ze0(<<~'RUBY')
      # Output that does NOT end in a newline is the whole point of this file.
      # Stdout is line-buffered, so a newline-terminated program flushes itself
      # on the way through and can never see the bug: an AOT binary RETURNS its
      # status to the emitted C `main`, past the runtime's own exit cleanup,
      # so nothing wrote the buffer out and the tail was lost.
      # `bm_so_mandelbrot` (a PBM writer) is what caught it, at 44,590 bytes of
      # 45,011 -- and every one of the suite's 5,000 newline-terminated goldens
      # passed over it. Run this one through the AOT leg.
      print "A" * 300
      print "B" * 300
      print "-no trailing newline"
    RUBY

    _(result).must_answer <<~'OUT'.chomp
      AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB-no trailing newline
    OUT
  end

  it "write waits in the streams own buffer" do
    result = ze0(<<~'RUBY')
      # A stream that is not a terminal holds what a program writes until the
      # buffer fills, the program asks for a flush, or the program ends. CRuby's
      # buffer is 8192 bytes: a write that would fill it writes what waits and
      # the new text with it. A pipe's write end and a stream to a child are
      # synchronised instead, so they write at once.
      require "tmpdir"

      Dir.mktmpdir do |dir|
        path = File.join(dir, "held.txt")
        File.open(path, "w") do |file|
          file.write("a" * 10)
          p [file.sync, File.size(path)]
          file.write("b" * 9000)
          p File.size(path)
          file.flush
          p File.size(path)
        end
        p File.size(path)
      end

      r, w = IO.pipe
      p w.sync
      w.write("x")
      p r.readpartial(1)
      w.close
      r.close

      IO.popen("cat", "r+") do |io|
        p io.sync
        io.write("through\n")
        p io.gets
      end

    RUBY

    _(result).must_answer <<~'OUT'
      [false, 0]
      9010
      9010
      9010
      true
      "x"
      true
      "through\n"
    OUT
  end
end
