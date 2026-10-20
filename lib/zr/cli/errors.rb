# frozen_string_literal: true

require_relative "../error"

module Zr
  module CLI
    # What `zr` prints, and the status that it exits with, for an error: a
    # wrong command line (`usage_error`) and an error that escapes a command
    # (`guard`).
    module Errors
      # The errors that say what the user must change, not a defect in zr.
      # They print their message only. Named as strings: not every command
      # loads the file that defines each one.
      EXPECTED = %w[Zr::Config::Invalid Zr::SourceChanged Zr::GemSet::Unresolved Zr::Paths::Missing Zr::Paths::Untrusted
                    Zr::TargetRefused Zr::InvalidProgram Zr::BuildError].freeze
      # The expected errors of a setting or a cache that the user must
      # change before any build: status 2, as a usage error.
      SETUP = %w[Zr::Config::Invalid Zr::Paths::Untrusted].freeze
      # The errors of a directory that zr cannot write to or that is full.
      UNWRITABLE = %w[EACCES EROFS ENOSPC EPERM].freeze
      # Exit status 70 (EX_SOFTWARE): an error that zr did not expect, a
      # defect in zr, apart from status 1 for an error the user can fix.
      DEFECT = 70
      # The errors that `guard` reports. Exception is never one: SystemExit
      # and the signals (SignalException) go through.
      CAUGHT = [StandardError, ScriptError, SystemStackError, NoMemoryError, SecurityError].freeze

      module_function

      # Runs the command, and turns an error that escapes it into one line
      # and an exit status (`status`): 130 for Ctrl-C. An error that zr did
      # not expect is a defect: the line says so, names zr's version and
      # where to report it, and writes a crash log. --backtrace or
      # ZR_DEBUG=1 shows the backtrace.
      #: [T] () { () -> T } -> T
      def guard
        yield
      rescue Interrupt
        # The `ensure` clauses of the build have removed its temp files.
        exit 130
      rescue *CAUGHT => e
        raise if Config.debug?

        exit report(e)
      end

      # Prints the line for `error`, and returns the status to exit with.
      #: (Exception error) -> Integer
      def report(error)
        status = status(error)
        warn "zr: #{error_line(error, (crash_log(error) if status == DEFECT))}"
        status
      end

      # 2 for a bad setting or an unsafe cache, 1 for another error that
      # the user can fix (each `Zr::Error`), DEFECT for any other error.
      #: (Exception error) -> Integer
      def status(error)
        return 2 if SETUP.include?(error.class.name)
        return 1 if EXPECTED.include?(error.class.name) || error.is_a?(Zr::Error) || error.is_a?(SystemCallError)

        DEFECT
      end

      # The line that `guard` prints for `error`. `log` is the crash log
      # of a defect.
      #: (Exception error, ?String? log) -> String
      def error_line(error, log = nil)
        return error.message if EXPECTED.include?(error.class.name) || error.is_a?(Zr::Error)
        return "#{error.message}#{cache_hint(error)}" if error.is_a?(SystemCallError)

        report = log ? "the crash log #{log}" : "the output of 'zr doctor'"
        "internal error: #{error.class}: #{error.message}. This is a defect in zr (#{about}). Report it at #{ISSUES_URL} " \
          "with #{report}. Run zr --backtrace (or set ZR_DEBUG=1) to see the backtrace."
      end

      # zr's version, the ruby that runs it, and the host.
      #: () -> String
      def about
        "zr #{VERSION}, ruby #{RUBY_VERSION}, #{Target.host_triple}"
      rescue StandardError
        "zr #{VERSION}, ruby #{RUBY_VERSION}"
      end

      # Days that a crash log stays in the cache (Cache::Janitor).
      CRASH_DAYS = 30

      # Writes what a report of a defect needs into `<cache>/crash/`, and
      # returns the log's path, or nil when it cannot. It names the `ZR_*`
      # variables that are set, not their values, which can hold paths and
      # secrets. It never raises: the error that it logs comes first.
      #: (Exception error) -> String?
      def crash_log(error)
        dir = File.join(Paths.cache, "crash")
        Paths.mkdir_p(dir, 0o700)
        path = File.join(dir, "#{Time.now.utc.strftime("%Y%m%dT%H%M%SZ")}-#{Process.pid}.log")
        File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(crash_text(error)) }
        path
      rescue Exception # rubocop:disable Lint/RescueException -- a log that fails must not hide the error
        nil
      end

      #: (Exception error) -> String
      def crash_text(error)
        lines = [Commands::Version::LINE, RUBY_DESCRIPTION, "host: #{Target.host_triple}", "zr: #{Paths::ROOT}",
                 "argv: #{ARGV.inspect}", "cwd: #{Dir.pwd}", "settings: #{Config.given.inspect}",
                 "set: #{ENV.keys.grep(/\AZR_/).sort.join(" ")}", ""]
        errors = [error] #: Array[Exception]
        while (cause = errors.last&.cause)
          errors << cause
        end
        errors.each_with_index do |each, at|
          lines << "Caused by:" if at.positive?
          lines << "#{each.class}: #{each.message}"
          lines.concat((each.backtrace || []).map { |line| "\tfrom #{line}" })
        end
        "#{lines.join("\n")}\n"
      end

      # For an error that writing into zr's cache gave, how to fix it.
      #: (SystemCallError error) -> String
      def cache_hint(error)
        return "" unless UNWRITABLE.any? { |name| Errno.const_get(name) === error }

        dirs = [Config.current.cache, Paths.user_cache, File.join(Paths::ROOT, "tmp/cache")].compact
        return "" unless dirs.any? { |dir| error.message.include?(dir) }

        ". Set XDG_CACHE_HOME (or ZR_CACHE) to a directory that you can write to, or run 'zr cache clean'"
      rescue StandardError
        ""
      end

      # The input that the command names is not a file: a usage error,
      # status 2.
      #: (String? path) -> void
      def file!(path)
        return if path && File.file?(path)

        warn "zr: no such file: #{path}"
        exit 2
      end

      # One line that says what is wrong, and where to find help.
      #: (String message, ?String? command) -> bot
      def usage_error(message, command = nil)
        warn "zr#{" #{command}" if command}: #{message}"
        warn "Run 'zr help#{" #{command}" if command}' for usage."
        exit 2
      end
    end
  end
end
