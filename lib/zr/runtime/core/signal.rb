# frozen_string_literal: true

# Signals and their handlers. The kernel counts a signal as it comes,
# and the program runs the handler at its next safe point, as CRuby's
# sighandler and rb_signal_exec split the work. Each signal keeps the
# command trap was last given for it.
module Signal
  # How the system handles a signal, with the kernel's name for it.
  SYSTEM_DEFAULT = 0
  IGNORED = 1
  HANDLED = 2
  DROPPED = 3
  # The system can deliver these only to the thread that faults, or
  # ruby itself uses them.
  RESERVED = %w[SEGV BUS ILL FPE VTALRM].to_h { |name| [LIST.fetch(name), name] }.freeze
  # The signals whose default handler raises SignalException in the
  # main thread. SIGINT raises Interrupt instead.
  RAISING = %w[HUP QUIT TERM ALRM USR1 USR2].map { |name| LIST.fetch(name) }.freeze
  INT = LIST.fetch("INT")
  # A command trap was never given, or DEFAULT put back.
  UNSET = Object.new.freeze
  private_constant :SYSTEM_DEFAULT, :IGNORED, :HANDLED, :DROPPED, :RESERVED, :RAISING, :INT, :UNSET

  def list = LIST.dup

  def signame(number)
    number = Primitive.zr_index_operand_m(number)
    LIST.key(number)&.dup
  end

  def trap(*args, &block) = Signal.send(:trap_signal, args, block)

  module_function :list, :signame, :trap

  class << self
    private

    # sig_trap: the signal, then the command, or the block as the
    # command. Returns the signal's previous handler.
    def trap_signal(args, block)
      Primitive.attr! :hidden
      raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 1..2)" unless args.size.between?(1, 2)

      signo = trap_number(args[0])
      raise ArgumentError, "can't trap reserved signal: SIG#{RESERVED[signo]}" if RESERVED.key?(signo)

      if args.size == 1
        raise ArgumentError, +"tried to create Proc object without a block" unless block

        install(signo, HANDLED, block)
      else
        install(signo, *handling(args[1], signo))
      end
    end

    # trap_signm: a number below NSIG, or a name EXIT among them.
    def trap_number(signal)
      Primitive.attr! :hidden
      # A Bignum is no number here; it is read as a name.
      return number(signal, exit: true) unless signal.is_a?(Integer) && signal.bit_length < 63
      raise ArgumentError, "invalid signal number (#{signal})" unless signal.between?(0, 31)

      signal
    end

    # signm2signo: a Symbol or a String is a signal's name, with or
    # without its SIG prefix; a leading minus, where the caller allows
    # one, negates the number.
    def number(signal, negative: false, exit: false)
      Primitive.attr! :hidden
      name = signal.is_a?(Symbol) ? signal.name : String.try_convert(signal)
      raise ArgumentError, "bad signal type #{signal.class}" if name.nil?
      raise Encoding::CompatibilityError, "ASCII incompatible encoding: #{name.encoding}" unless name.encoding.ascii_compatible?
      raise ArgumentError, +"signal name with null byte" if name.include?("\0")

      minus = name.start_with?("-")
      raise ArgumentError, "negative signal name: #{name}" if minus && !negative

      bare = (minus ? name[1..] : name).delete_prefix("SIG")
      signo = LIST[bare] unless bare.empty? || (bare == +"EXIT" && !exit)
      raise ArgumentError, "unsupported signal 'SIG#{bare}'" if signo.nil?

      minus ? -signo : signo
    end

    # trap_handler: the command a String or a Symbol spells, and how the
    # system handles the signal for it.
    def handling(command, signo)
      Primitive.attr! :hidden
      return [IGNORED, nil] if command.nil?

      text = command.is_a?(Symbol) ? command.name : String.try_convert(command)
      return [HANDLED, command] if text.nil?

      case text
      when "", "IGNORE", "SIG_IGN" then [IGNORED, true]
      when "DEFAULT", "SIG_DFL" then [default_handling(signo), UNSET]
      when "SYSTEM_DEFAULT" then [SYSTEM_DEFAULT, UNSET]
      when "EXIT" then [HANDLED, :exit]
      else [HANDLED, text]
      end
    end

    # The handling ruby starts a signal with.
    def default_handling(signo)
      Primitive.attr! :hidden
      case Signal.signame(signo)
      when "INT", "HUP", "QUIT", "TERM", "ALRM", "USR1", "USR2", "CHLD" then HANDLED
      when "PIPE", "SYS" then DROPPED
      else SYSTEM_DEFAULT
      end
    end

    # trap: the new handling in place, and the old one described.
    def install(signo, how, command)
      Primitive.attr! :hidden
      unless signo.zero?
        was = Primitive.zr_trap_handle(signo, how)
        raise SystemCallError.new("SIG#{Signal.signame(signo)}", -was) if was.negative?
      end
      old = commands.fetch(signo, UNSET)
      if command.equal?(UNSET)
        commands.delete(signo)
      else
        commands[signo] = command
      end
      return +"EXIT" if old == :exit
      return old unless old.equal?(UNSET) || old == true

      case was
      when IGNORED then +"IGNORE"
      when SYSTEM_DEFAULT then +"SYSTEM_DEFAULT"
      when HANDLED then +"DEFAULT"
      end
    end

    def commands
      Primitive.attr! :hidden
      Primitive.zr_hidden_get(self, :__commands__) || Primitive.zr_hidden_set(self, :__commands__, {})
    end

    # A safe point: every signal that came runs its command. A signal
    # that comes while a command runs waits for it to end, and one that
    # comes while the scheduler changes its lists waits for the next safe
    # point: a block that the scheduler's own loops call is one, and a
    # command run there would change those lists under them.
    def deliver
      Primitive.attr! :hidden
      return nil if Primitive.zr_hidden_get(self, :__delivering__) || Thread.send(:busy?)
      # The commands run in the main thread, as rb_signal_exec runs them:
      # another thread that reaches a safe point wakes it.
      return Thread.main.send(:signalled) unless Thread.current.equal?(Thread.main)

      Primitive.zr_hidden_set(self, :__delivering__, true)
      begin
        while (signo = Primitive.zr_trap_next)
          run(signo)
        end
      ensure
        Primitive.zr_hidden_set(self, :__delivering__, false)
      end
      nil
    end

    # rb_signal_exec: ruby's own handler raises in the main thread; a
    # command runs with the signal's number.
    def run(signo)
      Primitive.attr! :hidden
      command = commands.fetch(signo, UNSET)
      if command.equal?(UNSET)
        if signo == INT
          interrupt(Interrupt.new(+""))
        elsif Primitive.zr_table_member_p(RAISING, signo)
          interrupt(SignalException.new(signo))
        end
      elsif command == :exit
        interrupt(SystemExit.new(+"exit"))
      else
        execute(command, signo)
      end
    end

    # signal_exec: an immediate value does nothing, a String is Ruby to
    # run in the scope that the signal interrupted, at its file and line,
    # with main as self, and anything else is called.
    # While the command runs, its thread is in trap context
    # (TRAP_INTERRUPT_MASK), where Mutex#lock refuses to wait.
    def execute(command, signo)
      Primitive.attr! :hidden
      return if Primitive.zr_special_p_m(command)

      was = Primitive.zr_hidden_get(self, :__trap_thread__)
      Primitive.zr_hidden_set(self, :__trap_thread__, Thread.current)
      begin
        command.is_a?(String) ? evaluate(command) : command.call(signo)
      ensure
        Primitive.zr_hidden_set(self, :__trap_thread__, was)
      end
    end

    def evaluate(command)
      Primitive.attr! :hidden
      scope = Primitive.zr_trap_binding(TOPLEVEL_BINDING.receiver)
      return TOPLEVEL_BINDING.send(:eval, command) if scope.nil?

      file, line = scope.source_location
      scope.eval(command, file, line)
    end

    # Whether the current thread runs a trap command.
    def trap_context?
      Primitive.attr! :hidden
      trapping = Primitive.zr_hidden_get(self, :__trap_thread__)
      !trapping.nil? && trapping.equal?(Thread.current)
    end

    # rb_threadptr_signal_raise: the main thread's handle_interrupt masks
    # may hold the exception back. Else it rises where the signal
    # interrupted the main thread, which runs this, so its backtrace has
    # no frame of the delivery.
    def interrupt(exception)
      Primitive.attr! :hidden
      main = Thread.main
      raise exception if main.equal?(Thread.current) && !main.send(:masked?, exception)

      main.raise(exception)
    end

    # The EXIT trap, run once as the program ends and before its at_exit
    # handlers. A signal that comes while it runs waits, as in any trap
    # (TRAP_INTERRUPT_MASK), until the first handler starts.
    def exit_trap
      Primitive.attr! :hidden
      return nil unless commands.key?(0)

      Primitive.zr_hidden_set(self, :__delivering__, true)
      begin
        execute(commands.delete(0), 0)
      ensure
        Primitive.zr_hidden_set(self, :__delivering__, false)
      end
      nil
    end
  end

  # Ruby's own handlers, in place as the program starts. A signal the
  # program was started with ignored stays ignored, as
  # install_sighandler leaves it.
  %w[INT HUP QUIT TERM ALRM USR1 USR2 CHLD PIPE SYS].each do |name|
    signo = LIST.fetch(name)
    was = Primitive.zr_trap_handle(signo, default_handling(signo))
    Primitive.zr_trap_handle(signo, was) unless was == SYSTEM_DEFAULT
  end
  # SIGVTALRM, which ruby's timer thread uses, is caught and dropped
  # (ruby_posix_signal in Init_native_thread), so it ends no process.
  Primitive.zr_trap_handle(LIST["VTALRM"], DROPPED) if LIST.key?("VTALRM")
end

module Kernel
  def trap(*args, &block) = Signal.send(:trap_signal, args, block)
  private :trap
end
