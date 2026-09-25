# frozen_string_literal: true

require "spec_helper"

describe "IO::console: reading and writing" do
  it "closed io refuses every console row" do
    result = zr(<<~'RUBY')
      # Every `io/console` row runs `GetOpenFile` first, so a CLOSED stream is
      # `IOError: closed stream` and no syscall happens.
      #
      # `#fileno` answered 0 for a closed handle, so the whole family ran its
      # ioctls and termios calls against descriptor 0 -- STDIN. A closed IO's
      # `raw!` put the user's own terminal into raw mode and reported ENOTTY.

      require "io/console"

      r, w = IO.pipe
      r.close
      w.close

      %i[fileno to_i tty? isatty winsize echo? ttyname iflush oflush cursor
         console_mode].each do |name|
        begin
          r.public_send(name)
          puts "#{name} answered"
        rescue IOError => e
          puts "#{name} #{e.class}: #{e.message}"
        end
      end

      begin
        r.raw { 1 }
      rescue IOError => e
        puts "raw #{e.class}: #{e.message}"
      end

      begin
        r.winsize = [24, 80]
      rescue IOError => e
        puts "winsize= #{e.class}: #{e.message}"
      end

      # `closed?` itself still answers, as it must.
      p r.closed?
    RUBY

    _(result).must_answer <<~'OUT'
      fileno IOError: closed stream
      to_i IOError: closed stream
      tty? IOError: closed stream
      isatty IOError: closed stream
      winsize IOError: closed stream
      echo? IOError: closed stream
      ttyname IOError: closed stream
      iflush IOError: closed stream
      oflush IOError: closed stream
      cursor IOError: closed stream
      console_mode IOError: closed stream
      raw IOError: closed stream
      winsize= IOError: closed stream
      true
    OUT
  end

  it "console row survives an earlier io call" do
    result = zr(<<~'RUBY')
      # The `io/console` rows are gated on the require, and touching an IO BEFORE
      # that require must not close the gate for the rest of the program.
      #
      # Here `r.fileno` runs before the require. After the require, `echo?`,
      # `raw` and `getch` must work, and `respond_to?` must agree with them.

      r, w = IO.pipe
      r.fileno # a call on the IO before the require

      require "io/console"

      p r.respond_to?(:echo?)
      p r.respond_to?(:raw)
      p IO.respond_to?(:console)

      # A pipe is not a terminal, so the ANSWER is a syscall error -- which is the
      # point: the row is reached at all.
      begin
        r.echo?
      rescue SystemCallError => e
        p e.class
      end

      begin
        r.raw { 1 }
      rescue SystemCallError => e
        p e.class
      end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      Errno::ENOTTY
      Errno::ENOTTY
    OUT
  end

  it "terminal modes, echo control and the cursor escapes answer, and a pipe raises ENOTTY" do
    result = zr(<<~'RUBY', path: "io_console.rb")
      # `io/console` -- terminal modes, echo control, and the cursor escapes. CRuby
      # ships it as a require-gated extension; zr's rows hang unconditionally off
      # the IO table, so the require is ceremony (`docs/EXTENSIONS.md`).
      #
      # Nothing here is a terminal, which is the only path a golden can assert
      # without a pty. The streams are a pipe and a regular file rather than STDIN:
      # the harness gives STDIN /dev/null, and tcgetattr on a character device
      # answers ENODEV on some platforms and ENOTTY on others.
      require "io/console"

      p STDIN.tty?
      p IO.console
      p STDIN.ttyname

      def refusal(label)
        yield
        "#{label}: no error"
      rescue SystemCallError, NotImplementedError => e
        "#{label}: #{e.class}: #{e.message}"
      end

      # A stream with no name reports none; the direct methods on a named one name
      # it, and the scoped forms never do -- CRuby reaches that failure through a
      # helper with no name to report.
      r, w = IO.pipe
      puts refusal("pipe raw!") { r.raw! }
      puts refusal("pipe raw") { r.raw {} }
      puts refusal("pipe winsize") { r.winsize }

      f = File.open("io_console_probe.txt", "w+")
      puts refusal("file raw!") { f.raw! }
      puts refusal("file raw") { f.raw {} }
      puts refusal("file cooked!") { f.cooked! }
      puts refusal("file cooked") { f.cooked {} }
      puts refusal("file echo?") { f.echo? }
      puts refusal("file echo=") { f.echo = false }
      puts refusal("file noecho") { f.noecho {} }
      puts refusal("file getch") { f.getch }
      puts refusal("file getpass") { f.getpass }
      puts refusal("file iflush") { f.iflush }
      puts refusal("file oflush") { f.oflush }
      puts refusal("file ioflush") { f.ioflush }
      puts refusal("file winsize") { f.winsize }
      puts refusal("file winsize=") { f.winsize = [10, 20] }
      puts refusal("file console_mode") { f.console_mode }
      # Windows-only in CRuby as well -- the message is its own.
      puts refusal("file pressed?") { f.pressed? }
      puts refusal("file check_winsize_changed") { f.check_winsize_changed }
      p f.ttyname
      f.close
      File.unlink("io_console_probe.txt")

      # The cursor and erase escapes only WRITE, so they work on any stream -- which
      # is why redirecting a program's output captures them rather than failing.
      w.goto(2, 3)
      w.goto_column(5)
      w.cursor_up(1)
      w.cursor_down(2)
      w.cursor_left(3)
      w.cursor_right(4)
      w.scroll_forward(5)
      w.scroll_backward(6)
      w.erase_line(0)
      w.erase_screen(2)
      w.clear_screen
      w.beep
      w.close
      p r.read
      r.close
    RUBY

    _(result).must_answer <<~'OUT'
      false
      nil
      nil
      pipe raw!: Errno::ENOTTY: Inappropriate ioctl for device
      pipe raw: Errno::ENOTTY: Inappropriate ioctl for device
      pipe winsize: Errno::ENOTTY: Inappropriate ioctl for device
      file raw!: Errno::ENOTTY: Inappropriate ioctl for device - io_console_probe.txt
      file raw: Errno::ENOTTY: Inappropriate ioctl for device
      file cooked!: Errno::ENOTTY: Inappropriate ioctl for device - io_console_probe.txt
      file cooked: Errno::ENOTTY: Inappropriate ioctl for device
      file echo?: Errno::ENOTTY: Inappropriate ioctl for device - io_console_probe.txt
      file echo=: Errno::ENOTTY: Inappropriate ioctl for device - io_console_probe.txt
      file noecho: Errno::ENOTTY: Inappropriate ioctl for device
      file getch: Errno::ENOTTY: Inappropriate ioctl for device
      file getpass: Errno::ENOTTY: Inappropriate ioctl for device
      file iflush: Errno::ENOTTY: Inappropriate ioctl for device - io_console_probe.txt
      file oflush: Errno::ENOTTY: Inappropriate ioctl for device - io_console_probe.txt
      file ioflush: Errno::ENOTTY: Inappropriate ioctl for device - io_console_probe.txt
      file winsize: Errno::ENOTTY: Inappropriate ioctl for device - io_console_probe.txt
      file winsize=: Errno::ENOTTY: Inappropriate ioctl for device - io_console_probe.txt
      file console_mode: Errno::ENOTTY: Inappropriate ioctl for device - io_console_probe.txt
      file pressed?: NotImplementedError: pressed?() function is unimplemented on this machine
      file check_winsize_changed: NotImplementedError: check_winsize_changed() function is unimplemented on this machine
      nil
      "\e[3;4H\e[6G\e[1A\e[2B\e[3D\e[4C\e[5S\e[6T\e[0K\e[2J\e[2J\e[1;1H\a"
    OUT
  end

  it "raw! with a non-numeric min:, an unknown keyword or a stray positional raises instead of ending the process" do
    result = zr(<<~'RUBY')
      # The `io/console` argument guards, all of them io-console's own.
      #
      # The worst of these was `min:`: a non-numeric went through an "unchecked"
      # float conversion that crashed, so `io.raw!(min: "x")` aborted the whole
      # process where ruby raises. An unknown keyword was dropped silently, and a
      # stray positional argument sent `getch` into a blocking read.

      require "io/console"

      r, w = IO.pipe

      def refusal
        yield
        "no refusal"
      rescue StandardError => e
        "#{e.class}: #{e.message}"
      end

      # Keywords: only min:, time: and intr:, and intr: is true or false.
      puts refusal { r.raw(nope: 1) { 1 } }
      puts refusal { r.raw!(min: "x") }
      puts refusal { r.raw!(time: "x") }
      puts refusal { r.raw!(intr: 1) }

      # No positional argument at all.
      puts refusal { r.getch(:nope) }
      puts refusal { r.raw!(1) }

      # `winsize=` takes 2 or 4 elements, counted after `Kernel#Array`.
      puts refusal { r.winsize = [1] }
      puts refusal { r.winsize = "x" }
      puts refusal { r.winsize = [1, 2, 3] }

      # The erase modes are bounded, and nil means 0.
      puts refusal { w.erase_line(9) }
      puts refusal { w.erase_screen(4) }
      puts refusal { w.erase_line("x") }

      # `cursor=` wants a 2D coordinate.
      puts refusal { w.cursor = [1] }
      puts refusal { w.cursor = 5 }

      # A block-taking row with no block.
      puts refusal { r.noecho }
      puts refusal { r.raw }

      # `IO.console`'s argument is a Symbol.
      puts refusal { IO.console("close") }

      r.close
      w.close
    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError: unknown keyword: :nope
      TypeError: no implicit conversion of String into Integer
      TypeError: no implicit conversion of String into Integer
      ArgumentError: true or false expected as intr: 1
      ArgumentError: wrong number of arguments (given 1, expected 0)
      ArgumentError: wrong number of arguments (given 1, expected 0)
      ArgumentError: wrong number of arguments (given 1, expected 2 or 4)
      ArgumentError: wrong number of arguments (given 1, expected 2 or 4)
      ArgumentError: wrong number of arguments (given 3, expected 2 or 4)
      ArgumentError: wrong line erase mode: 9
      ArgumentError: wrong screen erase mode: 4
      ArgumentError: wrong line erase mode: x
      ArgumentError: expected 2D coordinate
      TypeError: no implicit conversion of Integer into Array
      Errno::ENOTTY: Inappropriate ioctl for device
      Errno::ENOTTY: Inappropriate ioctl for device
      TypeError: wrong argument type String (expected Symbol)
    OUT
  end

  it "the io/console methods answer respond_to?, not only a call" do
    result = zr(<<~'RUBY')
      # io/console's methods answer to reflection, not just to calls -- webrick and
      # friends feature-test with `respond_to?(:raw)` before touching the terminal.
      require "io/console"
      p STDIN.respond_to?(:raw)
    RUBY

    _(result).must_answer "true\n"
  end

  it "io/console/size is its own require, and IO.console_size reads the environment" do
    result = zr(<<~'RUBY')
      # `require "io/console/size"` is its own require in ruby -- `io/console`
      # alone does NOT define `IO.console_size` -- and it was a LoadError here, so
      # irb, debug and power_assert all failed on their first line.

      p IO.respond_to?(:console_size)
      p IO.respond_to?(:default_console_size)

      require "io/console/size"

      p IO.respond_to?(:console_size)
      p IO.respond_to?(:default_console_size)

      ENV["LINES"] = "37"
      ENV["COLUMNS"] = "111"
      p IO.default_console_size

      # A blank or non-numeric value falls back, because `String#to_i.nonzero?`
      # answers nil for both.
      ENV["LINES"] = "0"
      ENV["COLUMNS"] = "nope"
      p IO.default_console_size

      ENV.delete("LINES")
      ENV.delete("COLUMNS")
      p IO.default_console_size

      # The size require pulls `io/console` in with it.
      r, w = IO.pipe
      p r.respond_to?(:echo?)
      r.close
      w.close
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      true
      true
      [37, 111]
      [25, 80]
      [25, 80]
      true
    OUT
  end

  it "a Symbol timeout, a huge read, a zero-capacity ioctl buffer and an i64 overflow all raise, not abort" do
    result = zr(<<~'RUBY')
      # Every one of these ended a zr process instead of raising.
      #
      # `io.wait(:read)` crashed: the Symbol lands in the timeout slot, which went
      # through an "unchecked" float conversion that crashes. `f.read(10**18)`
      # allocated eagerly, and an allocation failure is an ABORT, not a rescuable
      # NoMemoryError. `$stdout.ioctl(TIOCGWINSZ, "")` handed the kernel a
      # zero-capacity buffer to write eight bytes through -- heap corruption from
      # pure Ruby. `io.goto(2**63 - 1, 0)` overflowed an i64.
      #
      # None of them is exotic; each is one wrong argument away from ordinary code.

      require "io/console"
      require "io/wait"

      def refusal
        v = yield
        "no refusal: #{v.inspect}"
      rescue Exception => e
        "#{e.class}: #{e.message}"
      end

      r, w = IO.pipe

      # A timeout that is not a number.
      puts refusal { r.wait_readable("1") }
      puts refusal { w.wait_writable(:soon) }
      puts refusal { r.wait(:read, "x") }
      puts refusal { r.wait(:nope, 0.05) }
      # Arguments sort by TYPE, so both orders name the same wait.
      puts refusal { [r.wait(:read, 0.05), r.wait(0.05, :read)].inspect }
      puts refusal { IO.select([r], nil, nil, "x") }

      # A length no allocator can serve.
      f = File.open("/etc/hosts")
      puts refusal { f.read(10**18) }
      puts refusal { f.readpartial(10**18) }
      puts refusal { f.pread(10**18, 0) }
      puts refusal { f.read(-1) }
      puts refusal { f.readpartial(-1) }
      f.close

      # A coordinate the escape cannot carry.
      puts refusal { w.goto(2**63 - 1, 0) }
      puts refusal { w.goto(0, 2**40) }
      puts refusal { w.goto_column(-2**31 - 1) }
      puts refusal { w.cursor = [2**33, 0] }
      puts refusal { w.winsize = [2**33, 80] }

      # A negative coordinate is legal, and wraps the way NUM2UINT does.
      w.goto(-1, -1)
      w.goto_column(-1)
      w.cursor = [-2, -3]
      w.flush
      p r.read_nonblock(80)

      r.close
      w.close
    RUBY

    _(result).must_answer <<~'OUT'
      TypeError: can't convert String into time interval
      TypeError: can't convert Symbol into time interval
      TypeError: can't convert String into time interval
      ArgumentError: unsupported mode: nope
      no refusal: "[nil, nil]"
      TypeError: can't convert String into time interval
      NoMemoryError: failed to allocate memory
      NoMemoryError: failed to allocate memory
      NoMemoryError: failed to allocate memory
      ArgumentError: negative length -1 given
      ArgumentError: negative length -1 given
      RangeError: integer 9223372036854775807 too big to convert to 'unsigned int'
      RangeError: integer 1099511627776 too big to convert to 'unsigned int'
      RangeError: integer -2147483649 too small to convert to 'unsigned int'
      RangeError: integer 8589934592 too big to convert to 'unsigned int'
      RangeError: integer 8589934592 too big to convert to 'unsigned int'
      "\e[0;0H\e[0G\e[-1;-2H"
    OUT
  end

  it "tty? is isatty on the handle's descriptor, not a test of which standard stream it is" do
    result = zr(<<~'RUBY')
      # `IO#tty?` is `isatty(2)` on the handle's descriptor, not a test of which
      # standard stream this is.
      #
      # Reading only the three std streams called EVERY other stream a file: a pty
      # a gem opened answered false, which is exactly the word `io/console` and
      # `reline` read before they go raw.

      require "io/console"
      require "pty"

      m, s = PTY.open
      p [s.tty?, s.isatty, m.tty?]

      r, w = IO.pipe
      p [r.tty?, w.tty?]

      f = File.open("/dev/null")
      p f.tty?
      f.close

      # A closed stream refuses BEFORE the syscall (`GetOpenFile`), rather than
      # asking about descriptor 0.
      begin
        f.tty?
      rescue IOError => e
        p [e.class, e.message]
      end

      r.close
      w.close
      m.close
      s.close
    RUBY

    _(result).must_answer <<~'OUT'
      [true, true, true]
      [false, false]
      false
      [IOError, "closed stream"]
    OUT
  end

  it "tty? and winsize reach the IO arm through a handle the program carries as poly" do
    result = zr(<<~'RUBY')
      # IO#tty? and IO#winsize on a handle of no single known type.
      #
      # The handle comes out of a container, or from a parameter that gets values
      # of different types. The call must still reach the IO method, not raise
      # NoMethodError for a value that IS an IO.
      #
      # What is pinned is reachability, not any particular terminal geometry: the
      # test runs with stdout redirected to a file, so it must not depend on a tty
      # existing. winsize is only asserted to answer WITHOUT NoMethodError, because
      # a non-tty answer can differ (CRuby raises Errno::ENOTTY).
      require "io/console"

      def winsize_reachable?(stream)
        size = stream.winsize
        size.is_a?(Array)
      rescue NoMethodError
        false          # the bug: an IO that claims not to know the method
      rescue StandardError
        true           # ENOTTY and friends: reached the method, no tty to measure
      end

      File.write("/tmp/sp_ttyws.txt", "x")

      # A block parameter over a literal array: the shape that regressed.
      [STDOUT].each { |s| p s.tty?.class }

      # A file handle out of a container answers false, not NoMethodError.
      File.open("/tmp/sp_ttyws.txt") do |f|
        [f].each { |s| p s.tty? }
        handles = [f, f]
        p handles[0].tty?
        p handles.first.tty?
        [f].each { |s| p winsize_reachable?(s) }
      end

      # Two call sites that disagree degrade the parameter to poly. The IO site
      # must keep working: this is what silently broke a winsize probe that also
      # accepted IO.console's (untyped) result.
      def probe_tty(stream)
        stream.tty?
      rescue NoMethodError
        :no_method
      end

      def untyped
        IO.console
      rescue StandardError
        nil
      end

      File.open("/tmp/sp_ttyws.txt") do |f|
        p probe_tty(f)
        p winsize_reachable?(f)
      end
      other = untyped
      p probe_tty(other).equal?(:no_method) == false || other.nil?

      # isatty is the same method under its second name.
      File.open("/tmp/sp_ttyws.txt") do |f|
        [f].each { |s| p s.isatty }
      end

      File.delete("/tmp/sp_ttyws.txt")
    RUBY

    _(result).must_answer <<~'OUT'
      FalseClass
      false
      false
      false
      true
      false
      true
      true
      false
    OUT
  end

  it "require io console winsize" do
    result = zr(<<~'RUBY')
      # `require "io/console"` enables the IO console methods (IO#winsize).
      # Without the require, winsize raises NoMethodError, as in CRuby.
      #
      # Here stdout is not a tty, so IO#winsize raises Errno::ENOTTY.

      # The blank lines keep the line numbers that the expected output names.



      require "io/console"
      p STDOUT.winsize
    RUBY

    _(result).must_answer "", stderr: <<~'ERR', status: 1
      stdlib/io_console/io_test.rb:11:in 'IO#winsize': Inappropriate ioctl for device - <STDOUT> (Errno::ENOTTY)
      	from stdlib/io_console/io_test.rb:11:in '<main>'
    ERR
  end
end
