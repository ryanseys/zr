# frozen_string_literal: true

require "spec_helper"

describe "IO: formatting and inspection" do
  it "argf walk reads every named file" do
    files = beside("argf_walk/a.txt", "argf_walk/b.txt")

    result = zr(<<~'RUBY', argv: ["core/io/argf_walk/a.txt", "core/io/argf_walk/b.txt"], files: files)

      # ARGF is one stream over the files ARGV names: each opens as the walk
      # reaches it, the line numbers run on across the whole set, and ARGV
      # empties as the walk goes.
      def e; p(yield); rescue => x; puts "#{x.class}: #{x.message}"; end
      e { ARGF.class.name }
      e { ARGF.class.ancestors.first(3) }
      e { ARGF.filename }
      e { ARGF.argv }
      e { ARGF.lineno }
      e { ARGF.eof? }
      rows = []
      ARGF.each_line { |l| rows << [ARGF.filename, ARGF.lineno, l] }
      p rows
      e { ARGF.lineno }
      e { ARGF.eof? }
      e { ARGF.gets }
      e { ARGF.argv }
      e { ARGF.to_s }
      e { ARGF.inspect }
    RUBY

    _(result).must_answer <<~'OUT'
      "ARGF.class"
      [ARGF.class, Enumerable, Object]
      "core/io/argf_walk/a.txt"
      ["core/io/argf_walk/b.txt"]
      0
      false
      [["core/io/argf_walk/a.txt", 1, "one\n"], ["core/io/argf_walk/a.txt", 2, "two\n"], ["core/io/argf_walk/b.txt", 3, "three\n"]]
      3
      IOError: closed stream
      nil
      []
      "ARGF"
      "ARGF"
    OUT
  end

  it "call operand lifetime" do
    result = zr(<<~'RUBY')
      # Every operand of a call stays alive until the call runs. An operand that is a
      # fresh allocation is reachable from nothing until the callee stores it, so a
      # sibling operand evaluated afterwards can collect it -- the argument-position
      # shape #4049 fixed for a constructor's members, which every other call had too.
      # Each operand binds to a rooted temp in front of the call now. A natural
      # collection does not reliably land in that window, so the lifetime half is
      # verified under SPINEL_GC_STRESS=1, where the first count was 40 of 40 before
      # the fix and 0 after. What this run asserts unconditionally is the shape
      # and the answer.
      def seg(tag, i)
        s = String.new(tag)
        s + i.to_s
      end

      def churn(tag, i)
        parts = []
        40.times { |j| parts.push("#{tag}-#{i}-#{j}......................") }
        GC.start
        parts.length
      end

      # allocates, collects, and answers a String: as a later operand it is what
      # reclaims an earlier one
      def churn_seg(tag, i)
        churn(tag, i)
        s = String.new(tag)
        s + i.to_s
      end

      bad = 0
      40.times do |i|
        joined = File.join(seg("a", i), churn_seg("m", i), seg("b", i))
        bad += 1 unless joined == "a#{i}/m#{i}/b#{i}"
      end
      p bad

      # the allocating sibling sits between two fresh operands, so one of them is
      # evaluated before it whichever order a C compiler would have picked
      bad2 = 0
      40.times do |i|
        left = seg("L", i)
        n = churn("m", i)
        right = seg("R", i)
        bad2 += 1 unless "#{left}/#{n}/#{right}" == "L#{i}/40/R#{i}"
      end
      p bad2

      bad3 = 0
      40.times do |i|
        joined = [seg("x", i), churn("y", i).to_s, seg("z", i)].join(",")
        bad3 += 1 unless joined == "x#{i},40,z#{i}"
      end
      p bad3
    RUBY

    _(result).must_answer <<~'OUT'
      0
      0
      0
    OUT
  end

  it "case mapping options and unprintable inspect" do
    result = zr(<<~'RUBY')
      # Ruby's case-mapping OPTIONS -- `:ascii`, `:turkic`, `:lithuanian`, `:fold`
      # -- and the acceptance rules around them, which follow from nothing but
      # CRuby's `check_case_options`: `:turkic` and `:lithuanian` may be given
      # together in either order, nothing else may be given twice, `:fold` is
      # downcasing only, and each refusal has its own message.
      #
      # They are not decoration. `"straße".upcase(:ascii)` is `"STRAßE"` where the
      # full mapping gives `"STRASSE"` and the string gets LONGER -- a protocol
      # that wants ASCII casing and gets Unicode's has silently changed its data.
      #
      # `:fold` is case FOLDING, which is not lowercasing: `ß` folds to `"ss"` and
      # `ﬁ` to `"fi"`. The 297 codepoints where the two differ are generated from
      # the oracle (`tools/casefold_table.rb`).
      #
      # The second half is `String#inspect`, which must ESCAPE a codepoint ruby
      # does not consider printable. Which ones those are is Oniguruma's own table
      # and follows no rule the general category gives -- U+E000 (private use) and
      # U+00AD (soft hyphen) print raw while U+FFFE and every unassigned codepoint
      # escape -- so that table is generated from the oracle too
      # (`tools/inspect_printable.rb`). A symbol name follows it: a character ruby
      # would escape is not an identifier character.
      %w[straße ÄB äb äB i I].each_with_index do |s, i|
        p [i, s.upcase(:ascii), s.downcase(:ascii), s.capitalize(:ascii), s.swapcase(:ascii)]
      end
      p ["ß".downcase(:fold), "ﬁ".downcase(:fold), "Σς".downcase(:fold), "İ".downcase(:fold)]
      p ["i".upcase(:turkic), "I".downcase(:turkic), "İ".downcase(:turkic), "ı".upcase(:turkic)]
      p ["istanbul".capitalize(:turkic), "iI".swapcase(:turkic), "i".upcase(:turkic, :lithuanian)]
      p ["i".upcase(:lithuanian), "I".downcase(:lithuanian), "i".upcase(:lithuanian, :turkic)]
      p :äb.upcase(:ascii)
      s = "äb".dup
      s.upcase!(:ascii)
      p s
      [proc { "a".upcase(:fold) }, proc { "ß".capitalize(:fold) },
       proc { "i".upcase(:ascii, :turkic) }, proc { "i".upcase(:nope) },
       proc { "i".upcase("ascii") }, proc { "i".upcase(:turkic, :lithuanian, :ascii) },
       proc { "i".upcase(:turkic, :nope) }].each do |f|
        begin
          f.call
        rescue ArgumentError => e
          p e.message
        end
      end
      p [0xE000.chr(Encoding::UTF_8), 0xFFFE.chr(Encoding::UTF_8), 0xAD.chr(Encoding::UTF_8)]
      p [0x378.chr(Encoding::UTF_8), 0x10FFFF.chr(Encoding::UTF_8), 0x1F600.chr(Encoding::UTF_8)]
      p "a#{0xFFFE.chr(Encoding::UTF_8)}b"
      p 0xFFFE.chr(Encoding::UTF_8).to_sym
      p :あ
    RUBY

    _(result).must_answer <<~'OUT'
      [0, "STRAßE", "straße", "Straße", "STRAßE"]
      [1, "ÄB", "Äb", "Äb", "Äb"]
      [2, "äB", "äb", "äb", "äB"]
      [3, "äB", "äb", "äb", "äb"]
      [4, "I", "i", "I", "I"]
      [5, "I", "i", "I", "i"]
      ["ss", "fi", "σσ", "i̇"]
      ["İ", "ı", "i", "I"]
      ["İstanbul", "İı", "İ"]
      ["I", "i", "İ"]
      :äB
      "äB"
      "option :fold only allowed for downcasing"
      "option :fold only allowed for downcasing"
      "too many options"
      "invalid option"
      "invalid option"
      "too many options"
      "invalid second option"
      ["", "\uFFFE", "­"]
      ["\u0378", "\u{10FFFF}", "😀"]
      "a\uFFFEb"
      :"\uFFFE"
      :あ
    OUT
  end

  it "created file takes its permissions less the umask" do
    result = zr(<<~'RUBY')
      # File.open and IO.sysopen create a file with open(2): the permissions
      # given, less the umask, and O_EXCL for "x".
      require "tmpdir"
      Dir.mktmpdir do |d|
        File.umask(0o022)
        at = ->(name) { File.join(d, name) }
        mode = ->(name) { File.stat(at[name]).mode.to_s(8) }
        File.open(at["a"], "w", 0o640) { |io| io.write "x" }
        p mode["a"]
        File.open(at["a"], "w", 0o600) { |io| io.write "y" }
        p mode["a"], File.read(at["a"])
        p((File.open(at["a"], "wx") rescue $!.class))
        File.open(at["b"], "wx", 0o777) {}
        p mode["b"]
        File.open(at["c"], File::RDWR | File::CREAT, 0o604) { |io| io.write "rw"; io.rewind; p io.read }
        p mode["c"]
        p((File.open(at["c"], File::RDWR | File::CREAT | File::EXCL) rescue $!.class))
        File.open(at["c"], "a+") { |io| io << "z"; io.rewind; p io.read }
        File.open(at["c"], "r+") { |io| io << "Q" }
        p File.read(at["c"])
        p((File.open(at["nope"], "r") rescue $!.class), (File.open(at["nope"], "r+") rescue $!.class))
        fd = IO.sysopen(at["e"], "w", 0o700)
        p mode["e"], fd.class
        IO.for_fd(fd).close
        io = IO.new(IO.sysopen(at["e"], File::WRONLY | File::APPEND), "a")
        io.write("tail")
        io.close
        p File.read(at["e"])
        File.umask(0o077)
        File.write(at["g"], "g")
        p mode["g"]
      end

    RUBY

    _(result).must_answer <<~'OUT'
      "100640"
      "100640"
      "y"
      Errno::EEXIST
      "100755"
      "rw"
      "100604"
      Errno::EEXIST
      "rwz"
      "Qwz"
      Errno::ENOENT
      Errno::ENOENT
      "100700"
      Integer
      "tail"
      "100600"
    OUT
  end

  it "dir entries children" do
    result = zr(<<~'RUBY')
      root = "/tmp/spinel_dir_entries_t"
      Dir.mkdir(root) unless Dir.exist?(root)
      File.write("#{root}/b.txt", "x")
      File.write("#{root}/a.txt", "x")
      File.write("#{root}/.hidden", "x")
      puts Dir.entries(root).sort.inspect
      puts Dir.children(root).sort.inspect
      begin
        Dir.entries("#{root}/nope")
      rescue => e
        puts "raised: #{e.message}"
      end
      File.delete("#{root}/a.txt"); File.delete("#{root}/b.txt"); File.delete("#{root}/.hidden")
      Dir.rmdir(root)
    RUBY

    _(result).must_answer <<~'OUT'
      [".", "..", ".hidden", "a.txt", "b.txt"]
      [".hidden", "a.txt", "b.txt"]
      raised: No such file or directory @ dir_initialize - /tmp/spinel_dir_entries_t/nope
    OUT
  end

  it "failed fcntl names the stream" do
    result = zr(<<~'RUBY')
      # rb_sys_fail_path: a failing `IO#fcntl` names the call that set up its
      # argument and the stream it was made on -- "... @ finish_narg - /etc/hosts"
      # -- and a stream that carries no path, as a pipe end does, names neither.
      #
      # zr wrote "@ io_fcntl" for every stream and never named one.
      require "fcntl"

      def refusal
        "no refusal: #{yield.inspect}"
      rescue SystemCallError => e
        "#{e.class}: #{e.message}"
      end

      f = File.open("/etc/hosts")
      r, w = IO.pipe

      # A command no descriptor answers, on a stream with a path, on one without,
      # and on a standard stream, whose path is its own name.
      puts refusal { f.fcntl(9999) }
      puts refusal { r.fcntl(9999) }
      puts refusal { $stdout.fcntl(9999) }

      # The commands that do answer, as a control: the close-on-exec flag ruby
      # sets on everything it opens, and the access mode the stream was opened in.
      p f.fcntl(Fcntl::F_GETFD)
      p (f.fcntl(Fcntl::F_GETFL) & Fcntl::O_ACCMODE) == Fcntl::O_RDONLY

      # A closed stream refuses before the call.
      f.close
      puts refusal { f.fcntl(Fcntl::F_GETFD) } rescue puts "IOError: #{$!.message}"
      r.close
      w.close

    RUBY

    _(result).must_answer <<~'OUT'
      Errno::ENOTTY: Inappropriate ioctl for device @ finish_narg - /etc/hosts
      Errno::EBADF: Bad file descriptor
      Errno::EBADF: Bad file descriptor @ finish_narg - <STDOUT>
      1
      true
      IOError: closed stream
    OUT
  end

  it "file io predicates and inspect" do
    result = zr(<<~'RUBY')
      # The real-uid stat predicates (`File.readable_real?` and its siblings) are
      # missing, so the program dies on line 10. ruby answers them from `stat(2)`
      # against the REAL uid/gid rather than the effective one.
      # File real-uid predicates, File.realdirpath, IO#inspect, String/IO.try_convert
      # Everything is compared against a path this test creates and resolves itself:
      # /tmp and /etc are symlinks on macOS, so a hardcoded expectation is not portable.
      dir = "spinel_rdp_test_dir"
      Dir.mkdir(dir) unless Dir.exist?(dir)
      path = File.join(dir, "sample.txt")
      File.write(path, "hello\n")
      real_dir = File.realpath(dir)

      p File.readable_real?(path)
      p File.readable_real?("no_such_spinel_file_xyz")
      p File.writable_real?("no_such_spinel_file_xyz")
      p File.executable_real?("no_such_spinel_file_xyz")
      p File.readable?(path)
      p File.readable?("no_such_spinel_file_xyz")

      p File.realdirpath(dir) == real_dir
      p File.realdirpath(File.join(dir, "missing_name_xyz")) == File.join(real_dir, "missing_name_xyz")
      p File.realdirpath("missing_name_xyz", dir) == File.join(real_dir, "missing_name_xyz")

      f = File.open(path)
      p f.inspect == "#<File:#{path}>"
      f.close
      p f.inspect == "#<File:#{path} (closed)>"
      p STDIN.inspect

      p String.try_convert("abc")
      p String.try_convert(5)
      p Integer.try_convert(5)

      p Math.expm1(0)
      p Math.log1p(0)

      File.delete(path)
      Dir.rmdir(dir)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      false
      false
      true
      false
      true
      true
      true
      true
      true
      "#<IO:<STDIN>>"
      "abc"
      nil
      5
      0.0
      0.0
    OUT
  end

  it "file read count" do
    result = zr(<<~'RUBY')
      # IO#read(n) reads up to n bytes from the current position, advancing it,
      # and returns nil at EOF. The no-arg form reads the rest of the file.
      path = "file_read_count_tmp.dat"
      File.delete(path) if File.exist?(path)

      File.open(path, "w") { |f| f.print "ABCDEFGHIJ" }

      f = File.open(path, "r")
      puts f.read(5).inspect
      puts f.read(5).inspect
      puts f.read(5).inspect
      f.close

      g = File.open(path, "r")
      puts g.read(3).inspect
      puts g.read.inspect
      g.close

      File.delete(path) if File.exist?(path)
    RUBY

    _(result).must_answer <<~'OUT'
      "ABCDE"
      "FGHIJ"
      nil
      "ABC"
      "DEFGHIJ"
    OUT
  end

  it "reopen makes a missing file, truncates where the mode says to, and dup2s one handle onto another" do
    result = zr(<<~'RUBY')
      require "tmpdir"

      DIR = Dir.tmpdir
      PROBE = File.join(DIR, "zeo_gap_reopen_#{Process.pid}")
      SINK = File.join(DIR, "zeo_gap_reopen_sink_#{Process.pid}")

      def try(label)
        p [label, yield]
      rescue StandardError => e
        p [label, e.class.to_s]
      ensure
        [PROBE, SINK].each { |f| File.delete(f) if File.exist?(f) }
      end

      # "w" onto a MISSING path creates it.
      try(:missing_w) do
        out = File.open(SINK, "w")
        out.reopen(PROBE, "w")
        out.puts "created"
        out.flush
        [File.exist?(PROBE), File.read(PROBE).chomp]
      end

      # "w" onto an EXISTING path truncates it.
      try(:existing_w) do
        File.write(PROBE, "stale")
        out = File.open(SINK, "w")
        out.reopen(PROBE, "w")
        out.puts "fresh"
        out.flush
        File.read(PROBE).chomp
      end

      # The one-argument form.
      try(:existing_bare) do
        File.write(PROBE, "stale")
        out = File.open(SINK, "w")
        out.reopen(PROBE)
        out.puts "bare"
        out.flush
        File.read(PROBE).chomp
      end

      # The IO-to-IO form.
      try(:io_to_io) do
        target = File.open(PROBE, "w")
        out = File.open(SINK, "w")
        out.reopen(target)
        out.puts "dup2"
        out.flush
        File.read(PROBE).chomp
      end

      # The one shape that DOES work, so a fix must not regress it.
      $stderr.reopen(IO::NULL)
      p :devnull_ok
    RUBY

    _(result).must_answer <<~'OUT'
      [:missing_w, [true, "created"]]
      [:existing_w, "fresh"]
      [:existing_bare, "bare"]
      [:io_to_io, "dup2"]
      :devnull_ok
    OUT
  end

  it "kernel gets reads the files argv names" do
    result = zr(<<~'RUBY', argv: ["core/io/argf_input.txt"], files: {"argf_input.txt" => "hello\nworld\nfin\n"})

      # A bare `gets` reads ARGF, not standard input: the files ARGV names,
      # one after another, with $. counting the lines across all of them.
      # $< is that same stream.
      p $<.equal?(ARGF)
      p gets
      p $.
      p readline
      p $.
      p readlines
      p gets
      p $.
      p ARGF.class.to_s

    RUBY

    _(result).must_answer <<~'OUT'
      true
      "hello\n"
      1
      "world\n"
      2
      ["fin\n"]
      nil
      3
      "ARGF.class"
    OUT
  end

  it "print puts expression and kinds" do
    result = zr(<<~'RUBY')
      # print renders Array/Hash/objects via to_s (it compile-errored on an Array
      # and printed blank for objects); puts/print compose as expressions
      # returning nil, like p.
      print [1, 2, 3]
      print "\n"
      print({ a: 1 })
      print "\n"
      print 1..3
      print "\n"
      x = puts("hi")
      p x
      r = print("a")
      puts
      p r
      puts (puts 7)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      {a: 1}
      1..3
      hi
      nil
      a
      nil
      7

    OUT
  end

  it "puts nested inspect container" do
    result = zr(<<~'RUBY')
      # puts flattens nested arrays recursively; a custom #inspect is honored for
      # elements inside containers (arrays, hashes), same as when inspected directly.
      puts [1, [2, [3]]]
      puts [[1, 2], [3, 4]]
      puts [1, [2, [3, [4, nil, [5]]]]]

      class Point127
        def inspect = "#<Point>"
      end
      p [Point127.new]
      p Point127.new
      p({ a: Point127.new })
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      3
      1
      2
      3
      4
      1
      2
      3
      4

      5
      [#<Point>]
      #<Point>
      {a: #<Point>}
    OUT
  end

  it "puts object nested new arg" do
    result = zr(<<~'RUBY')
      # puts/print of an object expression whose evaluation constructs nested
      # instances: the argument's hoisted declarations must land as complete
      # statements before the result temp's declaration.
      class Money
        attr_reader :c
        def initialize(c) = @c = c
        def +(o) = Money.new(c + o.c)
        def to_s = "$#{c}"
      end

      m = Money.new(5)
      puts(m + Money.new(3))
      puts(Money.new(1) + Money.new(2) + Money.new(4))
      print(m + Money.new(10))
      print("\n")
      puts "total: #{m + Money.new(7)}"
    RUBY

    _(result).must_answer <<~'OUT'
      $8
      $7
      $15
      total: $12
    OUT
  end

  it "raw descriptor carries the mode it was opened with" do
    result = zr(<<~'RUBY')
      # `IO.sysopen(path, mode, perm)` opens and hands back the raw fd. zeo read the
      # path and dropped everything after it, so the descriptor always came back
      # read-only and `IO.new(fd, "w").write` raised EBADF on a file the program had
      # just asked to open for writing. `File.open` dropped `perm` the same way.
      require "tmpdir"
      require "fileutils"

      dir = Dir.mktmpdir("zeo_sysopen")

      a = File.join(dir, "a.txt")
      File.open(a, "w", 0o600) { |f| f.write "x" }
      p format("%o", File.stat(a).mode & 0o777)

      b = File.join(dir, "b.txt")
      fd = IO.sysopen(b, "w", 0o640)
      w = IO.new(fd, "w")
      w.write("written")
      w.close
      p format("%o", File.stat(b).mode & 0o777)
      p File.read(b)

      # An `O_*` bitmask says the same thing a mode string does.
      c = File.join(dir, "c.txt")
      File.write(c, "hello")
      rw = IO.new(IO.sysopen(c, File::RDWR), "r+")
      rw.seek(0)
      rw.write("HE")
      rw.close
      p File.read(c)

      app = IO.new(IO.sysopen(c, "a"), "a")
      app.write("!")
      app.close
      p File.read(c)

      # The failure names CRuby's own syscall, `rb_sysopen`.
      begin
        IO.sysopen(File.join(dir, "nope.txt"), "r")
      rescue SystemCallError => e
        p [e.class, e.message.sub(dir, "DIR")]
      end

      # TWO IO objects over ONE live descriptor, both autoclosing. Ruby's second
      # close(2) fails EBADF: explicitly, that is the exception below; at teardown it
      # is silence. zeo let the native file object close the fd when it was
      # dropped, and a failed close there ABORTS -- so this program printed
      # everything and then died at exit.
      d = File.join(dir, "d.txt")
      File.write(d, "content")
      f = File.open(d)
      g = IO.new(f.fileno)
      p g.read
      p [f.closed?, g.closed?]
      f.close
      begin
        g.close
      rescue SystemCallError => e
        p [e.class, e.message]
      end

      # The pair that must still reach teardown with nothing to say.
      h = File.open(d)
      i = IO.new(h.fileno)
      p i.read

      FileUtils.remove_entry(dir)
      puts "ran to the end"
    RUBY

    _(result).must_answer <<~'OUT'
      "600"
      "640"
      "written"
      "HEllo"
      "HEllo!"
      [Errno::ENOENT, "No such file or directory @ rb_sysopen - DIR/nope.txt"]
      "content"
      [false, false]
      [Errno::EBADF, "Bad file descriptor"]
      "content"
      ran to the end
    OUT
  end

  it "splat print builtins" do
    result = zr(<<~'RUBY')
      # Splat into the print builtins and format expands the array elements.
      a = [1, 2, 3]
      puts(*a)
      print(*a)
      puts
      p(*a)
      args = ["%d-%d", 3, 4]
      puts format(*args)
      b = ["x", :y, [7, 8]]
      puts(*b)
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      3
      123
      1
      2
      3
      3-4
      x
      y
      7
      8
    OUT
  end

  it "ungetc reaches every reader" do
    result = zr(<<~'RUBY')
      # `#ungetc` pushed a byte onto a stack only `#getbyte` knew about, so
      # `f.ungetc("Z"); f.getc` answered the stream's next character and the pushed
      # byte was simply LOST -- the exact failure the comment on `peeked_read`
      # warns about ("a per-row unget stack would only have been drained by the one
      # row that knows about it").
      #
      # The bytes go into the read buffer now, at the cursor, which every reader
      # already consults. Two rules ride with them: the descriptor was never
      # advanced past a pushed byte, so giving the read-ahead back must not seek
      # over it; and a seek DISCARDS it, because there is nowhere to give it back.
      #
      # `#pos` was wrong for the same reason -- it reported the raw descriptor
      # offset, which sits wherever the last buffered fill stopped.

      require "tmpdir"
      dir = Dir.mktmpdir
      path = File.join(dir, "a")
      File.write(path, "one\ntwo\nthree\n")

      def fresh(path) = File.open(path)

      def show(label)
        puts "#{label} #{yield.inspect}"
      rescue Exception => e
        puts "#{label} #{e.class}: #{e.message}"
      end

      show("getc") { f = fresh(path); f.getc; f.ungetc("Z"); v = f.getc; f.close; v }
      show("read") { f = fresh(path); f.getc; f.ungetc("Z"); v = f.read(4); f.close; v }
      show("gets") { f = fresh(path); f.getc; f.ungetc("Z"); v = f.gets; f.close; v }
      show("getbyte") { f = fresh(path); f.getc; f.ungetc("Z"); v = f.getbyte; f.close; v }
      show("readpartial") { f = fresh(path); f.getc; f.ungetc("Z"); v = f.readpartial(3); f.close; v }
      show("read all") { f = fresh(path); f.getc; f.ungetc("Z"); v = f.read; f.close; v }
      show("each_char") { f = fresh(path); f.getc; f.ungetc("Z"); v = f.each_char.first(3); f.close; v }

      # A multi-byte push reads back in order, and an Integer pushes one byte.
      show("two bytes") { f = fresh(path); f.ungetc("AB"); v = [f.getc, f.getc, f.getc]; f.close; v }
      show("ungetbyte") { f = fresh(path); f.ungetbyte(65); v = f.getc; f.close; v }

      # The position counts what has been HANDED OUT, not what the descriptor read.
      show("pos") { f = fresh(path); f.getc; f.ungetc("Z"); v = f.pos; f.close; v }
      show("pos after getc") { f = fresh(path); f.getc; v = f.pos; f.close; v }
      show("eof?") { f = fresh(path); f.read; f.ungetc("Z"); v = [f.eof?, f.getc]; f.close; v }

      # A seek throws the pushed byte away.
      show("rewind") { f = fresh(path); f.getc; f.ungetc("Z"); f.rewind; v = f.getc; f.close; v }
      show("seek") { f = fresh(path); f.getc; f.ungetc("Z"); f.seek(0); v = f.getc; f.close; v }

      # A pipe has no descriptor to give read-ahead back to, and works the same.
      show("pipe") { r, w = IO.pipe; w.write("xy"); w.close; r.getc; r.ungetc("Q"); v = r.read; r.close; v }

      show("answers nil") { f = fresh(path); v = f.ungetc("Z"); f.close; v }

      require "fileutils"
      FileUtils.remove_entry(dir)
    RUBY

    _(result).must_answer <<~'OUT'
      getc "Z"
      read "Zne\n"
      gets "Zne\n"
      getbyte 90
      readpartial "Zne"
      read all "Zne\ntwo\nthree\n"
      each_char ["Z", "n", "e"]
      two bytes ["A", "B", "o"]
      ungetbyte "A"
      pos 0
      pos after getc 1
      eof? [false, "Z"]
      rewind "o"
      seek "o"
      pipe "Qy"
      answers nil nil
    OUT
  end
end
