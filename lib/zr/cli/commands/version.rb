# frozen_string_literal: true

require_relative "../command"
require_relative "../../version"

module Zr
  module CLI
    module Commands
      # `zr version` and `zr --version`: zr's version and the ruby version
      # that it matches. `zr -v` is ruby's -v (`Compile#ruby`).
      class Version < Command
        LINE = "zr #{VERSION} (for ruby #{RUBY_PIN})".freeze

        #: () -> bool
        def plain? = true

        #: (Array[String] _argv) -> void
        def run(_argv) = puts(LINE)
      end
    end
  end
end
