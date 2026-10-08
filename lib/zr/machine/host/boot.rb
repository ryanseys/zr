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
      # kernel the tables that a link gives a binary (`LoadTables`,
      # `SymbolNumbering.names_table`): the kernel's symbol names and empty
      # load tables.
      class Boot
        # @rbs @symbols: Symbols
        # @rbs @fibers: Array[Fiber?]
        # @rbs @indices: Hash[Fiber, Integer]
        # @rbs @captures: Hash[Integer, Array[untyped]]
        # @rbs @jump: Array[untyped]?
        # @rbs @handlers: Hash[Integer, Integer]
        # @rbs @wake: Thread::Queue
        # @rbs @poll: Thread?

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
        #
        # These modules run as methods of the kernel module, a Module that
        # `Host#kernel_module` makes; `const_set` gives it `BOOT`, and its
        # other methods are the kernel's defs. Steep cannot see either.
        # steep:ignore:start
        module Arch
          #: (Integer ctx, Integer entry, Integer top) -> nil
          def zr_arch_context_start(ctx, entry, top)
            Memory.write(ctx, [0, entry, top, top].pack("Q<4"))
            nil
          end

          #: (Integer ctx) -> Integer
          def zr_arch_context_sp(ctx) = Memory.read(ctx + 24, 8).unpack1("q<")
          #: (Integer from, Integer to) -> nil
          def zr_switch(from, to) = self::BOOT.switch(from, to)
          #: (Integer record, Integer fn, Integer argv, Integer argc) -> Integer
          def zr_cframe_call(record, fn, argv, argc) = self::BOOT.cframe_call(record, fn, argv, argc)
          #: (Integer record) -> bot
          def zr_cframe_leap(record) = throw(record)
        end

        # The OS layer's stack bounds are the main fiber's slot area: a
        # stack check compares a slot's address with them.
        #
        # A fiber's stack is in the host's region, so its slots are as fast
        # to read as the main fiber's. It has no guard page: the walker's
        # depth limit stops a deep recursion first. `munmap` gives it back
        # (`Memory.function`).
        module Stack
          def zr_os_stack_low = self::BOOT.host.slot_base
          def zr_os_stack_high = self::BOOT.host.slot_base + SLOT_BYTES
          def zr_os_stack_map(bytes) = Memory::REGION.memalign(16, bytes) || super
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

        # nanosleep(2) that a signal cuts short, as in a binary: ruby runs a
        # trap on its main thread, and the program runs on another one.
        module Sleep
          def nanosleep(request, remaining) = self::BOOT.nanosleep(request, remaining)
        end

        # fork(2) as ruby forks, so ruby's own state in the child is right.
        # The child runs the program (`restart`).
        module Fork
          def zr_proc_fork = zr_fix(self::BOOT.fork_process)
        end

        # A Regexp's compile, which CRuby makes here (`Walk::Regexps`). The
        # kernel's own def answers nil, as it does in a binary, until a
        # walker runs the core.
        module Regexps
          def zr_regexp_host_compile(source, bits)
            walk = self::BOOT.walk
            walk ? walk.regexp_compile(source, bits) : super
          end
        end
        # steep:ignore:end

        attr_reader :host #: Host

        # The walker that runs the core over this kernel.
        attr_accessor :walk #: Walk?

        #: (?Target target) -> void
        def initialize(target = Target.default)
          files = RuntimeSources.for(target).kernel_files.reject { |path| path.include?("/kernel/arch/") }
          @symbols = Symbols.new
          files.each { |path| File.read(path).scan(/Machine\.id\(:"?([^)"]+)"?\)/) { @symbols.id(Regexp.last_match(1)) } }
          @host = Host.new(files, symbols: @symbols, constants: { "CONTEXT_BYTES" => CONTEXT_BYTES }, externs: externs)
          @fibers = [nil]
          @indices = {} #: Hash[Fiber, Integer]
          @captures = {} #: Hash[Integer, Array[untyped]]
          @jump = nil
          @walk = nil
          kern = @host.kern
          kern.const_set(:BOOT, self)
          @handlers = {} #: Hash[Integer, Integer]
          @owner = Process.pid
          @wake = Thread::Queue.new
          kern.prepend(Arch, Stack, Signals, Sleep, Fork, Regexps)
          kern.zr_boot
        end

        # The kernel module: its methods are the kernel's defs, which it
        # gets as it loads.
        #: () -> untyped
        def kern = @host.kern

        # `zr_cframe_call` on the host: the call of C is a Fiddle call
        # (`Host#call_at`), and a leap (`zr_cframe_leap`) throws the
        # record's address back to here, as a longjmp to the saved context
        # would return. The walker's own frames unwind as Ruby frames, and
        # the slot top goes back to where it was.
        #: (Integer record, Integer fn, Integer argv, Integer argc) -> Integer
        def cframe_call(record, fn, argv, argc)
          args = Memory.read(argv, argc * 8).unpack("q<*")
          word = TYPES["Word"]
          top = @host.slot_top
          catch(record) { return @host.call_at(fn, [word] * argc, word, args) }
          @host.slot_top = top
          kern::QUNDEF
        end

        # Switches from the context `from` to `to`, starting `to`'s Fiber at
        # its entry the first time.
        #
        # A continuation (continuation.rb) copies the slot area on a side
        # context, but the walker's frames are Ruby frames. So a switch to
        # the side context also captures them with ruby's `callcc`, with
        # its fiber's Stack (`Host::Stack`). When a restore on the side context
        # switches back to a context that a capture left, the switch goes
        # through that capture, and the capture's switch returns again.
        #
        # Ruby's `callcc` does not restore the locals of Ruby frames, so a
        # kernel loop (Array#each) would go on from the index it had last.
        # Each kernel def that loops and can yield is rooted, and its frame
        # can be read (`Host#live_roots`): the capture keeps the locals of
        # each one, and the jump writes them back.
        #: (Integer from, Integer to) -> nil
        def switch(from, to)
          if to == kern.zr_cont_side_ctx
            k = callcc { |c| c }
            return unless k

            stack = @host.stack
            frames = @host.live_roots
            capture = [k, stack.top, stack.pins.dup, stack.roots, frames, locals(frames), stack.rooted, stack.depth]
          end
          @jump = @captures[to] if @captures.key?(to)
          leave(from, to)
          if (jump = @jump)
            @jump = nil
            k, top, pins, roots, frames, locals, rooted, depth = jump
            stack = @host.stack
            stack.top = top
            stack.pins.replace(pins)
            stack.roots = roots
            frames.each_with_index do |(binding, _), i|
              locals[i].each { |name, v| binding.local_variable_set(name, v) }
            end
            stack.rooted = rooted
            stack.depth = depth
            k.call(nil)
          end
          @captures[from] = capture if capture
          nil
        end

        # The locals of each rooted kernel frame, by name (`switch`).
        #: (Array[[Binding, Array[Symbol]]] frames) -> Array[Hash[Symbol, untyped]]
        def locals(frames)
          frames.map do |binding, _|
            binding.local_variables.to_h { |name| [name, binding.local_variable_get(name)] }
          end
        end

        # A switch writes the whole `from` context, as a binary's saves
        # every register there: a context that the kernel allocates (a
        # continuation's, in memory that malloc gave again) holds old bytes
        # until then.
        #: (Integer from, Integer to) -> nil
        def leave(from, to)
          # @type ivar @fibers: Array[Fiber]
          index = @indices[Fiber.current] ||= @fibers.push(Fiber.current).size - 1
          Memory.write(from, [index].pack("Q<"))
          Memory.write(from + 24, [@host.slot_top].pack("Q<"))
          target, entry, top = Memory.read(to, 24).unpack("Q<3") #: [Integer, Integer, Integer]
          if target.zero?
            host = @host
            fiber = Fiber.new do
              host.fiber_slots(top)
              host.call_at(entry, [], TYPES["Void"], [])
              raise "a fiber's entry returned; it must switch away"
            end
            target = @indices[fiber] = @fibers.push(fiber).size - 1
            Memory.write(to, [target].pack("Q<"))
          end
          # A collection on another fiber marks this one's rooted frames,
          # which only this fiber can read.
          stack = @host.stack
          stack.frames = @host.live_roots
          @fibers.fetch(target).transfer
          nil
        end

        # A thread's time slice, as a binary's.
        SLICE = 0.1

        # A forked child has no thread but the one that forked: the timer
        # starts again in it (`restart`).
        #: () -> nil
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
        #: () -> void
        def restart
          @owner = Process.pid
          poll_start if @poll
        end

        # The process whose kernel takes the signals: the one that booted,
        # or a fork that runs a program (`restart`).
        attr_reader :owner #: Integer

        # A signal's handler ran: a sleep ends now (`nanosleep`).
        #: () -> void
        def wake = @wake << true

        # The kernel's nanosleep (`Sleep`): 0 after the whole time, or -1
        # with EINTR and the time left when a signal arrives. A signal that
        # came before the sleep does not cut it short.
        #: (Integer request, Integer remaining) -> Integer
        def nanosleep(request, remaining)
          seconds, nanoseconds = Memory.read(request, 16).unpack("q<q<") #: [Integer, Integer]
          length = seconds + (nanoseconds / 1e9)
          @wake.clear
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          return 0 unless @wake.pop(timeout: length)

          if remaining != 0
            left = [length - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started), 0].max
            Memory.write(remaining, [left.floor, ((left % 1) * 1e9).floor].pack("q<q<"))
          end
          kern.zr_os_set_errno(4) # EINTR
          -1
        end

        # `Process.fork` for the kernel (`Fork`): the child's pid, or 0 in
        # the child.
        #: () -> Integer
        def fork_process
          pid = Process.fork
          return pid if pid

          restart
          0
        end

        # sigaction(2) for the kernel: `fn` 0 is the default, 1 is ignore,
        # else the address of a kernel def (`Machine.addr`). Stores the
        # previous `fn` at `old`. Returns 0, or -1 with errno EINVAL for a
        # signal that ruby does not let a program trap.
        #: (Integer signo, Integer fn, Integer old) -> Integer
        def sigaction(signo, fn, old)
          kern = @host.kern
          name = Signal.signame(signo) or raise ArgumentError, "no signal #{signo}"
          handler = case fn
                    when 0 then "SYSTEM_DEFAULT"
                    when 1 then "IGNORE"
                    else
                      target = @host.def_at(fn) or raise ArgumentError, "a signal handler at #{fn} that is no kernel def"
                      # A fork inherits the trap; one that does not run the
                      # program (a test worker) keeps its kernel unchanged
                      # for the forks it makes after.
                      boot = self
                      proc do
                        if boot.owner == Process.pid
                          kern.public_send(target, signo)
                          boot.wake
                        end
                      end
                    end
          Signal.trap(name, handler)
          Memory.write(old, [@handlers.fetch(signo, 0)].pack("Q<"))
          @handlers[signo] = fn
          0
        rescue ArgumentError, Errno::EINVAL
          # ruby refuses a signal it keeps (ArgumentError) and one that the
          # OS refuses, as SIGKILL (EINVAL).
          kern.zr_os_set_errno(22)
          -1
        end

        private

        # The data objects of other units that the kernel reads.
        #: () -> Hash[String, Integer]
        def externs
          # The kernel's table has no pads.
          names = @symbols.names #: Array[String]
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

        #: (Integer n) -> Integer
        def word(n)
          addr = Memory.zeroed(8)
          Memory.write(addr, [n].pack("Q<"))
          addr
        end
      end
    end
  end
end
