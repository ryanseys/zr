# frozen_string_literal: true

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

        attr_reader :host

        def initialize(target = Target.default)
          files = RuntimeSources.for(target).kernel_files.reject { |path| path.include?("/kernel/arch/") }
          @symbols = Symbols.new
          files.each { |path| File.read(path).scan(/Machine\.id\(:"?([^)"]+)"?\)/) { @symbols.id(Regexp.last_match(1)) } }
          @host = Host.new(files, symbols: @symbols, constants: { "CONTEXT_BYTES" => CONTEXT_BYTES }, externs: externs)
          @fibers = [nil]
          kern = @host.kern
          kern.const_set(:BOOT, self)
          kern.prepend(Arch, Stack)
          kern.zr_boot
        end

        def kern = @host.kern

        # Switches from the context `from` to `to`, starting `to`'s Fiber at
        # its entry the first time.
        def switch(from, to)
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
