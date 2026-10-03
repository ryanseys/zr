# frozen_string_literal: true

require_relative "../command"
require_relative "../help"

module Zr
  module CLI
    module Commands
      # `zr help [<command>]`, `zr -h` and `zr --help`: the commands of zr,
      # or the page of one command.
      #
      # In `Commands`, `Help` names this class: the words are `CLI::Help`.
      class Help < Command
        #: (Array[String] argv) -> void
        def run(argv) = CLI::Help.show(argv.first)
      end
    end
  end
end
