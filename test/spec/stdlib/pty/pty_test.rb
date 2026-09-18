# frozen_string_literal: true

require "spec_helper"

describe "PTY programs" do
  it "expect answers a prompt over a pty" do
    result = ze0(<<~'RUBY')
      # expect, as ruby's pty extension ships it, reads a PTY child's prompt,
      # answers it, and gives nil when the pattern never comes.
      require "pty"
      require "expect"
      PTY.spawn("sh", "-c", "printf 'name? '; read n; echo hello $n") do |r, w, pid|
        p r.expect(/name\? /, 5)
        w.puts "zeo"
        p r.expect(/hello \w+/, 5)&.first&.strip
        p r.expect(/never/, 0.2)
      end

    RUBY

    _(result).must_answer <<~'OUT'
      ["name? "]
      "zeo\r\nhello z"
      nil
    OUT
  end

  it "pty spawn" do
    result = ze0(<<~'RUBY')
      # pty -- a pseudo-terminal for a child process. A pty IS a terminal, so the
      # child's "\n" comes back "\r\n" (ONLCR) -- the observable difference from a
      # pipe, and what the golden pins.
      require "pty"

      p PTY.respond_to?(:spawn)
      p PTY.respond_to?(:getpty)
      p PTY.respond_to?(:open)
      p PTY.respond_to?(:check)

      PTY.spawn("printf 'from a pty\n'") do |r, w, pid|
        p r.gets
        p pid.positive?
        w.close
        r.close
      end

      master, slave = PTY.open
      p master.class
      p slave.class
      p slave.path.start_with?("/dev/")
      slave.close
      master.close

      r, w, pid = PTY.spawn("true")
      sleep 0.3
      begin
        PTY.check(pid, true)
        p "no raise"
      rescue PTY::ChildExited => e
        p e.class
      end
      w.close
      r.close
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      "from a pty\r\n"
      true
      IO
      File
      true
      PTY::ChildExited
    OUT
  end

  it "pty spawn and check" do
    result = ze0(<<~'RUBY')
      # `PTY` against CRuby's `ext/pty/pty.c`.
      #
      # Five of these were wrong. `PTY.spawn` handed back plain `IO`s where ruby
      # gives `File`s named for the slave device; its block form answered the
      # block's value where ruby answers nil; with no command at all it raised
      # instead of starting a login shell; a command it could not launch blamed the
      # empty string rather than "fork failed"; and `PTY.check` on a pid that is not
      # this process's child raised `Errno::ECHILD` where ruby answers nil, which is
      # the whole point of a non-blocking poll.
      #
      # `PTY::ChildExited#status` also answered nil: the raise carried only a
      # message, so the `Process::Status` never reached the exception.

      require "pty"

      m, s = PTY.open
      p [m.class.to_s, s.class.to_s]
      p [m.path.start_with?("masterpty:/dev/"), s.path.start_with?("/dev/")]
      p m.path == "masterpty:#{s.path}"
      p [m.tty?, s.tty?, m.fileno != s.fileno]
      m.close
      s.close

      # The block form of `open` closes the pair after.
      p(PTY.open { |mm, ss| [mm.class.to_s, ss.tty?] })

      r, w, pid = PTY.spawn("echo", "hi")
      p [r.class.to_s, w.class.to_s, pid.is_a?(Integer)]
      p [r.path == w.path, r.path.start_with?("/dev/"), r.pid]
      out = begin
              r.gets
            rescue Errno::EIO
              nil
            end
      p out&.chomp
      Process.wait(pid)
      r.close
      w.close

      # The block form answers nil, not the block's value.
      p(PTY.spawn("echo", "block") do |rr, _ww, cpid|
        begin
          rr.gets
        rescue Errno::EIO
        end
        Process.wait(cpid)
        :from_the_block
      end)

      # A command that cannot start blames "fork failed", whatever the errno.
      begin
        PTY.spawn("this-command-does-not-exist-zeo")
      rescue SystemCallError => e
        p [e.class.to_s, e.message]
      end

      # A pid that is not this process's child is nil, never an error.
      p PTY.check(999_999)
      p PTY.check(1)

      r2, w2, pid2 = PTY.spawn("true")
      sleep 0.3
      p PTY.check(pid2).class.to_s
      r2.close
      w2.close

      r3, w3, pid3 = PTY.spawn("true")
      sleep 0.3
      begin
        PTY.check(pid3, true)
      rescue PTY::ChildExited => e
        p [e.class.to_s, e.message.start_with?("pty - exited: "), e.status.class.to_s,
           e.status.exitstatus]
      end
      r3.close
      w3.close

      p PTY.respond_to?(:getpty)
      p PTY::ChildExited.superclass.to_s
    RUBY

    _(result).must_answer <<~'OUT'
      ["IO", "File"]
      [true, true]
      true
      [true, true, true]
      ["IO", true]
      ["File", "File", true]
      [true, true, nil]
      "hi"
      nil
      ["Errno::ENOENT", "No such file or directory - fork failed"]
      nil
      nil
      "Process::Status"
      ["PTY::ChildExited", true, "Process::Status", 0]
      true
      "RuntimeError"
    OUT
  end

  it "reads a character in raw mode" do
    result = ze0(<<~'RUBY')
      # `getch` and `getpass` over a real pty -- the end-to-end shape `irb` and
      # `reline` depend on.
      #
      # Both HUNG. The mode setter used `TCSADRAIN`, which waits for the terminal's
      # pending output to be transmitted, so the switch into raw mode blocked
      # forever whenever nobody was draining the other end. io-console uses
      # `TCSANOW` with a retry on EINTR.

      require "io/console"
      require "pty"

      m, s = PTY.open
      p s.tty?

      m.write("A")
      sleep 0.05
      p s.getch

      m.write("BC")
      sleep 0.05
      p [s.getch, s.getch]

      # The mode is restored around the scoped forms, whatever the block does.
      p s.echo?
      p(s.raw { s.echo? })
      p s.echo?
      p(s.noecho { s.echo? })
      p s.echo?

      begin
        s.raw { raise "boom" }
      rescue RuntimeError => e
        p [e.message, s.echo?]
      end

      m.write("pw\r")
      sleep 0.05
      p s.getpass("")
      p s.echo?

      # `console_mode` is a detached copy, and `#raw` on it answers a NEW mode
      # rather than destroying the saved one.
      saved = s.console_mode
      p saved.class
      p saved.raw.equal?(saved)
      p saved.raw.class
      restored = (s.console_mode = saved)
      p restored.class

      p s.winsize = [24, 80]
      p s.winsize
      p s.ttyname.frozen?

      m.close
      s.close

    RUBY

    _(result).must_answer <<~'OUT'
      true
      "A"
      ["B", "C"]
      true
      false
      true
      false
      true
      ["boom", true]
      "pw"
      true
      IO::ConsoleMode
      false
      IO::ConsoleMode
      IO::ConsoleMode
      [24, 80]
      [24, 80]
      true
    OUT
  end
end
