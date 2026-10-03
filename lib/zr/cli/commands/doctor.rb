# frozen_string_literal: true

require_relative "../command"

module Zr
  module CLI
    module Commands
      # `zr doctor`: checks what zr needs on this host (lib/zr/doctor.rb).
      # Exits with status 1 if a check fails.
      class Doctor < Command
        #: () -> bool
        def plain? = true

        #: (Array[String] _argv) -> void
        def run(_argv)
          require_relative "../../doctor"
          exit(Zr::Doctor.run ? 0 : 1)
        end
      end
    end
  end
end
