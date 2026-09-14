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

  # A child on the far end of a new pair. The child needs a session of
  # its own and the slave for its terminal, which no spawn here reaches
  # yet.
  def self.spawn(*) = Primitive.zr_unimplemented("PTY.spawn")

  def self.getpty(*) = Primitive.zr_unimplemented("PTY.getpty")

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
end
