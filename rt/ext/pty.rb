# frozen_string_literal: true

# `require "pty"`: a pseudo-terminal pair. ruby opens the master through
# the Unix98 calls (posix_openpt, grantpt, unlockpt) and then opens the
# slave device by the name they give.
module PTY
  # A child that ended or stopped, which PTY.check reports by name. The
  # status it carries is the one the wait answered.
  class ChildExited < RuntimeError
    attr_reader :status
  end

  # The master and the slave of a new pair. The master is an IO whose
  # path names the pair rather than any file; the slave is a File on the
  # device itself. A block takes the pair and leaves both closed.
  def self.open
    answer = Primitive.zr_pty_open
    raise RuntimeError, "can't get Master/Slave device" if answer.is_a?(Integer) # rubocop:disable Style/RedundantException

    descriptor, name = answer
    master = IO.new(descriptor, "r+", path: "masterpty:#{name}".freeze)
    master.sync = true
    # PTY.open asks for a slave no other user can write to, which is
    # what prevent_messages does with its own chmod.
    File.chmod(0o600, name)
    slave = File.open(name, "r+")
    slave.sync = true
    pair = [master, slave]
    return pair unless block_given?

    begin
      yield pair
    ensure
      pair.each { |stream| stream.close unless stream.closed? }
    end
  end

  # pty_getpty: a child on the far end of a new pair, leading a session
  # with the slave for its terminal, and the master as a reading File and
  # a writing one, both named for the slave. With no command the child
  # is the user's shell. A block takes the three, and the child is
  # detached after it.
  def self.spawn(*command)
    command = [login_shell] if command.empty?
    answer = Primitive.zr_pty_open
    raise RuntimeError, "can't get Master/Slave device" if answer.is_a?(Integer) # rubocop:disable Style/RedundantException

    master, name = answer
    slave = Primitive.zr_io_open_flags(name, File::RDWR | File::NOCTTY, 0)
    if slave.negative?
      Primitive.zr_io_close(master)
      raise SystemCallError.new("open: pty slave", -slave)
    end
    pid = Process.send(:tty_spawn, command, master, slave)
    Primitive.zr_io_close(slave)
    if pid.negative?
      Primitive.zr_io_close(master)
      raise SystemCallError.new("fork failed", -pid)
    end
    path = name.dup.freeze
    reader = stream(master, "r", path)
    writer = stream(Primitive.zr_io_dup(master), "w", path)
    writer.sync = true
    ends = [reader, writer, pid]
    return ends unless block_given?

    begin
      yield ends
    ensure
      detach(pid)
    end
    nil
  end

  class << self
    alias getpty spawn
  end

  # Whether a child changed state: nil while it runs, its status once it
  # ended or stopped, and a ChildExited when the caller asks to be told
  # by exception.
  def self.check(pid, want_raise = nil)
    answer = begin
      Process.wait2(pid, Process::WNOHANG | Process::WUNTRACED)
    rescue SystemCallError
      nil
    end
    return nil if answer.nil?

    status = answer[1]
    return status unless want_raise

    error = ChildExited.new("pty - #{state_of(pid, status)}: #{pid}")
    Primitive.zr_hidden_set(error, :status, status)
    raise error
  end

  # The word ruby puts in the message: a stopped child, one that changed
  # in some other way and is still there, or one that has gone.
  def self.state_of(pid, status)
    Primitive.attr! :hidden
    return "stopped" if status.stopped?

    begin
      Process.kill(0, pid)
      "changed"
    rescue SystemCallError
      "exited"
    end
  end
  private_class_method :state_of

  # establishShell's shell: $SHELL, else the user's login shell, else
  # /bin/sh.
  def self.login_shell
    Primitive.attr! :hidden
    return ENV["SHELL"] if ENV["SHELL"]

    require "etc"
    user = ENV["USER"] || Etc.getlogin
    (user && Etc.getpwnam(user)&.shell) || "/bin/sh"
  rescue ArgumentError
    "/bin/sh"
  end

  # A File on a descriptor, named `path`.
  def self.stream(fd, mode, path)
    Primitive.attr! :hidden
    file = File.allocate
    IO.instance_method(:initialize).bind_call(file, fd, mode, path: path)
    file
  end

  # pty_detach_process: a child already gone is reaped, else a thread
  # waits for it.
  def self.detach(pid)
    Primitive.attr! :hidden
    Process.detach(pid) if Process.waitpid(pid, Process::WNOHANG).nil?
  rescue SystemCallError
    nil
  end
  private_class_method :login_shell, :stream, :detach
end
