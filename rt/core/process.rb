# Child processes: `system`, backticks and Process.spawn over
# posix_spawn. A single command string goes through /bin/sh when it
# holds shell syntax or starts with a shell word; else its words run
# directly.
module Process
  SHELL_META = "*?{}[]<>()~&|\\$;'`\"\n#".freeze
  SHELL_WORDS = %w[! . : break case continue do done elif else esac eval exec exit export fi for if in readonly return set shift then times trap unset until while].freeze
  SIGNALS = { "HUP" => 1, "INT" => 2, "QUIT" => 3, "ILL" => 4, "TRAP" => 5, "ABRT" => 6, "EMT" => 7, "FPE" => 8, "KILL" => 9, "BUS" => 10,
              "SEGV" => 11, "SYS" => 12, "PIPE" => 13, "ALRM" => 14, "TERM" => 15, "URG" => 16, "STOP" => 17, "TSTP" => 18, "CONT" => 19,
              "CHLD" => 20, "TTIN" => 21, "TTOU" => 22, "IO" => 23, "XCPU" => 24, "XFSZ" => 25, "VTALRM" => 26, "PROF" => 27,
              "WINCH" => 28, "INFO" => 29, "USR1" => 30, "USR2" => 31 }.freeze
  private_constant :SHELL_META, :SHELL_WORDS, :SIGNALS
  WNOHANG = 1
  WUNTRACED = 2

  # What waitpid answered for a child.
  class Status
    attr_reader :pid, :to_i

    def initialize(pid, raw)
      @pid = pid
      @to_i = raw
    end

    def exited? = (@to_i & 0x7F) == 0

    def signaled? = !exited? && !stopped?

    def stopped? = (@to_i & 0xFF) == 0x7F

    def exitstatus = exited? ? (@to_i >> 8) & 0xFF : nil

    def termsig = signaled? ? @to_i & 0x7F : nil

    def stopsig = stopped? ? (@to_i >> 8) & 0xFF : nil

    def coredump? = signaled? && (@to_i & 0x80) != 0

    def success? = exited? ? exitstatus == 0 : nil

    def ==(other) = other.is_a?(Integer) ? @to_i == other : (other.is_a?(Status) && @to_i == other.to_i)

    def &(mask) = @to_i & mask

    def >>(places) = @to_i >> places

    def to_s
      return "pid #{@pid} exit #{exitstatus}" if exited?
      return "pid #{@pid} stopped SIG#{Signal.signame(stopsig)} (signal #{stopsig})" if stopped?

      "pid #{@pid} SIG#{Signal.signame(termsig)} (signal #{termsig})#{coredump? ? ' (core dumped)' : ''}"
    end

    def inspect = "#<Process::Status: #{self}>"
  end

  def self.spawn(*args, **options)
    pid = spawn_command(args, options, nil)
    raise SystemCallError.new("No such file or directory - #{args.first}", 2) if pid.nil?

    pid
  end

  def self.wait(pid = -1, flags = 0)
    result = Primitive.zr_proc_wait(pid, flags)
    raise SystemCallError.new(nil, -result) if result.is_a?(Integer)

    child, raw = result
    return nil if child == 0

    $? = Status.new(child, raw)
    child
  end

  def self.waitpid(pid = -1, flags = 0) = wait(pid, flags)

  def self.wait2(pid = -1, flags = 0)
    child = wait(pid, flags)
    child && [child, $?]
  end

  def self.waitpid2(pid = -1, flags = 0) = wait2(pid, flags)

  def self.last_status = $?

  def self.ppid = Primitive.zr_proc_ppid

  Tms = Struct.new(:utime, :stime, :cutime, :cstime)

  # This process's times, then its waited-for children's.
  def self.times
    Tms.new(*Primitive.zr_proc_rusage(0), *Primitive.zr_proc_rusage(-1))
  end

  def self.kill(signal, *pids)
    number = signal.is_a?(Integer) ? signal : SIGNALS.fetch(signal.to_s.delete_prefix("SIG")) { raise ArgumentError, "unsupported signal 'SIG#{signal.to_s.delete_prefix('SIG')}'" }
    pids.each do |pid|
      result = Primitive.zr_proc_kill(pid, number)
      raise SystemCallError.new(nil, -result) if result < 0
    end
    pids.size
  end

  def self.exit(status = true) = Kernel.exit(status)

  def self.exit!(status = false) = Kernel.exit!(status)

  def self.abort(*args) = Kernel.abort(*args)

  def self.fork(*) = Primitive.zr_unimplemented("Process.fork")

  def self.daemon(*) = Primitive.zr_unimplemented("Process.daemon")

  def self.signal_number(name) = SIGNALS[name]

  def self.signal_name(number) = SIGNALS.key(number)

  # Runs the command; the child's pid, or nil when it could not start
  # (then `$?` says exit 127).
  def self.spawn_command(args, options, out)
    Primitive.zr_unimplemented("Process.spawn with options") unless options.empty?
    args = args.dup
    args.shift if args.first.is_a?(Hash) && Primitive.zr_unimplemented("Process.spawn with an environment")
    raise ArgumentError, "wrong number of arguments (given 0, expected 1+)" if args.empty?

    words = args.size == 1 ? command_words(args.first) : args.map { |arg| arg.is_a?(Array) ? arg.first : arg }
    words.each { |word| raise TypeError, "no implicit conversion of #{word.class} into String" unless word.is_a?(String) }
    words.each { |word| raise ArgumentError, "string contains null byte" if word.include?("\0") }
    pid = words.empty? ? -2 : Primitive.zr_proc_spawn(words, out)
    if pid < 0
      $? = Status.new(0, 127 << 8)
      return nil
    end
    pid
  end

  def self.command_words(command)
    raise TypeError, "no implicit conversion of #{command.class} into String" unless command.is_a?(String)

    first = command.split(" ").first || ""
    return ["/bin/sh", "-c", command] if command.each_char.any? { |c| SHELL_META.include?(c) } || SHELL_WORDS.include?(first)

    command.split(" ")
  end

  # The words a command runs as, for exec.
  def self.exec_words(args, options)
    Primitive.zr_unimplemented("exec with options") unless options.empty?
    args = args.dup
    args.shift if args.first.is_a?(Hash) && Primitive.zr_unimplemented("exec with an environment")
    raise ArgumentError, "wrong number of arguments (given 0, expected 1+)" if args.empty?

    words = args.size == 1 ? command_words(args.first) : args.map { |arg| arg.is_a?(Array) ? arg.first : arg }
    words.each { |word| raise TypeError, "no implicit conversion of #{word.class} into String" unless word.is_a?(String) }
    words.each { |word| raise ArgumentError, "string contains null byte" if word.include?("\0") }
    words
  end

  private_class_method :spawn_command, :command_words, :exec_words
