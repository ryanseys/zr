# frozen_string_literal: true

require_relative "lib/zr/dev"

module Zr
  module Dev
    # `zr-dev host prog.rb [args]`: runs a program on CRuby, with no build
    # (A7). The kernel runs as Ruby (`Machine::Host`), and the walker runs
    # the core library, the gem prelude and the program over the kernel's
    # heap (`Machine::Host::Walk`). The exit status is the program's.
    class Hosted < Command
      summary "Run a program on CRuby over zr's kernel, with no build"
      usage "<file.rb> [args...]"
      host_ruby!

      # The walker and the kernel nest one Ruby frame in another for each
      # call of the program, so the VM stack must be as large as a zr
      # fiber's. ruby reads the size at its start.
      STACK = { "RUBY_THREAD_VM_STACK_SIZE" => (256 << 20).to_s, "RUBY_THREAD_MACHINE_STACK_SIZE" => (256 << 20).to_s,
                "RUBY_FIBER_VM_STACK_SIZE" => (64 << 20).to_s, "RUBY_FIBER_MACHINE_STACK_SIZE" => (64 << 20).to_s }.freeze

      def options(o)
        o.stop_on_unknown if o.respond_to?(:stop_on_unknown)
      end

      def run(argv)
        path = argv.shift or fail!("give a Ruby file")
        unless STACK.all? { |name, value| ENV[name] == value }
          exec(STACK, RbConfig.ruby, "--yjit", File.join(__dir__, "zr-dev.rb"), "host", path, *argv)
        end
        require_relative "../lib/zr/runtime"
        require_relative "../lib/zr/machine/host/walk"
        status = nil
        Thread.new { status = Machine::Host::Walk.new.main(path, argv) }.join
        $stdout.flush
        exit(status)
      end
    end
  end
end
