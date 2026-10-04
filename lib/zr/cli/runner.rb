# frozen_string_literal: true

require_relative "../gc_tuning"

module Zr
  module CLI
    # Runs the binary that `zr run` built, and ends zr as the program ended.
    module Runner
      module_function

      # Runs a binary with the arguments after the program's path, and
      # returns its status. A Ctrl-C goes to the program, which decides what
      # to do with it; zr waits for the program to end.
      #: (String binary, Array[String] rest) -> Process::Status
      def run_binary(binary, rest)
        interrupt = Signal.trap("INT") { nil }
        # `[binary, binary]`: with no arguments, a lone string would be a
        # command for the shell.
        system(program_env, [binary, binary], *rest)
        Signal.trap("INT", interrupt)
        # `system` sets `$?` also when the binary does not start.
        $? #: Process::Status
      end

      # The environment changes for a program that zr runs: the collector
      # limits that zr set for itself go (`GcTuning.program_env`), and
      # `ZR_RUBY` names this `zr`, so the program's `RbConfig.ruby` is the zr
      # that ran it (lib/zr/runtime/ext/rbconfig.rb), as a ruby program's is
      # the ruby that ran it.
      #: () -> Hash[String, String?]
      def program_env
        env = GcTuning.program_env
        launcher = $PROGRAM_NAME
        return env unless File.basename(launcher) == "zr" && File.file?(launcher)

        env.merge("ZR_RUBY" => File.realpath(launcher))
      end

      # The end of `zr run`, once the build is gone: the program's status.
      # A signal that stopped the program stops zr too, so the shell sees
      # the status that ruby gives when the signal stops it.
      #: (Process::Status status) -> bot
      def exit_as(status)
        code = status.exitstatus
        exit(code) if code

        # A status with no exit code is signaled, and has a signal number.
        signo = status.termsig #: Integer
        # SIGKILL and SIGSTOP keep their default action, and trap refuses them.
        begin
          Signal.trap(signo, "SYSTEM_DEFAULT") unless [Signal.list["KILL"], Signal.list["STOP"]].include?(signo)
        rescue ArgumentError
          # ruby keeps SIGSEGV, SIGBUS, SIGILL, SIGFPE and SIGVTALRM for
          # itself, and its own handler would print a ruby bug report. The
          # C library's `signal` sets the default action again. Without
          # Fiddle (a zr binary), zr exits with the status that a shell
          # gives for the signal.
          exit(128 + signo) unless default_action!(signo)
        end
        Process.kill(signo, Process.pid)
        # Only a signal that does not stop a process by default comes here.
        sleep 1
        exit(128 + signo)
      end

      # `signal(signo, SIG_DFL)` through Fiddle. Returns whether it was set.
      #: (Integer signo) -> bool
      def default_action!(signo)
        require "fiddle"
        set = ::Fiddle::Function.new(::Fiddle::Handle::DEFAULT["signal"], [::Fiddle::TYPE_INT, ::Fiddle::TYPE_VOIDP], ::Fiddle::TYPE_VOIDP)
        set.call(signo, 0)
        true
      rescue LoadError, StandardError
        false
      end
    end
  end
end