end

module Kernel
  # The process becomes the command; only a failure to start returns.
  def exec(*args, **options)
    words = Process.send(:exec_words, args, options)
    result = words.empty? ? -2 : Primitive.zr_proc_exec(words)
    raise SystemCallError.new(words.first || args.first, -result)
  end
  private :exec
  module_function :exec

  def system(*args, exception: false, **options)
    pid = Process.send(:spawn_command, args, options, nil)
    if pid.nil?
      raise SystemCallError.new("No such file or directory - #{args.first}", 2) if exception

      return nil
    end
    Process.wait(pid)
    return true if $?.success?
    raise RuntimeError, "Command failed with exit #{$?.exitstatus}: #{args.join(' ')}" if exception

    false
  end

  # Backticks: the command's stdout, read through a pipe.
  def `(command)
    ends = Primitive.zr_io_pipe
    raise SystemCallError.new(nil, -ends) if ends.is_a?(Integer)

    reader, writer = ends
    pid = Process.send(:spawn_command, [command], {}, writer)
    Primitive.zr_io_close(writer)
    if pid.nil?
      Primitive.zr_io_close(reader)
      raise SystemCallError.new("No such file or directory - #{command}", 2)
    end
    out = "".b
    loop do
      chunk = Primitive.zr_io_read(reader, 65536)
      break if chunk.nil?
      raise SystemCallError.new(nil, -chunk) if chunk.is_a?(Integer)

      out << chunk
    end
    Primitive.zr_io_close(reader)
    Process.wait(pid)
    out.force_encoding(Encoding.default_external)
  end

  private :system, :`
  module_function :system, :`
end

module Signal
  def self.list = Process.send(:const_get, :SIGNALS).dup.merge("EXIT" => 0)

  def self.signame(number)
    number = Primitive.zr_index_operand_m(number)
    number == 0 ? "EXIT" : Process.signal_name(number)
  end

  def self.trap(*) = Primitive.zr_unimplemented("Signal.trap")
end

module Kernel
  def trap(*) = Primitive.zr_unimplemented("Kernel#trap")
  private :trap
end
