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
      def run_binary(binary, rest)
        interrupt = Signal.trap("INT") { nil }
        # `[binary, binary]`: with no arguments, a lone string would be a
        # command for the shell.
        system(GcTuning.program_env, [binary, binary], *rest)
        Signal.trap("INT", interrupt)
        $?
      end

      # The end of `zr run`, once the build is gone: the program's status.
      # A signal that stopped the program stops zr too, so the shell sees
      # the status that ruby gives when the signal stops it.
      def exit_as(status)
        exit(status.exitstatus) unless status.signaled?

        begin
          Signal.trap(status.termsig, "SYSTEM_DEFAULT")
        rescue ArgumentError
          # ruby keeps SIGSEGV, SIGBUS, SIGILL, SIGFPE and SIGVTALRM for
          # itself, and its own handler would print a ruby bug report. The
          # C library's `signal` sets the default action again. Without
          # Fiddle (a zr binary), zr exits with the status that a shell
          # gives for the signal.
          exit(128 + status.termsig) unless default_action!(status.termsig)
        end
        Process.kill(status.termsig, Process.pid)
        # Only a signal that does not stop a process by default comes here.
        sleep 1
        exit(128 + status.termsig)
      end

      # `signal(signo, SIG_DFL)` through Fiddle. Returns whether it was set.
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
