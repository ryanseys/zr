# frozen_string_literal: true

require "digest/sha2"
require "rbconfig"
require_relative "../gc_tuning"
require_relative "../paths"

module Zr
  module CLI
    # Runs the binary that `zr run` built, and ends zr as the program ended.
    module Runner
      # @rbs @lost_cwd: Dir?

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
      # the ruby that ran it. `ZR_HOME` names this zr's ruby tree, which the
      # program's RbConfig and $LOAD_PATH take as their prefix, as a ruby
      # program's are the prefix of the ruby that ran it.
      #
      # The program also starts in the directory that zr started in, when
      # zr had to build from another one (`keep_lost_cwd`).
      #: () -> Hash[String, String?]
      def program_env
        lost = @lost_cwd # rubocop:disable ThreadSafety/ClassInstanceVariable
        Dir.fchdir(lost.fileno) if lost
        # zr read RUBYOPT as it built the program (lib/zr/runtime/core/rubyopt.rb).
        env = GcTuning.program_env.merge("ZR_RUBYOPT_READ" => "1")
        launcher = $PROGRAM_NAME
        name = File.basename(launcher)
        return env unless %w[zr ruby].include?(name) && File.file?(launcher)

        env.merge("ZR_RUBY" => pinned_launcher(EXE, name: name), "ZR_HOME" => HOME)
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

      # This copy of zr's ruby tree: the standard library and the bundled
      # gems, laid out as an installed ruby's prefix. Its real path, as ruby
      # gives its own prefix.
      HOME = File.realpath(File.expand_path("../../../vendor/ruby", __dir__))

      # A ruby binary runs with any environment, so `RbConfig.ruby` names
      # one that does. `exe` starts with `#!/usr/bin/env ruby`, which needs
      # the PATH to find a ruby; its twin in the cache names `ruby` itself.
      # The twin is the zr that ran the program, so it keeps zr's own cache
      # directory, as a flag: the program's environment stays the
      # program's. One twin serves each ruby, launcher, cache and name.
      # Without a cache to write to, the launcher stands as it is. A twin
      # whose bytes are not the ones zr writes is written again, so a
      # file that another hand put in the cache does not run. Named
      # `ruby`, zr acts as ruby where its own CLI differs (`--version`).
      # Under RUBY_BOX, the ruby that runs zr makes boxes of its own; its
      # `#!` line keeps that ruby from printing their notice, which the
      # program prints (`Ruby::Box.notice`).
      #: (String exe, ?ruby: String, ?flags: Array[String], ?name: String) -> String
      def pinned_launcher(exe, ruby: RbConfig.ruby, flags: pinned_flags, name: "zr")
        exe = File.realpath(exe)
        cache = Paths.cache or return exe
        key = Digest::SHA256.hexdigest([SHEBANG, ruby, exe, *flags, name].join("\0"))[0, 16] #: String
        dir = File.join(cache, "launcher", key)
        twin = File.join(dir, name)
        text = twin_text(exe, ruby, flags)
        return twin if File.file?(twin) && File.binread(twin) == text

        Paths.mkdir_p(dir)
        draft = "#{twin}.#{Process.pid}"
        # The mode of a new file is less the umask.
        File.open(draft, "w", 0o755) { |file| file.write(text) }
        File.rename(draft, twin)
        twin
      rescue SystemCallError
        exe
      end

      # The one flag of a twin's `#!` line.
      SHEBANG = "-W:no-experimental"

      # The bytes of the twin of `exe` for `ruby` and `flags`.
      #: (String exe, String ruby, Array[String] flags) -> String
      def twin_text(exe, ruby, flags)
        given = "ARGV.unshift(#{flags.map(&:dump).join(", ")})\n" unless flags.empty?
        "#!#{ruby} #{SHEBANG}\n# frozen_string_literal: true\n\n#{given}load #{exe.dump}\n".b
      end

      # The settings that the twin keeps: a cache directory zr was given.
      #: () -> Array[String]
      def pinned_flags
        cache = Config.current.cache
        cache ? ["--cache-dir=#{File.expand_path(cache)}"] : []
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
