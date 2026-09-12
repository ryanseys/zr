# Child processes: `system`, backticks and Process.spawn over
# posix_spawn. A single command string goes through /bin/sh when it
# holds shell syntax or starts with a shell word; else its words run
# directly.
module Process
  SHELL_META = "*?{}[]<>()~&|\\$;'`\"\n#".freeze
  SHELL_WORDS = %w[! . : break case continue do done elif else esac eval exec exit export fi for if in readonly return set shift then times trap unset until while].freeze
  # The signals a process can be sent: Signal.list less EXIT, which
  # names no signal.
  SIGNALS = Signal.send(:const_get, :LIST).reject { |name, _| name == "EXIT" }.freeze
  private_constant :SHELL_META, :SHELL_WORDS, :SIGNALS
  WNOHANG = 1
  WUNTRACED = 2

  # Who a priority is asked about: a process, a process group, a user.
  PRIO_PROCESS = 0
  PRIO_PGRP = 1
  PRIO_USER = 2

  # An answer from the kernel, or the errno it carries instead.
  def self.checked(result)
    Primitive.attr! :hidden
    raise SystemCallError.new(nil, -result) if result.is_a?(Integer) && result < 0

    result
  end
  private_class_method :checked

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

  # What a spawn's options ask the child for: `dups` are (child
  # descriptor, source descriptor) pairs applied in order, `closes` the
  # child's descriptors to shut, and `opened` the parent's own streams
  # to close once the child holds copies of them.
  class Redirects
    STREAMS = { in: 0, out: 1, err: 2 }.freeze
    private_constant :STREAMS

    attr_reader :dups, :closes, :opened, :chdir

    def initialize(options)
      # The standard streams cross into the child; every other
      # descriptor the parent holds stays behind, so a pipe end the
      # parent keeps cannot hold the child's own read open. An option
      # that names one of the three comes later and wins.
      @dups = [0, 0, 1, 1, 2, 2]
      @closes = []
      @opened = []
      @chdir = nil
      options.each { |key, value| add(key, value) }
    end

    private

    def add(key, value)
      case key
      when :chdir then @chdir = path_of(value)
      when :unsetenv_others, :close_others then nil
      when Symbol
        return descriptors(key).each { |fd| redirect(fd, value) } if STREAMS.key?(key)

        Primitive.zr_unimplemented("Process.spawn with #{key}:")
      else descriptors(key).each { |fd| redirect(fd, value) }
      end
    end

    # The child's descriptors one option key names.
    def descriptors(key)
      case key
      when Integer then [key]
      when Symbol then [STREAMS.fetch(key) { raise ArgumentError, "wrong exec option symbol: #{key.inspect}" }]
      when IO then [key.fileno]
      when Array then key.flat_map { |one| descriptors(one) }
      else raise ArgumentError, "wrong exec option: #{key.inspect}"
      end
    end

    def redirect(fd, value)
      case value
      when Integer then dup2(fd, value)
      when :close then @closes << fd
      when Symbol then dup2(fd, STREAMS.fetch(value) { raise ArgumentError, "wrong exec redirect symbol: #{value.inspect}" })
      when IO then dup2(fd, value.fileno)
      when String then open_file(fd, value, nil, nil)
      when Array then from_array(fd, value)
      else raise ArgumentError, "wrong exec redirect action"
      end
    end

    # `[:child, :out]` is the child's own descriptor, so the pair is
    # applied in the order the options list them.
    def from_array(fd, value)
      return dup2(fd, descriptors(value[1]).first) if value.first == :child

      open_file(fd, value[0], value[1], value[2])
    end

    def dup2(fd, source)
      @dups << fd << source
    end

    def open_file(fd, path, mode, perm)
      io = File.open(path_of(path), mode || (fd == 0 ? "r" : "w"), perm || 0o666)
      @opened << io
      dup2(fd, io.fileno)
    end

    def path_of(value) = String.try_convert(value) || value.to_path
  end
  private_constant :Redirects

  def self.spawn(*args, **options)
    pid = spawn_command(args, options)
    raise SystemCallError.new(command_words(args).first, 2) if pid.nil?

    pid
  end

  def wait(pid = -1, flags = 0)
    result = Primitive.zr_proc_wait(pid, flags)
    raise SystemCallError.new(nil, -result) if result.is_a?(Integer)

    child, raw = result
    return nil if child == 0

    $? = Status.new(child, raw)
    child
  end

  def waitpid(pid = -1, flags = 0) = Process.wait(pid, flags)

  def wait2(pid = -1, flags = 0)
    child = Process.wait(pid, flags)
    child && [child, $?]
  end

  def waitpid2(pid = -1, flags = 0) = Process.wait2(pid, flags)

  def self.last_status = $?

  def ppid = Primitive.zr_proc_ppid

  # The process group and the session. Each call answers an id, and a
  # failure arrives as its errno.
  def getpgrp = Process.send(:checked, Primitive.zr_proc_getpgrp)

  def getpgid(pid) = Process.send(:checked, Primitive.zr_proc_getpgid(Integer.send(:int_operand, pid)))

  def setpgid(pid, pgrp)
    Process.send(:checked, Primitive.zr_proc_setpgid(Integer.send(:int_operand, pid), Integer.send(:int_operand, pgrp)))
  end

  def getsid(pid = 0) = Process.send(:checked, Primitive.zr_proc_getsid(Integer.send(:int_operand, pid)))

  def setsid = Process.send(:checked, Primitive.zr_proc_setsid)

  def groups = Process.send(:checked, Primitive.zr_proc_groups)

  # The most groups this platform carries, as getgroups counts them.
  def maxgroups = 16

  # A niceness is a number that can be negative, so the errno beside
  # it, and not the answer, says whether the call failed.
  def getpriority(which, who)
    value, errno = Primitive.zr_proc_getpriority(Integer.send(:int_operand, which), Integer.send(:int_operand, who))
    raise SystemCallError.new(nil, errno) if value == -1 && errno != 0

    value
  end

  def setpriority(which, who, priority)
    Process.send(:checked, Primitive.zr_proc_setpriority(Integer.send(:int_operand, which), Integer.send(:int_operand, who), Integer.send(:int_operand, priority)))
  end

  Tms = Struct.new(:utime, :stime, :cutime, :cstime)

  # This process's times, then its waited-for children's.
  def times
    Tms.new(*Primitive.zr_proc_rusage(0), *Primitive.zr_proc_rusage(-1))
  end

  def kill(signal, *pids)
    number = signal.is_a?(Integer) ? signal : SIGNALS.fetch(signal.to_s.delete_prefix("SIG")) { raise ArgumentError, "unsupported signal 'SIG#{signal.to_s.delete_prefix('SIG')}'" }
    pids.each do |pid|
      result = Primitive.zr_proc_kill(pid, number)
      raise SystemCallError.new(nil, -result) if result < 0
    end
    pids.size
  end

  def daemon(*) = Primitive.zr_unimplemented("Process.daemon")

  module_function :wait, :waitpid, :wait2, :waitpid2, :ppid, :times, :kill, :daemon, :getpgrp, :getpgid,
                  :setpgid, :getsid, :setsid, :groups, :maxgroups, :getpriority, :setpriority

  def self.exit(status = true) = Kernel.exit(status)

  def self.exit!(status = false) = Kernel.exit!(status)

  def self.abort(*args) = Kernel.abort(*args)

  def self.fork(*) = Primitive.zr_unimplemented("Process.fork")

  def self.signal_number(name) = SIGNALS[name]

  def self.signal_name(number) = SIGNALS.key(number)

  # Runs the command; the child's pid, or nil when it could not start
  # (then `$?` says exit 127).
  # `rb_exec_getargs`: a leading Hash is the environment and a trailing
  # Hash is the options, written as arguments rather than as keywords.
  def self.exec_args(args, options)
    args = args.dup
    env = args.first.is_a?(Hash) ? args.shift : nil
    options = options.merge(args.pop) if args.size > 1 && args.last.is_a?(Hash)
    [env, args, options]
  end

  def self.spawn_command(args, options)
    env, args, options = exec_args(args, options)
    words = command_words(args)
    IO.send(:flush_std)
    redirects = Redirects.new(options)
    pid = Primitive.zr_proc_spawn(words, redirects.dups, redirects.closes, environment(env, options), redirects.chdir)
    redirects.opened.each(&:close)
    if pid < 0
      $? = Status.new(0, 127 << 8)
      return nil
    end
    pid
  end

  # The program and its arguments. One string goes through the shell
  # when it holds shell syntax; a list is the argument vector itself.
  def self.command_words(args)
    raise ArgumentError, "wrong number of arguments (given 0, expected 1+)" if args.empty?

    words = args.size == 1 ? shell_words(args.first) : args.map { |arg| arg.is_a?(Array) ? arg.first : arg }
    words.each do |word|
      raise TypeError, "no implicit conversion of #{conversion_name(word)} into String" unless word.is_a?(String)
      raise ArgumentError, "string contains null byte" if word.include?("\0")
    end
    words
  end

  def self.shell_words(command)
    raise TypeError, "no implicit conversion of #{conversion_name(command)} into String" unless command.is_a?(String)

    # An `=` inside the first word makes it an assignment, which only a
    # shell can do, as rb_exec_fillarg reads it.
    first = command.split(" ").first || ""
    # rb_exec_fillarg hands the shell its own name as argv[0], which is
    # the name a shell puts in front of its own complaints, and the
    # spawn finds it on PATH.
    return ["sh", "-c", command] if command.each_char.any? { |c| SHELL_META.include?(c) } || SHELL_WORDS.include?(first) || first.include?("=")

    words = command.split(" ")
    # A command of no words at all still names a program: rb_exec_fillarg
    # leaves the name empty, and the exec of it answers ENOENT. An empty
    # list would leave the spawn with no program name to read.
    words.empty? ? [""] : words
  end

  # The child's whole environment as "KEY=value" strings, or nil to
  # inherit the parent's.
  def self.environment(env, options)
    return nil if env.nil? && !options[:unsetenv_others]

    table = options[:unsetenv_others] ? {} : ENV.to_h
    env&.each do |key, value|
      key = String.try_convert(key) or raise TypeError, "no implicit conversion of #{conversion_name(key)} into String"
      if value.nil?
        table.delete(key)
      else
        table[key] = String.try_convert(value) or raise TypeError, "no implicit conversion of #{conversion_name(value)} into String"
      end
    end
    table.map { |key, value| "#{key}=#{value}" }
  end

  # The words a command runs as, for exec.
  def self.exec_words(args, options)
    env, args, options = exec_args(args, options)
    Primitive.zr_unimplemented("exec with options") unless options.empty?
    Primitive.zr_unimplemented("exec with an environment") unless env.nil?

    words = command_words(args)
    IO.send(:flush_std)
    words
  end

  private_class_method :spawn_command, :command_words, :shell_words, :environment, :exec_words, :exec_args
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

  def spawn(*args, **options)
    pid = Process.send(:spawn_command, args, options)
    raise SystemCallError.new(Process.send(:command_words, args).first, 2) if pid.nil?

    pid
  end

  def system(*args, exception: false, **options)
    pid = Process.send(:spawn_command, args, options)
    if pid.nil?
      raise SystemCallError.new(Process.send(:command_words, args).first, 2) if exception

      return nil
    end
    Process.wait(pid)
    return true if $?.success?
    raise RuntimeError, "Command failed with exit #{$?.exitstatus}: #{args.join(' ')}" if exception

    false
  end

  # Backticks: the command's standard output, read through a pipe.
  def `(command)
    IO.popen(command) { |io| io.read.force_encoding(Encoding.default_external) }
  end

  private :spawn, :system, :`
  module_function :spawn, :system, :`
end

module Signal
  def self.list = LIST.dup

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
