# frozen_string_literal: true

# Child processes: `system`, backticks and Process.spawn over
# posix_spawn. A single command string goes through /bin/sh when it
# contains shell syntax or starts with a shell word; else its words run
# directly.
module Process
  SHELL_META = "*?{}[]<>()~&|\\$;'`\"\n#".freeze
  SHELL_WORDS = %w[! . : break case continue do done elif else esac eval exec exit export fi for if in readonly return set shift then times trap unset until while].freeze
  private_constant :SHELL_META, :SHELL_WORDS

  # A result from the kernel, or the errno that it gives in its place.
  def self.checked(result)
    Primitive.attr! :hidden
    raise SystemCallError.new(nil, -result) if result.is_a?(Integer) && result < 0

    result
  end
  private_class_method :checked

  # waitpid(2) as rb_waitpid runs it: `[pid, status word]`, `[0, 0]` for
  # a WNOHANG child still running, or the negated errno. A thread among
  # others parks on the pipe SIGCHLD writes to between WNOHANG tries,
  # so its siblings run while the child does; the signal count taken
  # before each try tells a signal that came since from one drained.
  # Each wakeup ends the park, and the thread that drains the pipe
  # wakes the other waiters, so a signal that one thread drained still
  # sends every waiter back to its try.
  def self.reap(pid, flags)
    Primitive.attr! :hidden
    pid = Integer.send(:int_operand, pid)
    flags = Integer.send(:int_operand, flags)
    # A non-blocking fiber's scheduler may wait for the child itself.
    scheduler = Fiber.current_scheduler
    if scheduler.respond_to?(:process_wait)
      status = scheduler.process_wait(pid, flags)
      return status && [status.pid, status.to_i]
    end
    return Primitive.zr_proc_wait(pid, flags) if flags.anybits?(WNOHANG) || !Primitive.zr_threaded || Thread.send(:alone?)

    fd = Primitive.zr_chld_fd(Signal.list.fetch(+"CHLD"))
    return Primitive.zr_proc_wait(pid, flags) if fd.negative?

    waiters = (@child_waiters ||= [])
    waiters << Thread.current
    begin
      loop do
        seen = Primitive.zr_chld_count
        result = Primitive.zr_proc_wait(pid, flags | WNOHANG)
        return result if result.is_a?(Integer) || !result[0].zero?

        Thread.current.send(:park_io, fd, IO::READABLE) if Primitive.zr_chld_count == seen
        Primitive.zr_chld_drain
        tell_waiters(waiters)
      end
    ensure
      Thread.send(:atomically) { waiters.delete(Thread.current) }
    end
  end
  private_class_method :reap

  # Wakes each other thread that waits for a child, once for each new
  # count of SIGCHLD: the pipe that would wake them is drained.
  def self.tell_waiters(waiters)
    Primitive.attr! :hidden
    count = Primitive.zr_chld_count
    return if count == @told_count

    @told_count = count
    waiters.each { |waiter| waiter.wakeup if !waiter.equal?(Thread.current) && waiter.status == +"sleep" }
  end
  private_class_method :tell_waiters

  # The value that waitpid returned for a child.
  class Status
    # An allocated status is pid 0 with a status word of 0.
    def self.allocate
      Primitive.attr! :hidden
      Primitive.zr_class_allocate(self).tap { |status| status.send(:initialize, 0, 0) }
    end

    attr_reader :pid, :to_i

    def initialize(pid, raw)
      Primitive.attr! :hidden
      @pid = pid
      @to_i = raw
    end

    # Process.wait's status and not its pid, leaving `$?` alone: nil
    # while a WNOHANG child still runs, and pid -1 when there is none to
    # wait for.
    def self.wait(pid = -1, flags = 0)
      result = Process.send(:reap, pid, flags)
      return new(-1, 0) if result.is_a?(Integer)

      child, raw = result
      child.zero? ? nil : new(child, raw)
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

    def to_s
      return "pid #{@pid} exit #{exitstatus}" if exited?
      return "pid #{@pid} stopped SIG#{Signal.signame(stopsig)} (signal #{stopsig})" if stopped?

      "pid #{@pid} SIG#{Signal.signame(termsig)} (signal #{termsig})#{coredump? ? ' (core dumped)' : ''}"
    end

    def inspect = Primitive.zr_obj_form(@pid.zero? ? "#<#{self.class}: uninitialized>" : "#<Process::Status: #{self}>")
  end

  # What a spawn's options set up for the child: `dups` are (child
  # descriptor, source descriptor) pairs applied in order, `closes` the
  # child's descriptors to close, and `opened` the parent's own streams
  # to close after the child has copies of them.
  class Redirects
    STREAMS = { in: 0, out: 1, err: 2 }.freeze
    # fcntl's command for a copy at or above a number, on every target.
    F_DUPFD = 0
    private_constant :STREAMS, :F_DUPFD

    attr_reader :dups, :closes, :opened, :chdir, :pgroup, :umask, :limits, :close_others

    def initialize(options)
      # The standard streams go into the child. All other descriptors of
      # the parent stay in the parent, so a pipe end that the parent keeps
      # cannot keep the child's own read open. An option that refers to
      # one of the three comes later and wins.
      @dups = [0, 0, 1, 1, 2, 2]
      @child_dups = []
      # The child's descriptors that an option names, each at most once.
      @named = []
      @closes = []
      @opened = []
      @chdir = nil
      @close_others = false
      # -1 leaves the process group and the umask as they are.
      @pgroup = -1
      @umask = -1
      @limits = []
      # -1 leaves the user and the group as they are.
      @uid = -1
      @gid = -1
      options.each { |key, value| add(key, value) }
      @dups = ordered(@dups) + children
    end

    # Whether an option needs what only a forked child can do before
    # its exec.
    def forked? = @pgroup >= 0 || @umask >= 0 || !@limits.empty? || @uid >= 0 || @gid >= 0

    # What zr_exec_options applies, in the order it reads them.
    def to_a = [@dups, @closes, @chdir, @pgroup, @umask, @limits, @uid, @gid]

    private

    # rb_execarg_addopt: each option once.
    def add(key, value)
      case key
      when :chdir then @chdir = path_of(value)
      when :unsetenv_others then nil
      when :close_others then @close_others = value ? true : false
      when :pgroup then @pgroup = pgroup_of(value)
      when :umask then @umask = Integer.send(:int_operand, value)
      when :uid then @uid = id_option(value, false)
      when :gid then @gid = id_option(value, true)
      when Symbol
        return redirect(descriptor(key), value) if STREAMS.key?(key)
        return add_limit(key, value) if key.start_with?("rlimit_")

        raise ArgumentError, "wrong exec option symbol: #{key}"
      else
        fds = descriptors(key)
        # Several descriptors to one file share one open of it.
        if fds.size > 1 && (value.is_a?(String) || (value.is_a?(Array) && value.first != :child))
          redirect(fds.first, value)
          opened = @dups.last
          fds.drop(1).each { |fd| dup2(fd, opened) }
        else
          fds.each { |fd| redirect(fd, value) }
        end
      end
    end

    # The user or group the child becomes before its exec: a number or a
    # name, which no UID.switch or GID.switch block may change.
    def id_option(value, group)
      Process.send(:switching!, group)
      Process.send(:id_of, value, group)
    end

    def pgroup_of(value)
      return -1 unless value
      return 0 if value == true

      group = Integer.send(:int_operand, value)
      raise ArgumentError, "negative process group ID : #{group}" if group.negative?

      group
    end

    # rb_execarg_addopt_rlimit: one limit for both, or [soft, hard].
    def add_limit(key, value)
      lower = key.name.delete_prefix("rlimit_")
      # rlimit_type_by_lname: the name is in lower case.
      resource = (RLIMITS[lower.upcase] if lower == lower.downcase) or raise ArgumentError, "wrong exec option symbol: #{key}"
      limits = Array.try_convert(value)
      soft, hard = if limits.nil? then [value, value]
                   elsif limits.size == 1 then [limits[0], limits[0]]
                   elsif limits.size == 2 then limits
                   else raise ArgumentError, +"wrong exec rlimit option"
                   end
      # NUM2RLIM: a limit fills an rlim_t, so RLIM_INFINITY fits.
      soft, hard = [soft, hard].map { |limit| Process.send(:signed, Process.send(:unsigned, limit, 64, +"unsigned long long")) }
      @limits.push(resource, soft, hard)
    end

    # rb_execarg_addopt: the child's descriptors that an option key names,
    # a Fixnum, an IO or an Array of descriptors.
    def descriptors(key)
      case key
      when Array then key.map { |one| descriptor(one) }
      when IO then [descriptor(key)]
      when Integer
        # A Bignum is no descriptor at all.
        raise ArgumentError, +"wrong exec option" unless key.bit_length < 63

        [descriptor(key)]
      else raise ArgumentError, +"wrong exec option"
      end
    end

    # check_exec_redirect_fd: one descriptor, as a Fixnum that fits an int,
    # :in, :out or :err, or an IO or what converts to one.
    def descriptor(value)
      fd = case value
           when Symbol then STREAMS.fetch(value) { raise ArgumentError, +"wrong exec redirect" }
           when Integer
             raise ArgumentError, +"wrong exec redirect" unless value.bit_length < 63

             Integer.send(:int_operand, value)
           else
             io = IO.try_convert(value) or raise ArgumentError, +"wrong exec redirect"
             undivided(io).fileno
           end
      raise ArgumentError, +"negative file descriptor" if fd.negative?

      fd
    end

    def redirect(fd, value)
      case value
      when Integer then dup2(fd, value)
      when :close then @closes << fd
      when Symbol then dup2(fd, STREAMS.fetch(value) { raise ArgumentError, "wrong exec redirect symbol: #{value.inspect}" })
      when IO then dup2(fd, undivided(value).fileno)
      when String then open_file(fd, value, nil, nil)
      when Array then from_array(fd, value)
      else
        # check_exec_redirect: an object that converts with to_io is that IO.
        io = IO.try_convert(value) or raise ArgumentError, +"wrong exec redirect action"
        dup2(fd, io.fileno)
      end
    end

    # `[:child, :out]` is the child's own descriptor after the other
    # redirects, so these pairs come last, in the order the options list
    # them (run_exec_dup2_child).
    def from_array(fd, value)
      return @child_dups << named(fd) << descriptor(value[1]) if value.first == :child

      open_file(fd, value[0], value[1], value[2])
    end

    def dup2(fd, source)
      @dups << named(fd) << source
    end

    # check_exec_redirect_fd: an option names each child descriptor once.
    def named(fd)
      raise ArgumentError, "fd #{fd} specified twice" if @named.include?(fd)

      @named << fd
      fd
    end

    # A duplex popen stream has two descriptors, so it names none.
    def undivided(io)
      raise ArgumentError, +"duplex IO redirection" if Primitive.zr_hidden_get(io, :twin)

      io
    end

    # check_exec_fds: a `[:child, fd]` pair copies what the child's `fd`
    # ends as, through a chain of them, after the other pairs. A chain
    # that comes back is cyclic, and one that ends at a descriptor no
    # other option names copies nothing.
    def children
      chains = @child_dups.each_slice(2).to_h
      chains.flat_map do |to, first|
        from = first
        seen = [to]
        while chains.key?(from)
          raise ArgumentError, "cyclic child fd redirection from #{first}" if seen.include?(from)

          seen << from
          from = chains[from]
        end
        raise ArgumentError, "child fd #{from} is not redirected" unless @named.include?(from) && !chains.key?(from)

        [to, from]
      end
    end

    # run_exec_dup2: the pairs in an order where no dup2 replaces a
    # descriptor that a later pair still reads. In a cycle, one pair reads
    # its source through a copy that the parent makes and closes after the
    # spawn. The copy's number is above every descriptor a pair names, so
    # no pair writes over it, and the program that the child runs does
    # not get it.
    def ordered(flat)
      pending = flat.each_slice(2).to_a
      above = flat.max + 1
      done = []
      until pending.empty?
        # A pair onto itself only clears close-on-exec: it changes no
        # descriptor that another pair reads, and it reads nothing.
        at = pending.index do |to, from|
          to == from || pending.none? { |other, read| read == to && other != read }
        end
        if at
          done << pending.delete_at(at)
        else
          to, from = pending.first
          copy = IO.for_fd(Process.send(:checked, Primitive.zr_io_fcntl(from, F_DUPFD, above)), autoclose: true)
          Primitive.zr_io_cloexec(copy.fileno)
          @opened << copy
          pending[0] = [to, copy.fileno]
        end
      end
      done.flatten
    end

    # A file that does not open closes the ones opened before it, and
    # the error names only the path, as ruby's child reports its open.
    def open_file(fd, path, mode, perm)
      name = path_of(path)
      begin
        io = File.open(name, mode || (fd == 0 ? "r" : "w"), perm || 0o666)
      rescue SystemCallError => e
        @opened.each(&:close)
        raise e.class.new(name)
      end
      @opened << io
      dup2(fd, io.fileno)
    end

    def path_of(value) = String.try_convert(value) || value.to_path
  end
  private_constant :Redirects

  def self.spawn(*args, **options)
    pid = spawn_command(args, options)
    raise start_error(args, options, pid) if pid.negative?

    pid
  end

  def wait(pid = -1, flags = 0)
    result = Process.send(:reap, pid, flags)
    raise SystemCallError.new(nil, -result) if result.is_a?(Integer)

    child, raw = result
    return nil if child == 0

    Process.send(:status!, Status.new(child, raw))
    child
  end

  def waitpid(pid = -1, flags = 0) = Process.wait(pid, flags)

  def wait2(pid = -1, flags = 0)
    child = Process.wait(pid, flags)
    child && [child, $?]
  end

  def waitpid2(pid = -1, flags = 0) = Process.wait2(pid, flags)

  # Every child that is left, reaped: `[pid, status]` each.
  def waitall
    Process.send(:status!, nil)
    children = []
    loop do
      result = Process.send(:reap, -1, 0)
      if result.is_a?(Integer)
        break if -result == Errno::ECHILD::Errno

        raise SystemCallError.new(nil, -result)
      end
      Process.send(:status!, Status.new(*result))
      children << [result[0], $?]
    end
    children
  end

  def self.last_status = $?

  def ppid = Primitive.zr_proc_ppid

  # The process group and the session. Each call returns an id, and a
  # failure arrives as its errno.
  def getpgrp = Process.send(:checked, Primitive.zr_proc_getpgrp)

  def getpgid(pid) = Process.send(:checked, Primitive.zr_proc_getpgid(Integer.send(:int_operand, pid)))

  def setpgid(pid, pgrp)
    Process.send(:checked, Primitive.zr_proc_setpgid(Integer.send(:int_operand, pid), Integer.send(:int_operand, pgrp)))
  end

  def getsid(pid = 0) = Process.send(:checked, Primitive.zr_proc_getsid(Integer.send(:int_operand, pid)))

  def setsid = Process.send(:checked, Primitive.zr_proc_setsid)

  def groups = Process.send(:checked, Primitive.zr_proc_groups)

  # The group ids in a list identify groups by id or by name.
  def groups=(list)
    raise TypeError, "wrong argument type #{conversion_name(list)} (expected Array)" unless list.is_a?(Array)

    most = Process.send(:group_limit)
    raise ArgumentError, "too many groups, #{most} max" if list.size > most

    Process.send(:checked, Primitive.zr_proc_setgroups(list.map { |group| Process.send(:id_of, group, true) }))
    Process.send(:checked, Primitive.zr_proc_groups)
  end

  def initgroups(user, group)
    Process.send(:checked, Primitive.zr_proc_initgroups(Process.send(:c_string, user), Process.send(:id_of, group, true)))
    Process.send(:checked, Primitive.zr_proc_groups)
  end

  # The maximum number of groups that `groups=` takes: the value that
  # sysconf returns, until a program sets fewer.
  def maxgroups = Process.send(:group_limit)

  def maxgroups=(count)
    count = Integer.send(:int_operand, count)
    raise ArgumentError, "maxgroups #{count} should be positive" unless count.positive?

    limit = Primitive.zr_sysconf(SC_NGROUPS_MAX)
    count = [count, MAX_GROUPS].min
    count = [count, limit].min if limit&.positive?
    Primitive.zr_hidden_set(Process, :__maxgroups__, count)
    count
  end

  def setpgrp = Process.send(:checked, Primitive.zr_proc_setpgid(0, 0))

  # A resource's `[soft, hard]` limits.
  def getrlimit(resource)
    limits = Primitive.zr_proc_getrlimit(Process.send(:rlimit_resource, resource))
    raise SystemCallError.new(+"getrlimit", -limits) if limits.is_a?(Integer)

    limits.map { |limit| limit % 2**64 }
  end

  # A limit is a count or a name: INFINITY, SAVED_MAX or SAVED_CUR. The
  # hard limit is the soft one unless given.
  def setrlimit(resource, soft, hard = nil)
    soft = Process.send(:rlimit_value, soft)
    hard = hard.nil? ? soft : Process.send(:rlimit_value, hard)
    result = Primitive.zr_proc_setrlimit(Process.send(:rlimit_resource, resource), Process.send(:signed, soft), Process.send(:signed, hard))
    raise SystemCallError.new(+"setrlimit", -result) if result.negative?

    nil
  end

  def uid=(user)
    Process.send(:switching!, false)
    Process.send(:set_ids, false, Process.send(:id_of, user, false), -1)
    user
  end

  def gid=(group)
    Process.send(:switching!, true)
    id = Process.send(:id_of, group, true)
    Process.send(:set_ids, true, id, -1)
    id
  end

  def euid=(user)
    Process.send(:switching!, false)
    Process.send(:set_ids, false, -1, Process.send(:id_of, user, false))
    user
  end

  def egid=(group)
    Process.send(:switching!, true)
    Process.send(:set_ids, true, -1, Process.send(:id_of, group, true))
    group
  end

  # The name the program was started under, which `$0 =` leaves as it
  # was.
  def argv0 = Primitive.zr_program_name

  # The title that `ps` shows, written over the program's arguments.
  def setproctitle(title)
    Primitive.zr_proc_title_set(Process.send(:c_string, title))
    title
  end

  # A hint to settle the heap before forking workers: one collection.
  def warmup
    GC.start
    true
  end

  # A niceness is a number that can be negative, so the errno next to
  # it, not the return value, shows whether the call failed.
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

  # rb_f_kill: a negative signal goes to each process group. A signal
  # that this process sends to itself is handled before the call returns.
  def kill(*args)
    raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 2+)" if args.size < 2

    signal, *pids = args
    number = Primitive.zr_fixnum_p_m(signal) ? signal : Signal.send(:number, signal, negative: true)
    pids.map! { |pid| Integer.send(:int_operand, pid) }
    pids.map!(&:-@) if number.negative?
    result = Primitive.zr_proc_kill_all(pids, number.abs)
    raise SystemCallError.new(nil, -result) if result < 0

    pids.size
  end

  # rb_daemon where the platform has no daemon(3): the parent ends, and
  # the child leads a session of its own, in "/" unless `nochdir`, with
  # /dev/null as its standard streams unless `noclose`.
  def daemon(nochdir = nil, noclose = nil)
    Primitive.zr_exit_now(0) unless Process._fork.zero?
    Primitive.zr_proc_setsid
    Dir.chdir("/") unless nochdir
    unless noclose
      null = File.open(File::NULL, File::RDWR)
      [0, 1, 2].each { |fd| Primitive.zr_io_dup2(null.fileno, fd) }
      null.close
    end
    0
  end

  module_function :wait, :waitpid, :wait2, :waitpid2, :waitall, :ppid, :times, :kill, :daemon, :getpgrp, :getpgid,
                  :setpgid, :getsid, :setsid, :groups, :groups=, :initgroups, :maxgroups, :maxgroups=,
                  :setpgrp, :getpriority, :setpriority, :getrlimit, :setrlimit, :uid=, :gid=, :euid=,
                  :egid=, :argv0, :setproctitle, :warmup

  def self.exit(status = true) = Kernel.exit(status)

  def self.exit!(status = false) = Kernel.exit!(status)

  def self.abort(*args) = Kernel.abort(*args)

  def self.fork(&) = forked(&)

  def self.exec(*args, **options) = replaced(args, options)

  # The fork itself, which Kernel#fork reaches through a send, so a
  # program that wraps `_fork` sees every fork. The streams are written
  # out first, so the child does not write them again; in the child only
  # the thread that forked lives on.
  def self._fork
    $stdout.flush
    $stderr.flush
    pid = checked(Primitive.zr_proc_fork)
    if pid.zero?
      $$ = Primitive.zr_process_id
      Thread.send(:after_fork)
    end
    pid
  end

  # rb_call_proc__fork: `_fork` through a send, so a program that wraps
  # it sees every fork, and its result as a pid (NUM2PIDT). A wrapper
  # that raises in the child ends the child with the error, as
  # ruby_stop does; in the parent the error goes on up.
  def self.call_fork
    Primitive.attr! :hidden
    parent = Primitive.zr_process_id
    begin
      Integer.send(:int_operand, Process.__send__(:_fork))
    rescue Exception => e # rubocop:disable Lint/RescueException
      raise if Primitive.zr_process_id == parent

      Primitive.zr_proc_child_exit(e)
    end
  end

  # `fork`: the child's pid in the parent. In the child, nil, or with a
  # block the block runs and the child ends there. A `break`, `return` or
  # `throw` that leaves the block ends the child as an error at the call of
  # `fork`, as rb_protect around the block and error_handle do.
  def self.forked(&block)
    Primitive.attr! :hidden
    pid = call_fork
    return pid unless pid.zero?
    return nil unless block

    # The frames of `fork` are hidden, so the first is the call.
    site = caller_locations(0, 1).first
    Primitive.zr_proc_child_run(block, "#{site.path}:#{site.lineno}:in 'fork': ")
  end

  # The process becomes the command, with its environment and options
  # applied first; only a failure to start returns.
  def self.replaced(args, options)
    Primitive.attr! :hidden
    env, args, options = exec_args(args, options)
    words, argv0 = command_line(args)
    IO.send(:flush_std)
    redirects = Redirects.new(options)
    environment = environment(env, options)
    path = executable(words.first, search_path(env))
    argv = argv0 ? [argv0, *words.drop(1)] : words
    result = if path.nil? then -Errno::ENOENT::Errno
             else Primitive.zr_exec_with(path, argv, environment, redirects.to_a)
             end
    redirects.opened.each(&:close)
    raise SystemCallError.new(words.first, -result)
  end
  private_class_method :forked, :replaced, :call_fork

  # A result that is a failure raises as `rb_sys_fail(0)` does, with
  # no text added to the error's own message.
  def self.set_ids(group, real, effective)
    Primitive.attr! :hidden
    result = Primitive.zr_proc_setreid(group, real, effective)
    raise SystemCallError.new(nil, -result) if result.negative?
  end

  def self.set_id(call, id)
    Primitive.attr! :hidden
    result = Primitive.zr_os_setid(call, id)
    raise SystemCallError.new(nil, -result) if result.negative?
  end

  # A user (`group` false) or group as the id calls take it: a name
  # looks the id up, and anything else converts as C's unsigned int.
  def self.id_of(value, group)
    Primitive.attr! :hidden
    name = String.try_convert(value) unless Primitive.zr_fixnum_p_m(value)
    return unsigned(value, 32, "unsigned int") if name.nil?

    row = group ? Primitive.zr_gr_name(c_string(name)) : Primitive.zr_pw_name(c_string(name))
    raise ArgumentError, "can't find #{group ? 'group' : 'user'} for #{value}" if row.nil?

    row[2]
  end

  # `value` as C converts an unsigned argument of `bits`: through an
  # unsigned long, so a negative count wraps as a cast wraps it.
  def self.unsigned(value, bits, type)
    Primitive.attr! :hidden
    number = case value
             when Integer then value
             when Float
               raise RangeError, "float #{format('%-.10g', value)} out of range of integer" unless value > -2**63 - 1 && value < 2**64

               value.truncate
             else
               Integer.try_convert(value) || raise(TypeError, "no implicit conversion of #{conversion_name(value)} into Integer")
             end
    wide = bits == 64 ? type : +"unsigned long"
    # rb_big2ull: a magnitude past 64 bits is too big whatever its sign.
    raise RangeError, "bignum too big to convert into '#{wide}'" if number.abs >= 2**64
    raise RangeError, "bignum out of range of #{wide}" if number < -2**63
    return number % 2**64 if bits == 64

    raise RangeError, "integer #{number} too small to convert to '#{type}'" if number < -2**(bits - 1)
    raise RangeError, "integer #{number % 2**64} too big to convert to '#{type}'" if number % 2**64 >= 2**bits && number >= 0

    number % 2**bits
  end

  def self.signed(limit)
    Primitive.attr! :hidden
    limit >= 2**63 ? limit - 2**64 : limit
  end

  # A String as a C string takes it: one with a NUL byte has no end.
  def self.c_string(text)
    Primitive.attr! :hidden
    text = Primitive.zr_str_operand(text)
    raise ArgumentError, +"string contains null byte" if text.include?("\0")

    text
  end

  # A resource by its number, or by name as a Symbol or a String.
  def self.rlimit_resource(resource)
    Primitive.attr! :hidden
    name = resource.is_a?(Symbol) ? resource.name : (String.try_convert(resource) unless resource.is_a?(Integer))
    return Integer.send(:int_operand, resource) if name.nil?

    RLIMITS.fetch(c_string(name)) { raise ArgumentError, "invalid resource name: #{resource}" }
  end

  def self.rlimit_value(limit)
    Primitive.attr! :hidden
    name = limit.is_a?(Symbol) ? limit.name : (String.try_convert(limit) unless limit.is_a?(Integer))
    return unsigned(limit, 64, "unsigned long long") if name.nil?

    RLIM_NAMES.fetch(c_string(name)) { raise ArgumentError, "invalid resource value: #{limit}" }
  end

  def self.group_limit
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(Process, :__maxgroups__) || Primitive.zr_sysconf(SC_NGROUPS_MAX) || MAX_GROUPS
  end

  # While a block given to UID.switch or GID.switch runs, no id of that
  # kind may change.
  def self.switching!(group)
    Primitive.attr! :hidden
    return unless Primitive.zr_hidden_get(group ? GID : UID, :__switching__)

    raise RuntimeError, "can't handle #{group ? 'GID' : 'UID'} while evaluating block given to Process::UID.switch method"
  end

  private_class_method :set_ids, :set_id, :id_of, :unsigned, :signed, :c_string, :rlimit_resource, :rlimit_value,
                       :group_limit, :switching!

  # Runs the command; the child's pid, or nil when it could not start
  # (then `$?` says exit 127).
  # `rb_exec_getargs`: a trailing Hash is the options, written as
  # arguments rather than as keywords, and then a leading Hash is the
  # environment. A value with to_hash counts as a Hash, unless it is a
  # String or an Array, so env and options with no command raise.
  def self.exec_args(args, options)
    args = args.dup
    last = hash_argument(args.last) unless args.empty?
    args.pop if last
    options = options.merge(last) if last
    env = hash_argument(args.first) unless args.empty?
    args.shift if env
    [env, args, options]
  end

  # check_hash: an argument converts to a Hash unless it is a String, an
  # Array or an immediate, whose to_hash a spawn never calls.
  def self.hash_argument(arg)
    Primitive.attr! :hidden
    case arg
    when String, Array, Integer, Float, Symbol, nil, true, false then nil
    else Hash.try_convert(arg)
    end
  end
  private_class_method :hash_argument

  # The error of a command that did not start, named by its program as
  # rb_exec_fail names it: after the environment and options come off.
  # The error names what failed, as ruby's child reports it: the
  # `chdir:` directory when the child could not enter it, else the
  # command.
  def self.start_error(args, options, pid)
    _, args, options = exec_args(args, options)
    dir = options[:chdir] && (String.try_convert(options[:chdir]) || options[:chdir].to_path)
    SystemCallError.new(dir && !Primitive.zr_path_access(dir, 1) ? dir : command_words(args).first, -pid)
  end

  def self.spawn_command(args, options)
    env, args, options = exec_args(args, options)
    words, argv0 = command_line(args)
    IO.send(:flush_std)
    redirects = Redirects.new(options)
    search = search_path(env)
    # A child of its own argv[0], or one that searches its own PATH,
    # starts from the path found here.
    pid = if redirects.forked? || argv0 || search
            path = executable(words.first, search)
            argv = argv0 ? [argv0, *words.drop(1)] : words
            path ? forked_spawn(path, argv, environment(env, options), redirects) : -Errno::ENOENT::Errno
          else
            Primitive.zr_os_spawn(words, redirects.dups, redirects.closes, environment(env, options), redirects.chdir, redirects.close_others)
          end
    redirects.opened.each(&:close)
    Process.send(:status!, Status.new(0, 127 << 8)) if pid.negative?
    pid
  end

  def self.forked_spawn(path, words, env, redirects)
    Primitive.attr! :hidden
    Primitive.zr_spawn_forked(path, words, env, redirects.to_a)
  end

  # pty.c's establishShell: the command, or a login shell, on the far
  # end of a pty pair. The pid, or the negated errno the child could not
  # start with. It closes `slave` in this process, as establishShell does.
  def self.tty_spawn(args, master, slave)
    Primitive.attr! :hidden
    options = args.size > 1 && args.last.is_a?(Hash) ? args.pop : {}
    env, args, options = exec_args(args, options)
    words = command_words(args)
    IO.send(:flush_std)
    redirects = Redirects.new(options)
    path = executable(words.first)
    pid = path ? Primitive.zr_spawn_forked(path, words, environment(env, options), redirects.to_a << [master, slave]) : -Errno::ENOENT::Errno
    Primitive.zr_io_close(slave) unless path
    redirects.opened.each(&:close)
    pid
  end

  # The file that a command word runs: the word itself when it is a
  # path, else the first executable file of that name on PATH, as
  # execvp searches.
  def self.executable(word, search = nil)
    Primitive.attr! :hidden
    return word if word.include?("/")

    (search || ENV.fetch("PATH", "/usr/bin:/bin")).split(":", -1).each do |dir|
      path = File.join(dir.empty? ? "." : dir, word)
      return path if Primitive.zr_path_kind(path) == 2 && Primitive.zr_path_access(path, 1)
    end
    nil
  end

  # The program and its arguments. One string goes through the shell
  # when it contains shell syntax; a list is the argument vector itself.
  def self.command_words(args) = command_line(args).first

  # The words of the command, and the argv[0] that a [program, argv0]
  # pair gives, else nil.
  def self.command_line(args)
    raise ArgumentError, +"wrong number of arguments (given 0, expected 1+)" if args.empty?

    # rb_exec_getargs: a first argument with to_ary is [program, argv0],
    # exactly two Strings.
    first = args.first.is_a?(String) ? nil : Array.try_convert(args.first)
    if first
      raise ArgumentError, +"wrong first argument" unless first.size == 2

      first = first.map { |part| String.try_convert(part) or raise TypeError, "no implicit conversion of #{conversion_name(part)} into String" }
      raise ArgumentError, +"string contains null byte" if first[1].include?("\0")

      args = [[first[0]]] + args.drop(1)
    end
    words = args.size == 1 ? shell_words(args.first) : args.map { |arg| arg.is_a?(Array) ? arg.first : arg }
    words = words.map do |word|
      string = String.try_convert(word)
      raise TypeError, "no implicit conversion of #{conversion_name(word)} into String" if string.nil?

      string
    end
    words.each do |word|
      raise ArgumentError, +"string contains null byte" if word.include?("\0")
    end
    [words, first&.last]
  end

  # The PATH the child searches: the one its environment gives, else
  # this process's.
  def self.search_path(env)
    Primitive.attr! :hidden
    env.is_a?(Hash) && env.key?("PATH") ? env["PATH"] : nil
  end

  def self.shell_words(command)
    return [command.first] if command.is_a?(Array)

    text = String.try_convert(command)
    raise TypeError, "no implicit conversion of #{conversion_name(command)} into String" if text.nil?

    # The command is bytes to the shell: one that is not valid in its
    # encoding is read as bytes, as rb_exec_fillarg reads it.
    command = text.valid_encoding? ? text : text.b

    # An `=` inside the first word makes it an assignment, which only a
    # shell can do, as rb_exec_fillarg reads it.
    first = command.split(" ").first || +""
    # rb_exec_fillarg gives the shell its own name as argv[0], which is
    # the name that a shell puts in front of its own error messages, and
    # the spawn finds it on PATH.
    return [+"sh", +"-c", command] if command.each_char.any? { |c| SHELL_META.include?(c) } || Primitive.zr_table_member_p(SHELL_WORDS, first) || first.include?("=")

    words = command.split(" ")
    # A command of no words still gives a program: rb_exec_fillarg
    # leaves the name empty, and the exec of it returns ENOENT. An empty
    # list would give the spawn no program name to read.
    words.empty? ? [+""] : words
  end

  # The child's whole environment as "KEY=value" strings, or nil to
  # inherit the parent's.
  def self.environment(env, options)
    return nil if env.nil? && !options[:unsetenv_others]

    table = options[:unsetenv_others] ? {} : ENV.to_h
    env&.each do |key, value|
      key = String.try_convert(key) or raise TypeError, "no implicit conversion of #{conversion_name(key)} into String"
      # check_exec_env: no = in a name, and no NUL in a name or a value.
      raise ArgumentError, +"string contains null byte" if key.include?("\0")
      raise ArgumentError, "environment name contains a equal : #{key}" if key.include?("=")
      if value.nil?
        table.delete(key)
      else
        table[key] = String.try_convert(value) or raise TypeError, "no implicit conversion of #{conversion_name(value)} into String"
        raise ArgumentError, +"string contains null byte" if table[key].include?("\0")
      end
    end
    table.map { |key, value| "#{key}=#{value}" }
  end

  private_class_method :spawn_command, :start_error, :command_words, :command_line, :search_path, :shell_words, :environment, :exec_args, :executable, :forked_spawn, :tty_spawn
