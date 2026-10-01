# frozen_string_literal: true

verbose, $VERBOSE = $VERBOSE, nil
require "continuation" # ruby warns that callcc is obsolete
$VERBOSE = verbose
require_relative "../host"
require_relative "../../runtime_sources"
require_relative "../../target"

module Zr
  module Machine
    class Host
      # The whole kernel on CRuby, booted (`zr_boot`): the portable files
      # and the OS layer of this machine, with the host's arch layer in
      # place of the one in lib/zr/runtime/kernel/arch. It gives the
      # kernel the tables that a link gives a binary (`Runtime#load_tables`,
      # `Runtime#symbol_names`): the kernel's symbol names and empty load
      # tables.
      class Boot
        # The host's machine state: a context is the index of its Ruby
        # Fiber (0 before the first switch into it), the entry, the top of
        # its slot area and the slot top it left at.
        CONTEXT_BYTES = 32

        # The arch layer (`os.rb`): contexts are Ruby Fibers, and a switch is
        # `Fiber#transfer`. The kernel changes the task, the root frames and
        # the current fiber in memory before it switches, so nothing else
        # moves.
        #
        # Each method runs with the kernel module as self, so `self::BOOT`
        # is the Boot.
        module Arch
          def zr_arch_context_start(ctx, entry, top)
            Memory.write(ctx, [0, entry, top, top].pack("Q<4"))
            nil
          end

          def zr_arch_context_sp(ctx) = Memory.read(ctx + 24, 8).unpack1("q<")
          def zr_switch(from, to) = self::BOOT.switch(from, to)
        end

        # The OS layer's stack bounds are the main fiber's slot area: a
        # stack check compares a slot's address with them.
        module Stack
          def zr_os_stack_low = self::BOOT.host.slot_base
          def zr_os_stack_high = self::BOOT.host.slot_base + SLOT_BYTES
        end

        # Signals go through ruby: a C handler would run a Ruby closure in
        # the signal's context, which CRuby cannot do. A trap runs the
        # kernel's handler at ruby's next safe point, as the kernel's own
        # handler defers its work to the next poll.
        module Signals
          def zr_os_sigaction(signo, fn, old) = self::BOOT.sigaction(signo, fn, old)

          # The preemption timer (os/<os>/stack.rb) is a Ruby thread, not a
          # C thread: it sets the poll word every 100 ms.
          def zr_os_poll_start = self::BOOT.poll_start
        end

        # fork(2) as ruby forks, so ruby's own state in the child is right.
        # The child runs the program (`restart`).
        module Fork
          def fork = self::BOOT.fork
        end

        attr_reader :host

        def initialize(target = Target.default)
          files = RuntimeSources.for(target).kernel_files.reject { |path| path.include?("/kernel/arch/") }
          @symbols = Symbols.new
          files.each { |path| File.read(path).scan(/Machine\.id\(:"?([^)"]+)"?\)/) { @symbols.id(Regexp.last_match(1)) } }
          @host = Host.new(files, symbols: @symbols, constants: { "CONTEXT_BYTES" => CONTEXT_BYTES }, externs: externs)
          @fibers = [nil]
          @captures = {}
          @jump = nil
          kern = @host.kern
          kern.const_set(:BOOT, self)
          @handlers = {}
          @owner = Process.pid
          kern.prepend(Arch, Stack, Signals, Fork)
          kern.zr_boot
        end

        def kern = @host.kern

        # Switches from the context `from` to `to`, starting `to`'s Fiber at
        # its entry the first time.
        #
        # A continuation (continuation.rb) copies the slot area on a side
        # context, but the walker's frames are Ruby frames. So a switch to
        # the side context also captures them with ruby's `callcc`, with
        # the slot top, the pins and the walker's depth. When a restore on the side context
        # switches back to a context that a capture left, the switch goes
        # through that capture, and the capture's switch returns again.
        def switch(from, to)
          if to == kern.zr_cont_side_ctx
            k = callcc { |c| c }
            return unless k

            capture = [k, @host.slot_top, @host.pins.dup, @host.depth]
          end
          @jump = @captures[to] if @captures.key?(to)
          leave(from, to)
          if (jump = @jump)
            @jump = nil
            k, top, pins, depth = jump
            @host.slot_top = top
            @host.pins.replace(pins)
            @host.depth = depth
            k.call(nil)
          end
          @captures[from] = capture if capture
          nil
        end

        def leave(from, to)
          index, = Memory.read(from, 8).unpack("Q<")
          if index.zero?
            index = @fibers.size
            @fibers << Fiber.current
            Memory.write(from, [index].pack("Q<"))
          end
          Memory.write(from + 24, [@host.slot_top].pack("Q<"))
          target, entry, top = Memory.read(to, 24).unpack("Q<3")
          if target.zero?
            host = @host
            fiber = Fiber.new do
              host.fiber_slots(top)
              host.call_at(entry, [], TYPES["Void"], [])
              raise "a fiber's entry returned; it must switch away"
            end
            target = @fibers.size
            @fibers << fiber
            Memory.write(to, [target].pack("Q<"))
          end
          @fibers.fetch(target).transfer
          nil
        end

        # A thread's time slice, as a binary's.
        SLICE = 0.1

        # A forked child has no thread but the one that forked: the timer
        # starts again in it (`restart`).
        def poll_start
          kern = @host.kern
          @poll = nil unless @poll&.alive?
          @poll ||= Thread.new do
            loop do
              sleep SLICE
              kern.zr_poll_set
            end
          end
          nil
        end

        # After a fork: this process runs the program now. The timer that
        # the kernel started runs again, and the kernel's signal handlers
        # run here (`sigaction`).
        def restart
          @owner = Process.pid
          poll_start if @poll
        end

        # The process whose kernel takes the signals: the one that booted,
        # or a fork that runs a program (`restart`).
        attr_reader :owner

        # The kernel's fork (`Fork`): the child's pid, or 0 in the child.
        def fork
          pid = Process.fork
          return pid if pid

          restart
          0
        end

        # sigaction(2) for the kernel: `fn` 0 is the default, 1 is ignore,
        # else the address of a kernel def (`Machine.addr`). Stores the
        # previous `fn` at `old`. Returns 0, or -1 with errno EINVAL for a
        # signal that ruby does not let a program trap.
        def sigaction(signo, fn, old)
          kern = @host.kern
          name = Signal.signame(signo)
          handler = case fn
                    when 0 then "SYSTEM_DEFAULT"
                    when 1 then "IGNORE"
                    else
                      target = @host.def_at(fn) or raise ArgumentError, "a signal handler at #{fn} that is no kernel def"
                      # A fork inherits the trap; one that does not run the
                      # program (a test worker) keeps its kernel unchanged
                      # for the forks it makes after.
                      boot = self
                      proc { kern.public_send(target, signo) if boot.owner == Process.pid }
                    end
          Signal.trap(name, handler)
          Memory.write(old, [@handlers.fetch(signo, 0)].pack("Q<"))
          @handlers[signo] = fn
          0
        rescue ArgumentError
          kern.zr_os_set_errno(22)
          -1
        end

        private

        # The data objects of other units that the kernel reads.
        def externs
          names = @symbols.names
          bytes = Memory.zeroed(names.sum(&:bytesize) + 1, 1)
          table = Memory.zeroed([names.size * 16, 16].max)
          at = bytes
          names.each_with_index do |name, i|
            Memory.write(at, name.b) unless name.empty?
            Memory.write(table + (i * 16), [at, name.bytesize].pack("Q<Q<"))
            at += name.bytesize
          end
          empty = Memory.zeroed(8)
          # The load tables: no compiled-in file, and eleven empty texts.
          words = Memory.zeroed(8 * 24)
          Memory.write(words, ([0, empty] + ([empty, 0] * 11)).pack("Q<*"))
          {
            "zr_symbol_names" => table, "zr_symbol_count" => word(names.size), "zr_site_count" => word(0),
            "zr_load_tables" => word(words), "environ" => Fiddle::Handle::DEFAULT["environ"]
          }
        end

        def word(n)
          addr = Memory.zeroed(8)
          Memory.write(addr, [n].pack("Q<"))
          addr
        end
      end
    end
  end
end
