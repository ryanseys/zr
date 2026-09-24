# frozen_string_literal: true

require "spec_helper"

describe "IO programs" do
  it "argf class no args" do
    result = zr(<<~'RUBY')
      # ARGF has its own pseudo-IO class; with no file args its filename is "-".
      puts ARGF.class
      puts ARGF.filename
    RUBY

    _(result).must_answer "ARGF.class\n-\n"
  end

  it "argf reads args" do
    result = zr(<<~'RUBY', argv: ["core/io/argf_input.txt"], files: {"argf_input.txt" => "hello\nworld\nfin\n"})

      # ARGF reads the files named in ARGV (here one file passed as an arg),
      # line by line; ARGF.filename names the current file.
      puts ARGF.filename
      ARGF.each_line do |line|
        puts line.chomp.upcase
      end
    RUBY

    _(result).must_answer <<~'OUT'
      core/io/argf_input.txt
      HELLO
      WORLD
      FIN
    OUT
  end

  it "armed gvl holder blocked on a full pipe write does not stall its siblings" do
    result = zr(<<~'RUBY', env: {"ZR_TEST_GVL" => "1"})
      # The write-side twin (the `write_rio` seam): 200KB overflows the
      # kernel pipe buffer, so the writer blocks mid-`write_all` until main
      # drains the pipe -- which main can only do if the writer released
      # the armed Gvl first.


      r, w = IO.pipe
      writer = Thread.new { w.write("x" * 200_000); w.close; :done }
      sleep 0.2
      data = r.read
      p writer.value
      p data.bytesize
    RUBY

    _(result).must_answer ":done\n200000\n"
  end

  it "armed gvl holder blocked on a pipe read does not stall its siblings" do
    result = zr(<<~'RUBY', env: {"ZR_TEST_GVL" => "1"})
      # The io-family without_gvl probe, in ZR_TEST_GVL=1 fidelity mode: the
      # reader parks on an EMPTY pipe while main sleeps, so without the
      # release at the `with_file` seam the reader would block INSIDE the
      # Gvl and main could never wake to perform the write -- this test
      # hangs there. Completing IS the proof of release.


      r, w = IO.pipe
      reader = Thread.new { r.gets }
      sleep 0.2
      w.puts "hello"
      p reader.value
    RUBY

    _(result).must_answer "\"hello\\n\"\n"
  end

  it "autoload feature composes dir and expand path" do
    result = zr(<<~'RUBY', files: beside("autoload_dir_expand/sub/also.rb", "autoload_dir_expand/sub/target.rb"))
      # An `autoload` target's feature text is folded at compile time from three
      # forms: a string literal, an interpolation whose computed part is `__dir__`,
      # and a whole `File.expand_path("<literal>", __dir__)`. They now COMPOSE --
      # `"#{File.expand_path("sub", __dir__)}/target"` is the shape rubygems and
      # bundler write, and it was none of the three, so the target was left entirely
      # to the run-time row and reading the constant raised `LoadError` for a file
      # that is right there.
      #
      # Reading THROUGH an autoloaded namespace is the second half. Only the fold
      # that materializes a Class immediate touched the autoload, so
      # `Holder::Composed` alone ran the target and `Holder::Composed::MARK` -- the
      # same read one level deeper -- raised `uninitialized constant` for a constant
      # the target assigns. A scoped read now touches its SCOPE, which is what CRuby
      # does before it looks the leaf up.

      module Holder
        autoload :Composed, "#{File.expand_path("autoload_dir_expand/sub", __dir__)}/target"
      end

      puts "before"
      p Holder.autoload?(:Composed) != nil
      # The NESTED read, which is what has to run the target: nothing has read
      # `Holder::Composed` on its own.
      p Holder::Composed::MARK
      p Holder.autoload?(:Composed) != nil
      p Holder::Composed.name

      module Sibling
        autoload :Also, "#{File.expand_path("autoload_dir_expand/sub", __dir__)}/also"
      end
      # The bare read of the constant itself, the shape that already worked.
      p Sibling::Also.tag
    RUBY

    _(result).must_answer <<~'OUT'
      before
      true
      target ran
      :composed
      false
      "Holder::Composed"
      also ran
      :also
    OUT
  end

  it "autoload with file expand path dir resolves a sibling file" do
    result = zr(<<~'RUBY', files: beside("autoload_sibling/main.rb", "autoload_sibling/mirror.rb"))
      # The dominant stdlib/bundler idiom: `autoload :C, File.expand_path("c",
      # __dir__)` -- a computed sibling path. Resolved at compile time from the
      # requiring file's directory.

      require_relative "autoload_sibling/main"
    RUBY

    _(result).must_answer "mirror!\n"
  end

  it "backtick captures stdout and sets child status" do
    result = zr(<<~'RUBY')
      # `` `cmd` `` lowers to a `Kernel#\`` fcall: it captures the child's
      # stdout as a String and leaves the wait status in `$?`.

      out = `echo hello`
      print out
      puts out.length
      puts $?.exitstatus
      puts $?.success?
      puts $?.class
    RUBY

    _(result).must_answer <<~'OUT'
      hello
      6
      0
      true
      Process::Status
    OUT
  end

  it "boxs required file patches a shared class privately" do
    files = beside("box_required_file/main.rb", "box_required_file/patch.rb")

    result = zr(<<~'RUBY', env: {"RUBY_BOX" => "1"}, files: files, ruby: ["-W:no-experimental"])
      # A box loading a FILE (rather than an eval'd string) isolates the same
      # way. The two routes reach the compiler differently -- a literal
      # `box.eval` is spliced at compile time and a `require_relative` brings in
      # a whole unit -- so both need saying.



      require_relative "box_required_file/main"
    RUBY

    _(result).must_answer <<~'OUT'
      false
      "go"
    OUT
  end

  it "break inside begin rescue targets the enclosing native loop" do
    result = zr(<<~'RUBY')
      # A bare `break`/`next`/`redo` inside a `begin`/`rescue`/`else` clause
      # targeting a native loop OUTSIDE the `begin`. The `begin`
      # expression is spliced INLINE in the loop body, so its final settling
      # translates the bubbled `Signal` into the loop's own literal jump -- no
      # loop-body closure needed. A
      # loop written INSIDE the `begin` is unaffected (the previous test).

      i = 0
      while i < 5
        begin
          break if i == 3
          puts "body #{i}"
        rescue
        end
        i += 1
      end
      puts "after"
    RUBY

    _(result).must_answer <<~'OUT'
      body 0
      body 1
      body 2
      after
    OUT
  end

  it "descriptor wait sees data and hang up" do
    result = zr(<<~'RUBY')
      # Waiting on one descriptor: a pipe with nothing in it is not readable,
      # data makes it readable but not priority-readable, and a closed write
      # end makes it readable too (a read then answers EOF). A pipe's write
      # end is writable at once.
      r, w = IO.pipe
      p IO.select([r], nil, nil, 0)
      p IO.select(nil, [w], nil, 0) == [[], [w], []]
      w.write("x")
      p IO.select([r], nil, nil, 1) == [[r], [], []]
      p IO.select(nil, nil, [r], 0)
      p r.wait_readable(1) == r
      p r.wait_priority(0)
      p r.read(1)
      p IO.select([r], nil, nil, 0)
      w.close
      p IO.select([r], nil, nil, 1) == [[r], [], []]
      p r.read
      r.close

    RUBY

    _(result).must_answer <<~'OUT'
      nil
      true
      true
      nil
      true
      nil
      "x"
      nil
      true
      ""
    OUT
  end

  it "diamond requires execute the shared file exactly once" do
    files = beside("diamond_requires/liba.rb", "diamond_requires/libb.rb", "diamond_requires/main.rb",
                   "diamond_requires/shared.rb")

    result = zr(<<~'RUBY', files: files)
      require_relative "diamond_requires/main"
    RUBY

    _(result).must_answer <<~'OUT'
      shared executed
      liba loaded
      libb loaded
      7
    OUT
  end

  it "dir exist" do
    result = zr(<<~'RUBY')
      puts Dir.exist?(".")
      puts Dir.exist?("no_such_dir_xyz123")
    RUBY

    _(result).must_answer "true\nfalse\n"
  end

  it "dir glob semantics" do
    result = zr(<<~'RUBY')
      # `Dir.glob`: `*` within a segment, `**` across them, `?`, `{a,b}`
      # alternation, and Ruby's hidden-file rule (a leading `.` is invisible to a
      # wildcard).

      dir = File.join(ENV.fetch("TMPDIR", "/tmp"), "zr_e2e_glob_#{Process.pid}")
      Dir.mkdir(dir)
      begin
        Dir.chdir(dir) do
          Dir.mkdir("sub")
          File.write("x.rb", "")
          File.write("y.txt", "")
          File.write(".hidden", "")
          File.write("sub/z.rb", "")

          p Dir.glob("*.rb").sort
          p Dir.glob("**/*.rb").sort
          p Dir.glob("sub/*.rb")
          p Dir.glob("*.{rb,txt}").sort
          p Dir.glob("?.rb")
          p Dir["*.rb"]
          p Dir.glob("*").sort
          p Dir.glob("*").include?(".hidden")
          p Dir.glob(".*").include?(".hidden")

          File.delete("x.rb", "y.txt", ".hidden", "sub/z.rb")
          Dir.rmdir("sub")
        end
      ensure
        Dir.rmdir(dir)
      end
    RUBY

    _(result).must_answer <<~'OUT'
      ["x.rb"]
      ["sub/z.rb", "x.rb"]
      ["sub/z.rb"]
      ["x.rb", "y.txt"]
      ["x.rb"]
      ["x.rb"]
      ["sub", "x.rb", "y.txt"]
      false
      true
    OUT
  end

  it "dir handle argf binding" do
    result = zr(<<~'RUBY')
      # Dir.new/Dir.open handles, ARGF's literally-named class and default "-"
      # filename (run with no file arguments), and binding.local_variable_get reading
      # an in-scope local -- including a reserved-word parameter.
      dir = "/tmp/sp_ex_dirh_#{Process.pid}"
      Dir.mkdir(dir) unless Dir.exist?(dir)
      File.write("#{dir}/x", "")
      File.write("#{dir}/y", "")

      d = Dir.new(dir)
      p d.class
      p d.path == dir
      names = []
      d.each { |n| names << n }
      p names.sort
      d.rewind
      p d.read.class
      d.close

      p Dir.open(dir) { |dd| dd.children.sort }
      p Dir.open(dir) { |dd| dd.entries.sort }
      p((Dir.new("/nonexistent_zz_example") rescue $!.class))
      File.delete("#{dir}/x", "#{dir}/y")
      Dir.rmdir(dir)

      p ARGF.class
      p ARGF.filename

      def read_reserved(then:)
        binding.local_variable_get(:then)
      end
      p read_reserved(then: :tick)

      def read_named(name:)
        binding.local_variable_get(:name)
      end
      p read_named(name: "hello")

      x = [1, 2, 3]
      p binding.local_variable_get(:x)
    RUBY

    _(result).must_answer <<~'OUT'
      Dir
      true
      [".", "..", "x", "y"]
      String
      ["x", "y"]
      [".", "..", "x", "y"]
      Errno::ENOENT
      ARGF.class
      "-"
      :tick
      "hello"
      [1, 2, 3]
    OUT
  end

  it "dir listing distinguishes entries from children" do
    result = zr(<<~'RUBY')
      # `Dir` listing: `entries` includes `.`/`..`, `children` does not.

      dir = File.join(ENV.fetch("TMPDIR", "/tmp"), "zr_e2e_list_#{Process.pid}")
      Dir.mkdir(dir)
      begin
        File.write(File.join(dir, "a.rb"), "")
        File.write(File.join(dir, "b.txt"), "")
        Dir.mkdir(File.join(dir, "sub"))

        p Dir.children(dir).sort
        p Dir.entries(dir).sort
        p Dir.exist?(dir)
        p Dir.exist?(File.join(dir, "a.rb"))
        p Dir.exist?("/definitely/not/here")
        p Dir.empty?(File.join(dir, "sub"))
        p Dir.pwd.start_with?("/")

        Dir.rmdir(File.join(dir, "sub"))
        File.delete(File.join(dir, "a.rb"), File.join(dir, "b.txt"))
      ensure
        Dir.rmdir(dir)
      end
    RUBY

    _(result).must_answer <<~'OUT'
      ["a.rb", "b.txt", "sub"]
      [".", "..", "a.rb", "b.txt", "sub"]
      true
      false
      false
      true
      true
    OUT
  end

  it "directory and a descriptor answer their own numbers" do
    result = zr(<<~'RUBY')
      # A directory is an open descriptor of its own: #fileno answers the
      # same number every time, and a closed directory answers nothing at
      # all. A stream answers the flags fcntl reads from its descriptor, and
      # a closed stream refuses that too.
      require "tmpdir"

      def t = yield rescue [$!.class, $!.message]

      Dir.mktmpdir do |dir|
        d = Dir.new(dir)
        p d.fileno == d.fileno
        p d.fileno > 2
        d.close
        p t { d.fileno }
        p t { d.read }

        e = Dir.for_fd(File.open(dir).fileno)
        p e.fileno.is_a?(Integer)
        e.close

        f = File.open(File.join(dir, "y"), "w")
        p f.fcntl(3, 0) & 3
        p f.fcntl(3) & 3
        p f.fcntl(1, 0).is_a?(Integer)
        f.close
        p t { f.fcntl(1, 0) }

        File.open(File.join(dir, "y")) { |r| p r.fcntl(3) & 3 }
      end

    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      [IOError, "closed directory"]
      [IOError, "closed directory"]
      true
      1
      1
      true
      [IOError, "closed stream"]
      0
    OUT
  end

  it "dying program orders its output and its report" do
    result = zr(<<~'RUBY')
      # The report of an uncaught exception goes through the `$stderr` OBJECT, so
      # the order it lands in follows each stream's own buffer rather than any
      # flush of zr's choosing.
      #
      # With both streams sent to one place, the report queues behind whatever the
      # program already wrote, so the output comes first -- and an at_exit handler
      # that writes goes out before the report of its own raise. (The order between
      # two streams on two descriptors is not visible to a case, which keeps stdout
      # and stderr apart; test/runtime/no_method.rb holds that one.)
      $stderr = $stdout

      at_exit { puts "at_exit wrote this" }
      $stdout.write("a plain write\n")
      puts "a line through puts"
      warn "a warning"
      raise "the program gave up"

    RUBY

    _(result).must_answer <<~'OUT', status: 1
      a plain write
      a line through puts
      a warning
      at_exit wrote this
      core/io/io_test.rb:16:in '<main>': the program gave up (RuntimeError)
    OUT
  end

  it "env select shadowed by kernel" do
    result = zr(<<~'RUBY')
      ENV["ZR_TEST_PROBE_X"] = "1"
      p ENV.select { |k, v| k == "ZR_TEST_PROBE_X" }
      p ENV.reject { |k, v| k != "ZR_TEST_PROBE_X" }
      p ENV.filter { |k, v| k == "ZR_TEST_PROBE_X" }
    RUBY

    _(result).must_answer <<~'OUT'
      {"ZR_TEST_PROBE_X" => "1"}
      {"ZR_TEST_PROBE_X" => "1"}
      {"ZR_TEST_PROBE_X" => "1"}
    OUT
  end

  it "eval file and line arguments" do
    result = zr(<<~'RUBY')
      # `eval`'s 3rd and 4th arguments name the snippet, and a snippet is a real
      # scope: it gets a frame of its own, under the label of the BINDING it runs
      # in -- not the caller's -- and each statement stamps its own line, counted
      # from the `lineno` argument. Below it sits the frame of the entry the source
      # came through (`Kernel#eval`, `Binding#eval`, ...).
      b = binding
      p eval("__FILE__", b, "fake.rb", 100)
      p eval("__LINE__", b, "fake.rb", 100)
      begin
        eval("raise 'x'", b, "fake.rb", 10)
      rescue => e
        p e.backtrace.first
      end

      # Every entry, and the `(eval at FILE:LINE)` name a snippet with no `file`
      # argument takes.
      begin; b.eval("raise 'a'", "f.rb", 1); rescue => e; p e.backtrace; end
      begin; Object.new.instance_eval("raise 'c'"); rescue => e; p e.backtrace; end
      begin; String.class_eval("raise 'd'"); rescue => e; p e.backtrace; end

      # The line advances with the snippet's own newlines.
      begin
        eval("\n\nraise 'w'", b, "multi.rb", 5)
      rescue => e
        p e.backtrace.first
      end

      # An eval under a binding captured inside a METHOD runs in that method's name.
      def outer
        bb = binding
        eval("raise 'm'", bb, "f1.rb", 1)
      rescue => e
        p e.backtrace.first(2)
      end
      outer

      # A method DEFINED by an eval reports the snippet it was written in, at the
      # `def`'s own line -- not the eval's first line.
      begin
        eval("def m_in_eval\n  raise 'q'\nend\nm_in_eval", b, "deffile.rb", 3)
      rescue => e
        p e.backtrace.first(3)
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "fake.rb"
      100
      "fake.rb:10:in '<main>'"
      ["f.rb:1:in '<main>'", "core/io/io_test.rb:17:in 'Binding#eval'", "core/io/io_test.rb:17:in '<main>'"]
      ["(eval at core/io/io_test.rb:18):1:in '<main>'", "core/io/io_test.rb:18:in 'BasicObject#instance_eval'", "core/io/io_test.rb:18:in '<main>'"]
      ["(eval at core/io/io_test.rb:19):1:in '<main>'", "core/io/io_test.rb:19:in 'Module#class_eval'", "core/io/io_test.rb:19:in '<main>'"]
      "multi.rb:7:in '<main>'"
      ["f1.rb:1:in 'Object#outer'", "core/io/io_test.rb:31:in 'Kernel#eval'"]
      ["deffile.rb:4:in 'Object#m_in_eval'", "deffile.rb:6:in '<main>'", "core/io/io_test.rb:40:in 'Kernel#eval'"]
    OUT
  end

  it "fcntl takes a struct in a string", only: "macos" do
    result = zr(<<~'RUBY')

      # IO#fcntl passes a String as the struct a command reads and fills, as a
      # file lock does, and refuses a frozen one.
      require "fcntl"
      require "tmpdir"

      Dir.mktmpdir do |dir|
        File.open(File.join(dir, "lock"), "w+") do |f|
          # darwin's struct flock: l_start, l_len, l_pid, l_type, l_whence.
          lock = [0, 0, 0, Fcntl::F_WRLCK, 0].pack("q q i s s")
          p f.fcntl(Fcntl::F_SETLK, lock)
          probe = [0, 0, 0, Fcntl::F_RDLCK, 0].pack("q q i s s")
          p f.fcntl(Fcntl::F_GETLK, probe), probe.unpack("q q i s s")[3] == Fcntl::F_UNLCK
        end
      end
      p((STDIN.fcntl(Fcntl::F_GETFL, "x".freeze) rescue $!.class))

    RUBY

    _(result).must_answer <<~'OUT'
      0
      0
      true
      FrozenError
    OUT
  end

  it "file and line report the eval site" do
    result = zr(<<~'RUBY')
      f = "__FILE__"
      p eval(f)
      l = "__LINE__"
      p eval(l)
    RUBY

    _(result).must_answer <<~'OUT'
      "(eval at core/io/io_test.rb:2)"
      1
    OUT
  end

  it "file basename gc" do
    result = zr(<<~'RUBY')
      # sp_file_basename used to return `path + offset` — a pointer into
      # the input path. Without keeping the underlying buffer rooted, the
      # GC could free the path string, leaving the held basename dangling.
      #
      # Triggering the bug requires:
      #  - A path constructed dynamically (heap string, not literal).
      #  - A basename returned from a helper, so the path goes out of scope.
      #  - GC pressure that actually fires `sp_gc_collect` so `sp_str_sweep`
      #    walks the string heap and reaps the unreferenced path. String
      #    allocations alone don't accrue to `sp_gc_bytes` (per the comment
      #    in `sp_str_alloc`); we need object allocations to push past the
      #    threshold.
      #
      # The fix returns a fresh sp_str_alloc'd copy whose own `\xfe` tag
      # byte makes mark_string take the right path, and which survives
      # independently of the original path.

      class Trash
        def initialize(n)
          @n = n
          @s = "padding payload " * 64    # ~1 KB heap string per Trash
        end
        attr_reader :n
      end

      def name_of(i)
        path = "/very/deep/parent/directory/with/many/segments/file" + i.to_s + ".rb"
        File.basename(path)
      end

      names = []
      i = 0
      while i < 50
        names << name_of(i)
        i = i + 1
      end

      # Allocate ~5000 Trash instances (~5 MB) — far past the 256 KB GC
      # threshold — to force multiple sp_gc_collect cycles and reap the
      # unreferenced path strings via sp_str_sweep.
      junk = []
      j = 0
      while j < 5000
        junk << Trash.new(j)
        j = j + 1
      end
      puts junk.length     # 5000

      # Each names[i] should still resolve to "fileN.rb".
      ok = 1
      i = 0
      while i < 50
        expected = "file" + i.to_s + ".rb"
        if names[i] != expected
          ok = 0
        end
        i = i + 1
      end
      puts(ok == 1 ? "ok" : "corrupt")    # ok
    RUBY

    _(result).must_answer "5000\nok\n"
  end

  it "file constants module" do
    result = zr(<<~'RUBY')
      # The open/lock/fnmatch flags are a MODULE that `IO` includes, not a bag of
      # constants on `File`. That is what makes `IO::APPEND` and `File::APPEND` the
      # same constant and what puts `File::Constants` in `IO.ancestors` -- a program
      # that opens an IO with `File::RDONLY` is relying on exactly that sharing.

      p File::Constants.constants.sort
      p File::Constants.class
      p IO.include?(File::Constants)
      p File.include?(File::Constants)
      p IO.ancestors.first(4)

      # The same constant, reached three ways.
      p [File::APPEND, IO::APPEND, File::Constants::APPEND].uniq.size
      p File::RDONLY == IO::RDONLY

      # ...including under a name computed at run time.
      name = "LOCK_EX"
      p [IO.const_get(name), File.const_get(name), File::Constants.const_get(name)].uniq.size

      # The seek/wait constants stay IO's own -- CRuby does not put them in the
      # shared module.
      p [IO::SEEK_SET, IO::SEEK_CUR, IO::SEEK_END, IO::SEEK_HOLE, IO::SEEK_DATA]
      p [IO::READABLE, IO::PRIORITY, IO::WRITABLE]
      p File::Constants.constants.include?(:SEEK_SET)

      # Regexp's two encoding option bits, which zr never sets but a program may
      # still AND against.
      p [Regexp::FIXEDENCODING, Regexp::NOENCODING]
      p(/a/.options & Regexp::FIXEDENCODING)

      # And the flags still do their job.
      File.open(File::NULL, File::RDONLY) { |f| p f.class }
      p File::NULL == IO::NULL
    RUBY

    _(result).must_answer <<~'OUT'
      [:APPEND, :BINARY, :CREAT, :DSYNC, :EXCL, :FNM_CASEFOLD, :FNM_DOTMATCH, :FNM_EXTGLOB, :FNM_NOESCAPE, :FNM_PATHNAME, :FNM_SHORTNAME, :FNM_SYSCASE, :LOCK_EX, :LOCK_NB, :LOCK_SH, :LOCK_UN, :NOCTTY, :NOFOLLOW, :NONBLOCK, :NULL, :RDONLY, :RDWR, :SHARE_DELETE, :SYNC, :TRUNC, :WRONLY]
      Module
      true
      true
      [IO, File::Constants, Enumerable, Object]
      1
      true
      1
      [0, 1, 2, 3, 4]
      [1, 2, 4]
      false
      [16, 32]
      0
      File
      true
    OUT
  end

  it "file dir methods" do
    result = zr(<<~'RUBY')
      # Issue #892: File.extname / .basename / .dirname / Dir.pwd.
      puts File.extname("hello.rb")
      puts File.basename("/home/user/file.rb")
      puts File.dirname("/home/user/file.rb")
      # Edge cases.
      puts File.extname(".bashrc")       # "" — leading-dot only
      puts File.extname("foo.")          # ""
      puts File.dirname("foo")           # "."
      puts File.dirname("/usr/local")    # "/usr"
      # Dir.pwd returns a string.
      puts Dir.pwd.length > 0
    RUBY

    _(result).must_answer <<~'OUT'
      .rb
      file.rb
      /home/user

      .
      .
      /usr
      true
    OUT
  end

  it "file errors are real errno classes" do
    result = zr(<<~'RUBY')
      # A missing path raises the right `Errno::*`, with CRuby's message shape --
      # and it is catchable by its PARENT (`SystemCallError`), which is what the
      # prelude hierarchy buys.

      begin
        File.read("/definitely/not/here")
      rescue Errno::ENOENT => e
        puts "#{e.class}: #{e.message}"
      end
      p Errno::ENOENT.superclass
      p Errno::ENOENT.ancestors.include?(StandardError)
      begin
        Dir.entries("/definitely/not/here")
      rescue SystemCallError => e
        puts e.class
      end
      begin
        File.read(5)
      rescue TypeError => e
        puts "TypeError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      Errno::ENOENT: No such file or directory @ rb_sysopen - /definitely/not/here
      SystemCallError
      true
      Errno::ENOENT
      TypeError
    OUT
  end

  it "file expand path" do
    result = zr(<<~'RUBY')
      # File.expand_path: pure-string absolute-path expansion. Only absolute
      # bases/paths are exercised so the result is independent of cwd/HOME.
      puts File.expand_path("test", "/tmp")
      puts File.expand_path("/a/b/c")
      puts File.expand_path("../x", "/a/b")
      puts File.expand_path("./y", "/a/b")
      puts File.expand_path("a/../b/./c", "/root")
      puts File.expand_path("", "/tmp")
      puts File.expand_path("/")
      puts File.expand_path("p/q/../../r", "/base")
    RUBY

    _(result).must_answer <<~'OUT'
      /tmp/test
      /a/b/c
      /a/x
      /a/b/y
      /root/b/c
      /tmp
      /
      /base/r
    OUT
  end

  it "file foreach separator" do
    result = zr(<<~'RUBY')
      require "tmpdir"

      Dir.mktmpdir do |d|
        f = File.join(d, "o.txt")
        File.write(f, "l1\nl2\n")
        p File.foreach(f, "1").first
        p File.foreach(f).first
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "l1"
      "l1\n"
    OUT
  end

  it "file ftype foreach and dir foreach" do
    result = zr(<<~'RUBY')
      require "tmpdir"
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "a.txt"), "one\ntwo\nthree\n")
        Dir.mkdir(File.join(dir, "sub"))
        p File.ftype(File.join(dir, "a.txt"))
        p File.ftype(File.join(dir, "sub"))
        File.foreach(File.join(dir, "a.txt")) { |line| print "L:", line }
        p File.foreach(File.join(dir, "a.txt"), chomp: true).to_a
        # Enumerator form gives the entries; block form returns nil.
        p Dir.foreach(dir).to_a.sort
        p(Dir.foreach(dir) { |e| })
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "file"
      "directory"
      L:one
      L:two
      L:three
      ["one", "two", "three"]
      [".", "..", "a.txt", "sub"]
      nil
    OUT
  end

  it "file join collapses separators" do
    result = zr(<<~'RUBY')
      # `File.join` collapses a separator at the seam rather than doubling it, and
      # flattens a nested Array argument.

      puts File.join("a", "b", "c")
      puts File.join("a/", "b")
      puts File.join("a", "/b")
      puts File.join("a/", "/b")
      puts File.join("/a", "b")
      puts File.join("a", ["b", "c"])
      p File.absolute_path?("/abs")
      p File.absolute_path?("rel")
    RUBY

    _(result).must_answer <<~'OUT'
      a/b/c
      a/b
      a/b
      a/b
      /a/b
      a/b/c
      true
      false
    OUT
  end

  it "file join poly component" do
    result = zr(<<~'RUBY')
      # A poly component of File.join (here: an element read from a heterogeneous
      # array) initializes a `const char *` slot in the sp_file_join argument list,
      # so it must be coerced with sp_poly_to_s rather than land its sp_RbVal raw
      # (doom's SoundManager builds its temp dir from a poly Dir.tmpdir value).
      parts = ["sounds", 7]
      dir = parts[0]
      path = File.join(dir, "doom_rb")
      puts path
      puts File.join("a", "b", "c")
    RUBY

    _(result).must_answer "sounds/doom_rb\na/b/c\n"
  end

  it "file open block form and positioned reads" do
    result = zr(<<~'RUBY')
      # `File.open`: the block form closes on every exit path and answers the
      # block's value. A LENGTHED read at EOF is nil where a whole-rest read is
      # `""` -- the asymmetry a `while chunk = f.read(n)` loop relies on.

      dir = File.join(ENV.fetch("TMPDIR", "/tmp"), "zr_e2e_open_#{Process.pid}")
      Dir.mkdir(dir)
      begin
        path = File.join(dir, "counted.txt")
        File.open(path, "w") { |f| f.print "ABCDEFGHIJ" }
        p File.read(path)

        File.open(path, "r") do |f|
          p f.read(5)
          p f.read(5)
          p f.read(5)
          f.rewind
          p f.read(2)
          p f.tell
          f.seek(0)
          p f.read
          p f.eof?
        end

        p File.open(path, "r") { |f| f.read(3) }

        h = File.open(path, "r")
        p h.closed?
        h.close
        p h.closed?
        begin
          h.read
        rescue IOError => e
          puts "IOError: #{e.message}"
        end

        File.delete(path)
      ensure
        Dir.rmdir(dir)
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "ABCDEFGHIJ"
      "ABCDE"
      "FGHIJ"
      nil
      "AB"
      2
      "ABCDEFGHIJ"
      true
      "ABC"
      false
      true
      IOError: closed stream
    OUT
  end

  it "file open closes even when the block raises" do
    result = zr(<<~'RUBY')
      # `File.open`'s block form closes the file even when the block RAISES --
      # that ensure is the whole reason the idiom exists.

      dir = File.join(ENV.fetch("TMPDIR", "/tmp"), "zr_e2e_raise_#{Process.pid}")
      Dir.mkdir(dir)
      begin
        path = File.join(dir, "x.txt")
        File.write(path, "data")
        handle = nil
        begin
          File.open(path, "r") do |f|
            handle = f
            raise "boom"
          end
        rescue RuntimeError => e
          puts "rescued: #{e.message}"
        end
        p handle.closed?
        File.delete(path)
      ensure
        Dir.rmdir(dir)
      end
    RUBY

    _(result).must_answer "rescued: boom\ntrue\n"
  end

  it "file predicates answer rather than raise" do
    result = zr(<<~'RUBY')
      # The `File.<predicate>?` family answers false for a missing path rather
      # than raising -- and `size?` is nil for a missing OR empty file, though
      # `size` is 0 for an empty one.

      dir = File.join(ENV.fetch("TMPDIR", "/tmp"), "zr_e2e_pred_#{Process.pid}")
      Dir.mkdir(dir)
      begin
        full = File.join(dir, "full.txt")
        empty = File.join(dir, "empty.txt")
        missing = File.join(dir, "missing.txt")
        File.write(full, "12345")
        File.write(empty, "")

        p [File.exist?(full), File.exist?(missing)]
        p [File.file?(full), File.file?(dir)]
        p [File.directory?(dir), File.directory?(full)]
        p [File.zero?(empty), File.zero?(full)]
        p File.size(full)
        p File.size(empty)
        p File.size?(full)
        p File.size?(empty)
        p File.size?(missing)
        p [File.exist?(missing), File.file?(missing), File.directory?(missing)]

        File.delete(full, empty)
      ensure
        Dir.rmdir(dir)
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [true, false]
      [true, false]
      [true, false]
      [true, false]
      5
      0
      5
      nil
      nil
      [false, false, false]
    OUT
  end

  it "file predicates times and fnm constants" do
    result = zr(<<~'RUBY')
      # File-type/permission predicates, time accessors, and the FNM_* flag
      # constants, exercised on a file the test writes.

      p [File::FNM_DOTMATCH, File::FNM_PATHNAME, File::FNM_CASEFOLD, File::FNM_NOESCAPE, File::FNM_EXTGLOB]
      path = "/tmp/sp_e2e_file_probe"
      File.write(path, "hi"); File.chmod(0644, path)
      p File.world_readable?(path)
      p [File.pipe?(path), File.socket?(path), File.chardev?(path), File.blockdev?(path)]
      p [File.owned?(path), File.setuid?(path), File.sticky?(path)]
      p File.identical?(path, path)
      p [File.birthtime(path).class, File.atime(path).class, File.ctime(path).class]
      link = "/tmp/sp_e2e_file_link"
      File.symlink(path, link)
      p [File.symlink?(link), File.readlink(link) == path]
      File.delete(link); File.delete(path)
    RUBY

    _(result).must_answer <<~'OUT'
      [4, 2, 8, 1, 16]
      420
      [false, false, false, false]
      [true, false, false]
      true
      [Time, Time, Time]
      [true, true]
    OUT
  end

  it "file pure path family" do
    result = zr(<<~'RUBY')
      # `File`'s pure-path family: string work that never touches the disk. Every
      # expectation oracle-read from ruby 4.0.6 -- including the two that read
      # like off-by-ones (a TRAILING dot IS an extension, a LEADING one is not).

      puts File.basename("/home/user/notes.md")
      puts File.basename("/home/user/notes.md", ".md")
      puts File.basename("/home/user/notes.md", ".*")
      puts File.basename("/a/b/")
      puts File.basename("/")
      puts File.dirname("/home/user/notes.md")
      puts File.dirname("solo")
      puts File.dirname("/x")
      p File.extname("archive.tar.gz")
      p File.extname(".bashrc")
      p File.extname("trailing.")
      p File.extname("plain")
      p File.split("/a/b/c.rb")
    RUBY

    _(result).must_answer <<~'OUT'
      notes.md
      notes
      notes
      b
      /
      /home/user
      .
      /
      ".gz"
      ""
      "."
      ""
      ["/a/b", "c.rb"]
    OUT
  end

  it "file unlink rename" do
    result = zr(<<~'RUBY')
      filename = "test_unlink_rename_temp.txt"
      renamed = "test_unlink_rename_temp2.txt"
      File.write(filename, "file op test")
      File.rename(filename, renamed)
      puts File.exist?(filename)
      puts File.exist?(renamed)
      File.unlink(renamed)
      puts File.exist?(renamed)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      false
    OUT
  end

  it "for fd takes the mode the descriptor has" do
    result = zr(<<~'RUBY')
      # A descriptor opened for writing alone becomes a stream with no mode
      # given, and read_nonblock says EAGAIN once in its message.
      r, w = IO.pipe
      x = IO.for_fd(w.fileno, autoclose: false)
      p (x.write("a") rescue $!), (x.read rescue $!)
      r, w = IO.pipe
      begin; r.read_nonblock(1); rescue => e; p e.message, e.class, e.detailed_message; end
      begin; IO.new(r.fileno, autoclose: false).read_nonblock(1); rescue => e; p e.message; end

    RUBY

    _(result).must_answer <<~'OUT'
      1
      #<IOError: not opened for reading>
      "Resource temporarily unavailable - read would block"
      IO::EAGAINWaitReadable
      "Resource temporarily unavailable - read would block (IO::EAGAINWaitReadable)"
      "Resource temporarily unavailable - read would block"
    OUT
  end

  it "if else void branch value" do
    result = zr(<<~'RUBY')
      # An if/else used in value position whose branches have mismatched value
      # types -- a typed branch vs a void/nil branch like `$stdout.puts` -- must
      # emit valid C. The puts branch is emitted as a single comma expression
      # (joined value, yielding nil), not `;`-separated statements that are illegal
      # inside the surrounding `return (...)`.

      def w(flag, line)
        if flag
          line.length          # Integer branch
        else
          $stdout.puts(line)   # void puts in value position -> nil
        end
      end

      p w(true, "abc")         # 3
      p w(false, "xy")         # prints "xy", then the call returns nil

      # multi-argument puts (each argument on its own line) as a statement
      $stdout.puts("a", "b")
    RUBY

    _(result).must_answer <<~'OUT'
      3
      xy
      nil
      a
      b
    OUT
  end

  it "IO::Buffer.new answers its size and prints no experimental warning" do
    result = zr(<<~'RUBY')
      b = IO::Buffer.new(8)
      p b.size
    RUBY

    _(result).must_answer "8\n", stderr: <<~'ERR'
      core/io/io_test.rb:1: warning: IO::Buffer is experimental and both the Ruby and C interface may change in the future!
    ERR
  end

  it "a buffered read leaves the descriptor where ruby consumed to, not where the read-ahead reached" do
    result = zr(<<~'RUBY')
      # Line and character reads buffer ahead, so every operation that observes or
      # moves the file position has to see the descriptor where RUBY consumed to,
      # never where the read-ahead left it.

      path = "/tmp/zr_buffered_read_#{Process.pid}.txt"
      File.open(path, "w") { |f| f.write("alpha\nbeta\ngamma\ndelta\n") }

      # `pos` after a buffered line read.
      File.open(path, "r") do |f|
        p f.gets
        p f.pos
        p f.gets
        p f.pos
      end

      # `read` picks up exactly where `gets` stopped.
      File.open(path, "r") do |f|
        p f.gets
        p f.read
      end

      # `seek` and `rewind` land where they say, mid-buffer.
      File.open(path, "r") do |f|
        f.gets
        f.seek(6)
        p f.gets
        f.rewind
        p f.gets
        f.seek(-6, IO::SEEK_END)
        p f.read
      end

      # `getc` and `getbyte` share the same buffer as `gets`.
      File.open(path, "r") do |f|
        p f.getc
        p f.getbyte
        p f.gets
        p f.pos
      end

      # `ungetbyte` is still returned ahead of anything buffered.
      File.open(path, "r") do |f|
        f.gets
        f.ungetbyte(88)
        p f.getbyte
        p f.gets
      end

      # `eof?` reports on the logical position, not the read-ahead one.
      File.open(path, "r") do |f|
        p f.eof?
        f.gets
        p f.eof?
        f.read
        p f.eof?
      end

      # A separate handle sees the file whole, whatever the first one buffered.
      File.open(path, "r") do |f|
        f.gets
        File.open(path, "r") { |g| p g.read.length }
        p f.pos
      end

      # `each_line` leaves the position at end of file.
      File.open(path, "r") do |f|
        n = 0
        f.each_line { |l| n += 1 }
        p n
        p f.pos
        p f.eof?
      end

      # Breaking out of `each_line` stops after the line the block last saw.
      File.open(path, "r") do |f|
        f.each_line do |l|
          break if l.start_with?("beta")
        end
        p f.pos
        p f.gets
      end

      File.delete(path)
    RUBY

    _(result).must_answer <<~'OUT'
      "alpha\n"
      6
      "beta\n"
      11
      "alpha\n"
      "beta\ngamma\ndelta\n"
      "beta\n"
      "alpha\n"
      "delta\n"
      "a"
      108
      "pha\n"
      6
      88
      "beta\n"
      false
      false
      true
      23
      6
      4
      23
      true
      11
      "gamma\n"
    OUT
  end

  it "copy_stream and rewind dispatch on the runtime class of a parameter that unions StringIO and File" do
    result = zr(<<~'RUBY')
      # IO.copy_stream / #rewind through a param that unions StringIO and File
      # dispatch on the runtime stream class (#3257). Uses temp files it creates.
      require 'stringio'

      def send_to(dst, io)
        io.rewind
        IO.copy_stream(io, dst)
      end

      src_path = "/tmp/spinel_test_copy_stream_src.txt"
      dst_path = "/tmp/spinel_test_copy_stream_dst.txt"
      io1 = StringIO.new("hello-sio ")
      io2 = File.open(src_path, "w+")
      io2.write("hello-file")
      dst = File.open(dst_path, "w")
      send_to(dst, io1)
      send_to(dst, io2)
      dst.close
      puts File.read(dst_path)
      File.delete(src_path)
      File.delete(dst_path)
    RUBY

    _(result).must_answer "hello-sio hello-file\n"
  end

  it "reading a write-only handle raises IOError before the syscall, not Errno::EBADF" do
    result = zr(<<~'RUBY')
      # Reading a write-only IO (or writing a read-only one) is an IOError ("not
      # opened for reading"/"not opened for writing") -- ruby checks the mode
      # before touching the fd. zr lets the syscall fail and raises
      # Errno::EBADF. (Found by the 2026-08-24 probe sweep.)
      begin
        File.open("/dev/null", "w") { |f| f.read }
      rescue IOError => e
        puts "#{e.class}: #{e.message}"
      end
      begin
        File.open("/dev/null", "r") { |f| f.write("x") }
      rescue IOError => e
        puts "#{e.class}: #{e.message}"
      end
    RUBY

    _(result).must_answer "IOError: not opened for reading\nIOError: not opened for writing\n"
  end

  it "IO.pipe answers a reader and a writer, and the reader reads what the writer wrote" do
    result = zr(<<~'RUBY')
      r, w = IO.pipe
      puts r.class
      puts w.class
      w.write("hello")
      w.close
      puts r.read
    RUBY

    _(result).must_answer <<~'OUT'
      IO
      IO
      hello
    OUT
  end

  it "popen replaces the child's stdin, stdout or both, and the handle knows its pid and reaps it into $?" do
    result = zr(<<~'RUBY')
      # IO.popen -- a subprocess with a pipe replacing its stdout ("r"), its stdin
      # ("w"), or both ("r+"), the handle knowing its child: #pid answers it and
      # #close reaps it into $?.
      IO.popen("echo hello") { |io| puts io.read.strip }
      p $?.exitstatus

      io = IO.popen(["printf", "a b c"])
      p io.read
      p io.pid.positive?
      p io.closed?
      io.close
      p $?.success?

      # A shell string with a metacharacter runs through the shell.
      IO.popen("echo one && echo two") { |io| p io.read.split }

      # Write mode: the child's stdin is ours; the close delivers its EOF.
      IO.popen("wc -c > /dev/null", "w") { |io| io.write("12345") }
      p $?.exitstatus

      # Duplex: one handle, both directions. close_write hands the child EOF while
      # its answer stays readable.
      IO.popen("cat", "r+") do |io|
        io.write("round trip\n")
        io.close_write
        p io.read
      end

      # A leading env hash reaches the child.
      IO.popen({ "POPEN_PROBE" => "seen" }, "echo $POPEN_PROBE") { |io| puts io.read }

      # The block's value is the call's answer.
      p(IO.popen("true") { |io| io.pid.is_a?(Integer) })
    RUBY

    _(result).must_answer <<~'OUT'
      hello
      0
      "a b c"
      true
      false
      true
      ["one", "two"]
      0
      "round trip\n"
      seen
      true
    OUT
  end

  it "STDOUT answers tty?, chains <<, and reports its fileno" do
    result = zr(<<~'RUBY')
      # IO#tty?/#isatty, IO#<< (chainable), and IO#fileno on STDOUT/STDERR. The 12-gem
      # "unsupported call: tty?/<</winsize on STDOUT/STDERR" cluster (#1605): STDOUT
      # types as a concrete IO, so these IO methods must be modelled rather than
      # rejected. The test harness redirects stdout/stderr, so tty? is false.
      puts STDOUT.tty?
      puts STDERR.isatty
      STDOUT << "a" << "b" << "c\n"
      puts STDOUT.fileno
      puts STDERR.fileno
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      abc
      1
      2
    OUT
  end

  it "ioctl fills the buffer its command names" do
    result = zr(<<~'RUBY')
      # `IO#ioctl`. rb_io_ctl reads its argument as setup_narg does: nil and false
      # stand for 0, true for 1, an Integer for itself, and a String is the buffer
      # the command fills -- grown to the length the command names (the IOCPARM
      # bits of the command itself) with one byte after it, so a command that wrote
      # too far is caught rather than trusted.
      #
      # FIONREAD asks how many bytes wait in a pipe, which needs no terminal, so
      # the whole path is observable here: the buffer grows, the count reads back,
      # and the sentinel byte is cleared to NUL on the way out.
      FIONREAD = 0x4004667f

      def answer
        "#{yield.inspect}"
      rescue StandardError => e
        "#{e.class}: #{e.message}"
      end

      r, w = IO.pipe
      w.write("hello")
      w.flush

      # A buffer of exactly the right size, and the count it comes back with.
      sized = "\0" * 4
      puts answer { [r.ioctl(FIONREAD, sized), sized.unpack1("l")] }

      # An empty String grows to the length the command names, plus the sentinel.
      empty = +""
      puts answer { [r.ioctl(FIONREAD, empty), empty.bytesize, empty.unpack1("l")] }

      # One byte is short as well, and grows the same way.
      short = +"\0"
      puts answer { [r.ioctl(FIONREAD, short), short.bytesize, short.unpack1("l")] }

      # A frozen String is no buffer to fill.
      puts answer { r.ioctl(FIONREAD, "".freeze) }

      # Without a buffer the command has nowhere to write, which the kernel says.
      puts answer { r.ioctl(FIONREAD, 0) }
      puts answer { r.ioctl(FIONREAD, nil) }

      r.close
      w.close

      # A closed stream refuses before the call.
      puts answer { r.ioctl(FIONREAD, +"\0" * 4) }

    RUBY

    _(result).must_answer <<~'OUT'
      [0, 5]
      [0, 5, 5]
      [0, 5, 5]
      FrozenError: can't modify frozen String: ""
      Errno::EFAULT: Bad address
      Errno::EFAULT: Bad address
      IOError: closed stream
    OUT
  end

  it "kernel dir" do
    result = zr(<<~'RUBY')
      # Issue #878: Kernel#__dir__ returns the dirname of the source
      # file at compile time. The parser emits SOURCE_FILE <path> near
      # the AST head so the codegen can compute dirname without needing
      # the source to reference __FILE__.
      #
      # `caller` is intentionally NOT supported -- it would require per-
      # call frame tracking that slows the dispatch hot path.
      puts __dir__.is_a?(String)
      puts __dir__.length > 0
    RUBY

    _(result).must_answer "true\ntrue\n"
  end

  it "kernel puts override takes effect" do
    result = zr(<<~'RUBY')
      # A user `def puts` on `Kernel` or `Object` answers every receiver-less
      # `puts` in the program.
      #
      # `puts` is the one Kernel primitive with a direct fold at the call site,
      # and the fold did not ask whether the program had redefined it -- so the
      # override was registered, reachable through `send` and from inside a
      # block, and skipped by every plain `puts` line. Wrong output, clean exit.

      module Kernel
        def puts(*a)
          $stdout.write("K:" + a.join(",") + "\n")
        end
      end

      puts "a", "b"
      send(:puts, "c")
      [1].each { |x| puts x }

      # A class of its own still wins over the universal, the way ruby's lookup
      # orders them.
      class Loud
        def puts(*a)
          $stdout.write("L:" + a.join(",") + "\n")
        end

        def go = puts("inside")
      end
      Loud.new.go
    RUBY

    _(result).must_answer <<~'OUT'
      K:a,b
      K:c
      K:1
      L:inside
    OUT
  end

  it "moved stderr takes warnings and the report" do
    result = zr(<<~'RUBY')
      # Once $stderr names another stream, warnings, abort's message and the
      # report of an uncaught exception all go there.
      $stderr = $stdout
      warn "w"
      $stderr.puts "direct"
      begin
        abort "a"
      rescue SystemExit
      end
      raise "boom"

    RUBY

    _(result).must_answer <<~'OUT', status: 1
      w
      direct
      a
      core/io/io_test.rb:10:in '<main>': boom (RuntimeError)
    OUT
  end

  it "multi assign targets follow the textual block local rule" do
    result = zr(<<~'RUBY')
      # A multi-assign target is a plain outer assignment for Ruby's textual
      # block-local rule, positioned at its own statement. Before: `level` here
      # counted its RE-assignment inside the loop as the scope's first, demoting
      # it to loop-block-local and refusing the nested `find` (minitest's
      # find_minimal_combination). After a block, the same shape stays untouched
      # by the block's own write -- both directions oracle-verified.
      def f
        level, n = 1, 1
        loop do
          r = [1, 2, 3].find { |a| a > level }
          level += 1
          break r if level > 2
        end + n
      end
      p f

      pr = proc { x = 99 }
      x, y = 5, 6
      pr.call
      p x
      p y
    RUBY

    _(result).must_answer <<~'OUT'
      4
      5
      6
    OUT
  end

  it "next value select" do
    result = zr(<<~'RUBY')
      # `next <cond>` inside a select/reject block decides the element's inclusion,
      # instead of being dropped as a bare skip.
      p [1, 2, 3, 4].select { |x| next true if x == 2; x > 2 }          # [2, 3, 4]
      p [1, 2, 3, 4].reject { |x| next true if x == 1; x.even? }        # [3]
      p [1, 2, 3].select { |x| next false if x == 2; true }             # [1, 3]
      p ["a", "bb", "ccc"].select { |s| next false if s == "bb"; s.length >= 1 } # ["a", "ccc"]

      # An int- or float-valued block is truthy unless it is nil -- 0 / 0.0 select.
      p [1, 2, 3, 4].select { |x| x % 2 }                               # [1, 2, 3, 4]
      p [1, 2, 3, 4].reject { |x| x % 2 }                               # []
      p [1, 2, 3].select { |x| next 0 if x == 2; x }                    # [1, 2, 3]
      p [1, 2, 3, 4].select { |x| (x % 2).to_f }                        # [1, 2, 3, 4]

      # Plain select/reject (no next) keep their behavior.
      p [1, 2, 3, 4].select { |x| x > 2 }                               # [3, 4]
      p [1, 2, 3, 4].reject(&:even?)                                     # [1, 3]
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 3, 4]
      [3]
      [1, 3]
      ["a", "ccc"]
      [1, 2, 3, 4]
      []
      [1, 2, 3]
      [1, 2, 3, 4]
      [3, 4]
      [1, 3]
    OUT
  end

  it "pipe read to eof does not seek" do
    result = zr(<<~'RUBY')
      # `read` (to EOF) and `eof?` on a PIPE must not seek: with the write end
      # closed, ruby answers "" and true. zr's eof probe seeks and raises
      # Errno::ESPIPE ("Illegal seek"). (Found by the 2026-08-24 probe sweep.)
      r, w = IO.pipe
      w.close
      p r.read
      p r.eof?
      r.close
    RUBY

    _(result).must_answer <<~'OUT'
      ""
      true
    OUT
  end

  it "poly io handle methods" do
    result = zr(<<~'RUBY')
      # An IO handle read back out of a poly container.
      #
      # A stream in a container is boxed, so the receiver's type is only known at run
      # time. The poly arm unboxes and dispatches, but its name list covered the
      # reader side only -- so `[$stdout, $stderr][0].puts "x"` answered
      # `NoMethodError: undefined method 'puts' for an instance of IO`, naming
      # exactly what the receiver was.
      #
      # Names with a non-IO meaning on a poly value stay off that list: `size`, `<<`
      # and `each` mean something else on an array and have their own arms.

      box = [$stdout, $stderr]

      box[0].puts "one"
      box[0].print "two\n"
      box[0].putc 51
      box[0].puts
      box[0].puts "four", "five"
      box[0].write "six\n"
      box[0].flush

      p box[0].closed?
      p box.length

      # a pipe pair through the same container shape: the write end takes the output
      # family, the read end the readers
      r, w = IO.pipe
      pair = [r, w]
      pair[1].puts "piped"
      pair[1].print "printed\n"
      pair[1].close
      p pair[0].read
      pair[0].close
      p pair[0].closed?

      # a handle held in a hash value
      h = { "out" => $stdout }
      h["out"].puts "through a hash"

      # a nil-able slot: the union is poly, and a real handle still dispatches
      def maybe(f)
        f ? $stdout : nil
      end

      s = maybe(true)
      s.puts "through a union"
    RUBY

    _(result).must_answer <<~'OUT'
      one
      two
      3
      four
      five
      six
      false
      2
      "piped\nprinted\n"
      true
      through a hash
      through a union
    OUT
  end

  it "print field and record separators" do
    result = zr(<<~'RUBY')
      $, = "-"
      $\ = "!"
      print "a", "b"
      $, = nil
      $\ = nil
      puts ""
    RUBY

    _(result).must_answer "a-b!\n"
  end

  it "puts class value" do
    result = zr(<<~'RUBY')
      # `puts` on a value-type sp_Class (from `obj.class`) should render
      # the class name, not `printf("%lld", (long long)struct_value)`.
      class Counter
        def initialize; @count = 0; end
        def increment; self; end
      end

      c = Counter.new
      puts c.increment.class
      puts Counter
    RUBY

    _(result).must_answer "Counter\nCounter\n"
  end

  it "puts compound arg" do
    result = zr(<<~'RUBY')
      # STDOUT/STDERR (constants) .puts/.print with a COMPOUND-expression argument --
      # a call that lowers to a C compound literal / statement-expression
      # (format/sprintf/Array#join, array literals). Previously the constant
      # .puts/.print codegen rendered the argument directly into the g_pre preamble
      # buffer, so the argument's own setup lines (e.g. sp_str_format_polyarr temps)
      # were spliced into the middle of the half-built sp_File_write(...) call and
      # the generated C failed to compile ("expected expression").

      STDOUT.puts(format("x=%d", 5))
      STDOUT.puts(sprintf("y=%d", 7))
      STDOUT.puts([1, 2, 3].join(","))
      STDOUT.print(format("p=%d", 9))
      STDOUT.print("\n")
      STDOUT.puts format("noparen=%d", 11)   # no parens -- same lowering
      STDOUT.puts([10, 20].map { |x| x * 2 }.join("-"))

      # Regression guards: the forms that already worked must keep working.
      m = format("bound=%d", 42)
      STDOUT.puts(m)                          # bind to a local first
      STDOUT.puts("a".upcase)                 # inline call that is NOT a compound expr
      STDOUT.puts("z=%d" % 3)                 # `%` instead of format(...)

      # puts adds a newline after EACH argument, and does NOT double a newline when
      # the argument already ends in one.
      STDOUT.puts("a", "b", "c")              # a\nb\nc\n
      STDOUT.puts("already\n")                # already\n (no extra blank line)
      STDOUT.puts(format("m=%d", 1), format("n=%d", 2))
      STDOUT.puts                             # a single blank line
      STDOUT.puts("abc"[10])                  # nil (out-of-range index) -> blank line
      STDOUT.print                            # print with no args -> nothing (no empty ({}) )
      STDOUT.puts("dprint-guard")

      # STDERR goes to stderr (asserted against the .err.expected sidecar).
      STDERR.puts(format("err=%d", 5))
      STDERR.print(sprintf("errp=%d\n", 6))
      STDERR.puts("e1", "e2")                 # e1\ne2\n
      STDERR.puts("edone\n")                  # edone\n (no double newline)
    RUBY

    _(result).must_answer <<~'OUT', stderr: "err=5\nerrp=6\ne1\ne2\nedone\n"
      x=5
      y=7
      1,2,3
      p=9
      noparen=11
      20-40
      bound=42
      A
      z=3
      a
      b
      c
      already
      m=1
      n=2


      dprint-guard
    OUT
  end

  it "puts in case value arm" do
    result = zr(<<~'RUBY')
      class Renderer
        attr_accessor :skip_background_fill

        def initialize
          @skip_background_fill = false
        end
      end

      class Window
        def initialize
          @renderer = Renderer.new
          @show_debug = false
        end

        def button_down(id)
          case id
          when 1
            @show_debug = !@show_debug
          when 2
            @renderer.skip_background_fill = !@renderer.skip_background_fill
            puts "Background fill: #{@renderer.skip_background_fill ? 'OFF' : 'ON'}"
          end
        end
      end

      w = Window.new
      w.button_down(2)
      w.button_down(1)
      w.button_down(2)
      w.button_down(3)
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      Background fill: OFF
      Background fill: ON
      done
    OUT
  end

  it "puts nil" do
    result = zr(<<~'RUBY')
      # `puts nil` (a nil literal) and `puts nil.itself` print a single empty
      # line, not `0`. (A nil-*typed* method/ivar that carries a real value is
      # deliberately left on the value path, so this gates on the syntactic
      # form, not the inferred type.)
      puts nil
      puts nil.itself
      puts "end"
    RUBY

    _(result).must_answer <<~'OUT'


      end
    OUT
  end

  it "puts object to s poly" do
    result = zr(<<~'RUBY')
      # puts/print/interpolation of an object whose to_s unions a String with
      # another branch type (returns a boxed sp_RbVal) must route through
      # sp_poly_to_s instead of a pointer cast (#3266).
      class Crash
        def initialize(flag) = @flag = flag
        def to_s = @flag ? "ok" : nil
      end

      puts Crash.new(true)
      print Crash.new(true), "\n"
      x = Crash.new(true)
      puts "val=#{x}"
    RUBY

    _(result).must_answer <<~'OUT'
      ok
      ok
      val=ok
    OUT
  end

  it "ruby version build constants and file separators" do
    result = zr(<<~'RUBY')
      # Stable values plus a self-consistency check that RUBY_DESCRIPTION is
      # composed from its parts exactly as CRuby's version.c does (portable
      # across build hosts; RUBY_PLATFORM is derived from the build target).

      puts RUBY_VERSION
      puts RUBY_ENGINE
      puts RUBY_PATCHLEVEL
      puts File::SEPARATOR
      p File::ALT_SEPARATOR
      short = RUBY_REVISION[0, 10]
      composed = "ruby #{RUBY_VERSION} (#{RUBY_RELEASE_DATE} revision #{short}) +PRISM [#{RUBY_PLATFORM}]"
      puts RUBY_DESCRIPTION == composed
    RUBY

    _(result).must_answer <<~'OUT'
      4.0.6
      ruby
      0
      /
      nil
      true
    OUT
  end

  it "select on a subclass with its own send" do
    result = zr(<<~'RUBY')
      # IO.select asks each stream whether it holds buffered bytes, through
      # Kernel#send as CRuby's C would. A stream whose class defines its own
      # `send`, as BasicSocket does for send(2), must not take that call:
      # a Socket in IO.select raised "wrong number of arguments".
      class Channel < IO
        def send(message, flags)
          raise "Channel#send(#{message.inspect}, #{flags})"
        end
      end

      reader, writer = Channel.pipe
      writer.write("x")
      ready = IO.select([reader], [writer], nil, 1)
      p ready.map { |list| list.map(&:class) }
      p reader.read_nonblock(1)
      [reader, writer].each(&:close)

    RUBY

    _(result).must_answer <<~'OUT'
      [[Channel], [Channel], []]
      "x"
    OUT
  end

  it "select waits on every list while threads run" do
    result = zr(<<~'RUBY')
      # IO.select parks the thread that asks, so a thread that writes later
      # still runs; a reader with bytes in its buffer is ready at once.
      r, w = IO.pipe
      writer = Thread.new { sleep 0.05; w.write "ab\ncd\n" }
      ready = IO.select([r], nil, nil, 5)
      p ready.map(&:size), ready[0][0].equal?(r)
      writer.join
      p r.gets
      p IO.select([r], [w], nil, 0).map(&:size)
      p IO.select([r], nil, nil, 0)&.first&.size
      r2, w2 = IO.pipe
      p IO.select([r2], nil, nil, 0.05)
      t = Thread.new { IO.select([r2]); :woke }
      sleep 0.02
      w2.write "x"
      p t.value

    RUBY

    _(result).must_answer <<~'OUT'
      [1, 0, 0]
      true
      "ab\n"
      [1, 1, 0]
      1
      nil
      :woke
    OUT
  end

  it "self referential collections print recursion markers" do
    result = zr(<<~'RUBY')
      # Pre-15.2 both of these self-deadlocked on the collection's own
      # non-reentrant payload Mutex.
      #
      # The two rings the program prints are the two it leaves alive.
      # At exit: cycle leak: 2 objects (Array x1, Hash x1)

      a = [1, 2]
      a << a
      puts a

      h = { k: 1 }
      h[:me] = h
      puts h
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      [...]
      {k: 1, me: {...}}
    OUT
  end

  it "self test block in a required file" do
    result = zr(<<~'RUBY', files: beside("self_test_block/lib.rb"))
      # `if __FILE__ == $0` -- the self-test block every second library file ends
      # with. In a file something else REQUIRED it is false whatever `$0` holds: the
      # entry point is, by definition, a different file. The definitions it guards
      # must therefore not register, which is what lets a library that ships its own
      # test harness compile at all.
      require_relative "self_test_block/lib"

      p Memcache.new.get
      p defined?(TestConnection)
    RUBY

    _(result).must_answer <<~'OUT'
      "get a\r\n"
      nil
    OUT
  end

  it "source file" do
    result = zr(<<~'RUBY')
      # SourceFileNode -- the `__FILE__` keyword.
      #
      # Spinel inlines `require`/`require_relative` at parse time, so call
      # sites in different source files are not distinguished. `__FILE__`
      # always returns the toplevel script path passed to spinel_parse,
      # matching CRuby's behavior for top-level uses.
      #
      # This test exercises __FILE__ end-to-end: it must (a) emit the path,
      # (b) flow as `string` through type inference (so dispatch picks the
      # string-method arms), (c) interoperate with literals (concat / compare
      # / interpolate), and (d) round-trip through a typed-String parameter
      # at a method call site.

      # Basic emission.
      puts __FILE__

      # String#length returns an Integer -> dispatch hit the string arm.
      puts __FILE__.length > 0

      # Concat with literal -> __FILE__ is a `string`, not poly/object.
      puts "[" + __FILE__ + "]"

      # Interpolation works (path appears verbatim).
      puts "got: #{__FILE__}"

      # Two reads compare equal -- same toplevel path resolves identically.
      puts __FILE__ == __FILE__

      # String predicates dispatch via the string arm.
      puts __FILE__.end_with?(".rb")
      puts __FILE__.include?("io_test")

      # Round-trip through a typed-String parameter at a method call site.
      def show(s)
        puts "param: " + s
      end
      show(__FILE__)
    RUBY

    _(result).must_answer <<~'OUT'
      core/io/io_test.rb
      true
      [core/io/io_test.rb]
      got: core/io/io_test.rb
      true
      true
      true
      param: core/io/io_test.rb
    OUT
  end

  it "stderr reassigned to stdout" do
    result = zr(<<~'RUBY')
      # `$stderr = $stdout` has to be honoured by reads of $stderr.
      #
      # A program that reassigns one of the standard streams already gets a real
      # global for it (gv_stderr, NULL until the assignment runs), and the assignment
      # was emitted correctly. Only the READ ignored it, so the write still went to
      # the real stderr and `$stderr == $stdout` answered false -- the two halves of
      # the report.
      #
      # A program that never reassigns has no such global and emits exactly as
      # before, which is what the second half of this test pins.

      $stderr = $stdout
      p($stderr == $stdout)
      $stderr.puts "err"
      puts "out"
      $stderr.write("w\n")
      $stderr.print("p\n")
      $stderr.flush

      # every one of those lines is on stdout now, so a stderr-only reader sees
      # nothing; the test harness merges the two, so the order above is the check
    RUBY

    _(result).must_answer <<~'OUT'
      true
      err
      out
      w
      p
    OUT
  end

  it "stdin io" do
    result = zr(<<~'RUBY', stdin: "hello\nworld\n")

      # $stdin / STDIN are IO handles over the C stdin stream: gets (nil at EOF),
      # read, each_line, eof?, tty? route through the ordinary TY_IO surface.
      line = $stdin.gets
      p line
      p STDIN.gets
      p $stdin.gets            # EOF -> nil
      p $stdin.eof?
      p $stdin.tty?            # piped in the test harness -> false
    RUBY

    _(result).must_answer <<~'OUT'
      "hello\n"
      "world\n"
      nil
      true
      false
    OUT
  end

  it "stdout is discarded by exit bang" do
    result = zr(<<~'RUBY')
      # `exit!` is CRuby's `_exit(2)`: no `at_exit` handler, and whatever stdio
      # still holds is DISCARDED. So this program prints NOTHING, where the same
      # text through `exit` prints all 300 bytes. A native `exit` runs the
      # runtime's own cleanup, which flushes, so the buffer has to be stepped
      # around rather than asked politely.
      at_exit { $stderr.print "[must not run]" }
      print "A" * 300
      exit!(0)
    RUBY

    _(result).must_answer ""
  end

  it "stdout survives exit" do
    result = zr(<<~'RUBY')
      # `exit` raises SystemExit, so the buffer is written on the way out and the
      # `at_exit` handler runs first -- the same return-to-C-`main` path as
      # falling off the end, reached through the exception.
      at_exit { $stderr.print "[at_exit ran]" }
      print "A" * 300
      exit 0
    RUBY

    _(result).must_answer <<~'OUT'.chomp, stderr: "[at_exit ran]"
      AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    OUT
  end

  it "thread file gets" do
    result = zr(<<~'RUBY')
      File.write("tfg.tmp", "line1\nline2\n")
      f = File.open("tfg.tmp")
      t = Thread.new do
        a = f.gets
        b = f.gets
        [a, b]
      end
      p t.value
      f.close
      File.delete("tfg.tmp")
    RUBY

    _(result).must_answer "[\"line1\\n\", \"line2\\n\"]\n"
  end

  it "user defined puts wins over the kernel function" do
    result = zr(<<~'RUBY')
      # A user-defined sibling `puts` WINS over the Kernel function (real Ruby's
      # rule).

      class Logger
        def puts(msg)
          $stdout_lines = 1
          "logged: #{msg}"
        end
        def run
          puts("hi")
        end
      end

      v = Logger.new.run
      p v
    RUBY

    _(result).must_answer "\"logged: hi\"\n"
  end

  it "warn after stderr reopen" do
    result = zr(<<~'RUBY')
      $stderr.reopen(IO::NULL)
      warn "w1"
      puts "survived"
    RUBY

    _(result).must_answer "survived\n"
  end

  it "warn and stderr writes land on stderr not stdout" do
    result = zr(<<~'RUBY')
      # `warn`, `$stderr.puts`, and `STDERR.write` all go to the error stream;
      # `$stdout.puts` stays on stdout. The two streams are asserted separately,
      # so a leak in either direction fails the test.

      $stdout.puts "out1"
      warn "w1"
      $stderr.puts "err1"
      STDERR.write "err2\n"
      $stdout.puts "out2"
      warn "w2", "w3"
    RUBY

    _(result).must_answer "out1\nout2\n", stderr: "w1\nerr1\nerr2\nw2\nw3\n"
  end

  it "IO#advise names an advice it does not know" do
    result = zr(<<~'RUBY')
      File.open(__FILE__) do |f|
        begin
          f.advise(:bogus)
        rescue NotImplementedError => e
          p [e.class, e.message]
        end
        p f.advise(:sequential)
        p f.advise(:normal, 0, 0)
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [NotImplementedError, "Unsupported advice: :bogus"]
      nil
      nil
    OUT
  end
end
