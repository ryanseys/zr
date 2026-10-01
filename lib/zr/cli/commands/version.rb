# frozen_string_literal: true

require_relative "../command"
require_relative "../../version"

module Zr
  module CLI
    module Commands
      # `zr version`, `zr --version` and `zr -v`: zr's version and the ruby
      # version that it matches.
      class Version < Command
        def plain? = true

        def run(_argv) = puts("zr #{VERSION} (for ruby #{RUBY})")
      end
    end
  end
end
