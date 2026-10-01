# frozen_string_literal: true

require_relative "lib/zr/dev"

module Zr
  module Dev
    # `zr-dev typecheck`: Steep checks the files that the Steepfile names.
    # They carry inline RBS annotations, or have their types in sig/pilot.
    # The rest of lib/ is not checked yet. See CONTRIBUTING.md.
    #
    #   zr-dev typecheck                check the files of the Steepfile
    #   zr-dev typecheck FILE...        check only these files
    #
    # It runs the Steep of this checkout's bundle (Gemfile.lock), not a
    # Steep that is installed elsewhere. It stops with status 1 when Steep
    # reports an error.
    class Typecheck < Command
      summary "Check the types of the files in the Steepfile (Steep)"
      usage "[FILE...]"
      host_ruby!

      STEEPFILE = Dev.path("Steepfile")

      # Steep runs in a child ruby through its binstub, which sets up the
      # bundle.
      def run(argv)
        ok = system(Dev.ruby, Dev.path("bin/steep"), "check", "--steepfile=#{STEEPFILE}", *argv, chdir: ROOT)
        fail!("Steep is not available; run `bundle install`") if ok.nil?
        fail!("Steep found type errors (exit status #{$?.exitstatus})") unless ok
      end
    end
  end
end
