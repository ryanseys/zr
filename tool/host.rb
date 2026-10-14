# frozen_string_literal: true

require_relative "lib/zr/dev"
require_relative "../lib/zr/machine/host/launch"

module Zr
  module Dev
    module Commands
      # `zr-dev host prog.rb [args]`: runs a program on CRuby, with no
      # build (lib/zr/machine/host/launch.rb). The exit status is the
      # program's.
      class Host < Command
        summary "Run a program on CRuby over zr's kernel, with no build"
        usage "<file.rb> [args...]"
        host_ruby!

        def options(o)
          o.stop_on_unknown if o.respond_to?(:stop_on_unknown)
        end

        def run(argv)
          path = argv.shift or fail!("give a Ruby file")
          unless Machine::Host.stacked?
            exec(Machine::Host::STACK, RbConfig.ruby, "--yjit", File.join(__dir__, "zr-dev.rb"), "host", path, *argv)
          end
          exit(Machine::Host.walk(path, argv) || 1)
        end
      end
    end
  end
end
