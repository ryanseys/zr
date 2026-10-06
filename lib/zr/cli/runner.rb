# frozen_string_literal: true

require "digest/sha2"
require "rbconfig"
require_relative "../gc_tuning"
require_relative "../paths"

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
      #
      # The program also starts in the directory that zr started in, when
      # zr had to build from another one (`keep_lost_cwd`).
      #: () -> Hash[String, String?]
      def program_env
        Dir.fchdir(@lost_cwd.fileno) if @lost_cwd # rubocop:disable ThreadSafety/ClassInstanceVariable
        env = GcTuning.program_env
        launcher = $PROGRAM_NAME
        return env unless File.basename(launcher) == "zr" && File.file?(launcher)

        env.merge("ZR_RUBY" => pinned_launcher(EXE))
      end

      # A ruby may start in a directory that is gone; its program finds
      # that out only when it asks for the directory. zr reads paths while
      # it builds, so it builds from "/" and keeps a handle on the lost
      # directory, which `program_env` goes back to.
      # It runs once, at the start, while zr has one thread.
      #: () -> void
      def keep_lost_cwd
        Dir.pwd
      rescue Errno::ENOENT
        # rubocop:disable ThreadSafety/ClassInstanceVariable, ThreadSafety/DirChdir
        @lost_cwd = Dir.new(".")
        Dir.chdir("/")
        # rubocop:enable ThreadSafety/ClassInstanceVariable, ThreadSafety/DirChdir
      end

      # The launcher that this copy of zr starts from.
      EXE = File.expand_path("../../../exe/zr", __dir__)

      # A ruby binary runs with any environment, so `RbConfig.ruby` names
      # one that does. `exe` starts with `#!/usr/bin/env ruby`, which needs
      # the PATH to find this ruby; its twin in the cache names this ruby
      # itself. One twin serves each pair of ruby and launcher. Without a
      # cache to write to, the launcher stands as it is.
      #: (String exe) -> String
      def pinned_launcher(exe)
        exe = File.realpath(exe)
        dir = File.join(Paths.cache, "launcher", Digest::SHA256.hexdigest("#{RbConfig.ruby}\0#{exe}")[0, 16])
        twin = File.join(dir, "zr")
        return twin if File.file?(twin)

        Paths.mkdir_p(dir)
        draft = "#{twin}.#{Process.pid}"
        File.write(draft, "#!#{RbConfig.ruby}\n# frozen_string_literal: true\n\nload #{exe.dump}\n", perm: 0o755)
        File.rename(draft, twin)
        twin
      rescue SystemCallError
        exe
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
