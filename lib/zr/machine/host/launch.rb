# frozen_string_literal: true

module Zr
  module Machine
    # How a hosted run starts: CRuby runs zr's kernel as Ruby, and the
    # walker runs the core library, the gem prelude and the program over
    # the kernel's heap (`Host::Walk`), with no build. `zr-dev host`, the
    # program tests with ZR_TEST_HOST=1 and the fuzzer start it so. The
    # file loads nothing until `walk`, so a caller that only starts ruby
    # again with `STACK` pays nothing.
    class Host
      # The walker and the kernel nest one Ruby frame in another for each
      # call of the program, so the VM stack must be as large as a zr
      # fiber's. A zr thread is a ruby fiber, and recurses as deep as the
      # main thread. ruby reads the sizes as it starts, and maps a stack's
      # pages as they are used.
      STACK = %w[RUBY_THREAD_VM_STACK_SIZE RUBY_THREAD_MACHINE_STACK_SIZE RUBY_FIBER_VM_STACK_SIZE RUBY_FIBER_MACHINE_STACK_SIZE]
              .to_h { |name| [name, (256 << 20).to_s] }.freeze

      # Whether this ruby started with `STACK`.
      #: () -> bool
      def self.stacked? = STACK.all? { |name, value| ENV[name] == value }

      # Runs the program at `path` with `argv` on the walker, in a thread,
      # whose stacks `STACK` sizes. Returns the program's exit status.
      #: (String path, Array[String] argv) -> Integer?
      def self.walk(path, argv)
        require_relative "../../runtime"
        require_relative "walk"
        status = nil #: Integer?
        Thread.new { status = Walk.new.main(path, argv) }.join
        $stdout.flush
        status
      end
    end
  end
end
