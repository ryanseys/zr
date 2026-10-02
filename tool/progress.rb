# frozen_string_literal: true

require_relative "lib/zr/dev"

module Zr
  module Dev
    # Prints where the tier that runs now stands, or where the last one
    # stood. A reporter of the test run writes the file
    # (`test/support/progress.rb`).
    class Progress < Command
      summary "Where the test tier running now stands, or the last one stood"

      def run(_argv)
        require_relative "../test/support/progress"
        puts(Test::Progress.read || "no tier has run yet")
      end
    end
  end
end