end

# The ids a process runs as. Process::Sys makes the system calls by
# their own names; Process::UID and Process::GID change the real,
# effective and saved ids together, the way CRuby does on darwin, and
# keep the saved id themselves where the system shows none.
module Process
  # How each kind of id is read and set: the ids zr_process_ids reads,
  # and the calls that set one id.
  ID_CALLS = {
    false => { real: 0, effective: 1, set: :setuid, set_real: :setruid, set_effective: :seteuid },
    true => { real: 2, effective: 3, set: :setgid, set_real: :setrgid, set_effective: :setegid }
  }.freeze
  private_constant :ID_CALLS

  module Sys
    def getuid = Primitive.zr_process_ids(0)
    def geteuid = Primitive.zr_process_ids(1)
    def getgid = Primitive.zr_process_ids(2)
    def getegid = Primitive.zr_process_ids(3)

    def setuid(user) = Process.send(:sys_set, :setuid, user, false)
    def setgid(group) = Process.send(:sys_set, :setgid, group, true)
    def setruid(user) = Process.send(:sys_set, :setruid, user, false)
    def setrgid(group) = Process.send(:sys_set, :setrgid, group, true)
    def seteuid(user) = Process.send(:sys_set, :seteuid, user, false)
    def setegid(group) = Process.send(:sys_set, :setegid, group, true)

    def setreuid(real, effective)
      Process.send(:switching!, false)
      Process.send(:set_ids, false, Process.send(:id_of, real, false), Process.send(:id_of, effective, false))
      nil
    end

    def setregid(real, effective)
      Process.send(:switching!, true)
      Process.send(:set_ids, true, Process.send(:id_of, real, true), Process.send(:id_of, effective, true))
      nil
    end

    def issetugid = Primitive.zr_os_issetugid

    # Darwin has no call that sets all three ids at once.
    Primitive.zr_define_notimplement(self, :setresuid)
    Primitive.zr_define_notimplement(self, :setresgid)

    module_function :getuid, :geteuid, :getgid, :getegid, :setuid, :setgid, :setruid, :setrgid, :seteuid,
                    :setegid, :setreuid, :setregid, :setresuid, :setresgid, :issetugid
  end

  module UID
    Primitive.zr_hidden_set(self, :__saved__, Primitive.zr_process_ids(1))

    def rid = Primitive.zr_process_ids(0)
    def eid = Primitive.zr_process_ids(1)
    def change_privilege(user) = Process.send(:change_privilege, user, false)
    def grant_privilege(user) = Process.send(:grant_privilege, user, false)

    # Darwin's setreuid cannot swap the two ids and keep the saved one.
    def re_exchangeable? = false

    def re_exchange
      Process.send(:switching!, false)
      raise NotImplementedError, +"re_exchange() function is unimplemented on this machine"
    end

    def sid_available? = true
    def switch(&) = Process.send(:switch, false, &)
    def from_name(name) = Process.send(:id_of, name, false)

    module_function :rid, :eid, :change_privilege, :grant_privilege, :re_exchangeable?, :re_exchange,
                    :sid_available?, :switch, :from_name

    class << self
      alias eid= grant_privilege
    end
  end

  module GID
    Primitive.zr_hidden_set(self, :__saved__, Primitive.zr_process_ids(3))

    def rid = Primitive.zr_process_ids(2)
    def eid = Primitive.zr_process_ids(3)
    def change_privilege(group) = Process.send(:change_privilege, group, true)
    def grant_privilege(group) = Process.send(:grant_privilege, group, true)

    # Darwin's setregid cannot swap the two ids and keep the saved one.
    def re_exchangeable? = false

    def re_exchange
      Process.send(:switching!, true)
      raise NotImplementedError, +"re_exchange() function is unimplemented on this machine"
    end

    def sid_available? = true
    def switch(&) = Process.send(:switch, true, &)
    def from_name(name) = Process.send(:id_of, name, true)

    module_function :rid, :eid, :change_privilege, :grant_privilege, :re_exchangeable?, :re_exchange,
                    :sid_available?, :switch, :from_name

    class << self
      alias eid= grant_privilege
    end
  end

  class << self
    private

    # `$?`: each thread keeps the status of the last child that it
    # waited for (rb_last_status_get). The kernel reads it here.
    def status
      Primitive.attr! :hidden
      Primitive.zr_hidden_get(Thread.current, :__last_status__)
    end

    def status!(status)
      Primitive.attr! :hidden
      Primitive.zr_hidden_set(Thread.current, :__last_status__, status)
    end

    def sys_set(call, value, group)
      Primitive.attr! :hidden
      switching!(group)
      set_id(call, id_of(value, group))
      nil
    end

    def saved_id(group)
      Primitive.attr! :hidden
      Primitive.zr_hidden_get(group ? GID : UID, :__saved__)
    end

    def save_id(group, id)
      Primitive.attr! :hidden
      Primitive.zr_hidden_set(group ? GID : UID, :__saved__, id)
    end

    # The real and effective ids become `value`: root sets all three at
    # once. Any other user changes them one at a time through the saved
    # id, which accepts only a value that the process already has.
    def change_privilege(value, group)
      Primitive.attr! :hidden
      switching!(group)
      id = id_of(value, group)
      calls = ID_CALLS[group]
      real = Primitive.zr_process_ids(calls[:real])
      effective = Primitive.zr_process_ids(calls[:effective])
      saved = saved_id(group)
      if Primitive.zr_process_ids(1).zero?
        set_id(calls[:set], id)
        save_id(group, id)
      elsif saved == id
        set_id(calls[:set_effective], id) if effective != id
        set_id(calls[:set_real], id) if real != id
      elsif effective == id && real != id
        set_id(calls[:set_real], id)
        save_id(group, id)
      elsif effective == id
        set_id(calls[:set_real], saved)
        save_id(group, id)
        set_id(calls[:set_real], id)
      elsif real == id
        set_id(calls[:set_effective], id)
        set_id(calls[:set_real], saved)
        save_id(group, id)
        set_id(calls[:set_real], id)
      else
        raise Errno::EPERM
      end
      value
    end

    def grant_privilege(value, group)
      Primitive.attr! :hidden
      id = id_of(value, group)
      switching!(group)
      set_id(ID_CALLS[group][:set_effective], id)
      value
    end

    # The effective id changes to the other of the real and saved ids;
    # with a block it changes back when the block is done.
    def switch(group)
      Primitive.attr! :hidden
      switching!(group)
      calls = ID_CALLS[group]
      real = Primitive.zr_process_ids(calls[:real])
      effective = Primitive.zr_process_ids(calls[:effective])
      saved = saved_id(group)
      if real != effective
        set_ids(group, -1, real)
        back = saved
        answer = effective
      elsif effective != saved
        set_ids(group, -1, saved)
        back = effective
        answer = real
      else
        raise Errno::EPERM
      end
      return answer unless block_given?

      holder = group ? GID : UID
      begin
        Primitive.zr_hidden_set(holder, :__switching__, true)
        yield
      ensure
        Primitive.zr_hidden_set(holder, :__switching__, false)
        set_id(calls[:set_effective], back)
      end
    end
  end
end


module Kernel
  # The process becomes the command; only a failure to start returns.
  def exec(*args, **options) = Process.send(:replaced, args, options)

  def fork(&) = Process.send(:forked, &)

  private :exec, :fork
  module_function :exec, :fork

  def spawn(*args, **options)
    pid = Process.send(:spawn_command, args, options)
    raise Process.send(:start_error, args, options, pid) if pid.negative?

    pid
  end

  def system(*args, exception: false, **options)
    pid = Process.send(:spawn_command, args, options)
    if pid.negative?
      raise Process.send(:start_error, args, options, pid) if exception

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

module Kernel
  # Darwin deprecates the raw system call, and ruby leaves it out.
  Primitive.zr_define_notimplement(self, :syscall)
  module_function :syscall
end
