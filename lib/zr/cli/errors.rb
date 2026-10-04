# frozen_string_literal: true

module Zr
  module CLI
    # What `zr` prints, and the status that it exits with, for an error: a
    # wrong command line (`usage_error`) and an error that escapes a command
    # (`guard`).
    module Errors
      # The errors that say what the user must change, not a defect in zr.
      # They print their message only. Named as strings: not every command
      # loads the file that defines each one.
      EXPECTED = %w[Zr::Config::Invalid Zr::SourceChanged Zr::GemSet::Unresolved Zr::Paths::Missing].freeze
      # The errors of a directory that zr cannot write to or that is full.
      UNWRITABLE = %w[EACCES EROFS ENOSPC EPERM].freeze

      module_function

      # Runs the command, and turns an error that escapes it into one line
      # and an exit status: 130 for Ctrl-C, 2 for a bad setting, 1 for any
      # other error. An error that zr did not expect is a defect: the line
      # says so and where to report it. --backtrace or ZR_DEBUG=1 shows the backtrace.
      #: [T] () { () -> T } -> T
      def guard
        yield
      rescue Interrupt
        # The `ensure` clauses of the build have removed its temp files.
        exit 130
      rescue StandardError => e
        raise if Config.debug?

        warn "zr: #{error_line(e)}"
        exit(e.is_a?(Config::Invalid) ? 2 : 1)
      end

      # The line that `guard` prints for `error`.
      #: (StandardError error) -> String
      def error_line(error)
        return error.message if EXPECTED.include?(error.class.name)
        return "#{error.message}#{cache_hint(error)}" if error.is_a?(SystemCallError)

        "internal error: #{error.class}: #{error.message}. This is a defect in zr. Report it at #{ISSUES_URL} " \
          "with the output of 'zr doctor'. Run zr --backtrace (or set ZR_DEBUG=1) to see the backtrace."
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
