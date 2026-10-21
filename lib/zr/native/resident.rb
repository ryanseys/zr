# frozen_string_literal: true

require_relative "../session"

module Zr
  module Native
    # The resident memory size of a process. Ruby has no portable way to
    # read it, and macOS has no `/proc`. Thus this calls the system through
    # Fiddle: `proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)`
    # returns the number of bytes of `info` that it filled (a
    # proc_taskinfo is 96). The resident size is the second word. The call
    # takes a microsecond; a `ps` child takes 2 ms. Linux has `/proc`: its
    # status file gives the resident size (VmRSS, in kB). On other systems,
    # or in a zr binary on macOS (which has no Fiddle), this returns nil and
    # the caller uses a different value.
    module Resident
      TASKINFO = 4
      SIZE = 96

      # The resident bytes of `pid`, or nil.
      #: (Integer pid) -> Integer?
      def self.bytes_of(pid)
        return from_proc(pid) if File.exist?("/proc/self/status")
        return nil unless (ask = asker)

        info = ::Fiddle::Pointer.malloc(SIZE, ::Fiddle::RUBY_FREE)
        return nil unless ask.call(pid, TASKINFO, 0, info, SIZE) == SIZE

        info[8, 8].unpack1("Q<") #: Integer
      end

      # VmRSS of `pid`'s status file, or nil when the process is gone.
      #: (Integer pid) -> Integer?
      def self.from_proc(pid)
        line = File.foreach("/proc/#{pid}/status").find { |text| text.start_with?("VmRSS:") }
        line && (line.split.fetch(1).to_i * 1024)
      rescue SystemCallError
        nil
      end

      # The same in megabytes, for a report.
      #: (Integer pid) -> Integer?
      def self.of(pid)
        bytes = bytes_of(pid)
        bytes && bytes / (1 << 20)
      end

      # `proc_pid_rusage(pid, RUSAGE_INFO_V0, &info)` fills a rusage_info_v0
      # (96 bytes); its ri_phys_footprint (at 72) is the memory that macOS
      # charges to the process, the pages it compressed or swapped too.
      # The resident size leaves those out, so it falls as the machine
      # runs out of memory, just when a limit must see it.
      RUSAGE_INFO_V0 = 0
      FOOTPRINT_AT = 72

      # The footprint bytes of `pid` on macOS, or nil (another system, or
      # the process is gone).
      #: (Integer pid) -> Integer?
      def self.footprint_of(pid)
        return nil unless (calls = group_calls)

        info = ::Fiddle::Pointer.malloc(SIZE, ::Fiddle::RUBY_FREE)
        return nil unless calls.fetch(:rusage).call(pid, RUSAGE_INFO_V0, info).zero?

        info[FOOTPRINT_AT, 8].unpack1("Q<") #: Integer
      end

      # `proc_listpids(PROC_PGRP_ONLY, pgid, &pids, size)` gives the pids of
      # a process group, 4 bytes each, and returns the bytes that it filled.
      PROC_PGRP_ONLY = 2
      GROUP_MAX = 4096

      # The pids of the process group `pgid` on macOS, or nil.
      #: (Integer pgid) -> Array[Integer]?
      def self.group_pids(pgid)
        return nil unless (calls = group_calls)

        pids = ::Fiddle::Pointer.malloc(GROUP_MAX * 4, ::Fiddle::RUBY_FREE)
        filled = calls.fetch(:list).call(PROC_PGRP_ONLY, pgid, pids, GROUP_MAX * 4)
        return nil if filled.negative?

        pids[0, filled].unpack("l<*").reject(&:zero?)
      end

      # The footprint bytes of the process group `pgid`, summed, or nil.
      #: (Integer pgid) -> Integer?
      def self.group_footprint(pgid)
        pids = group_pids(pgid) or return nil
        pids.sum { |pid| footprint_of(pid) || 0 }
      end

      #: () -> { rusage: Fiddle::Function, list: Fiddle::Function }?
      def self.group_calls
        Session.current.memo(:group_calls) do
          next nil unless RUBY_PLATFORM.include?("darwin")

          require "fiddle"
          handle = ::Fiddle::Handle::DEFAULT
          { rusage: ::Fiddle::Function.new(handle["proc_pid_rusage"], [::Fiddle::TYPE_INT, ::Fiddle::TYPE_INT, ::Fiddle::TYPE_VOIDP],
                                           ::Fiddle::TYPE_INT),
            list: ::Fiddle::Function.new(handle["proc_listpids"],
                                         [::Fiddle::TYPE_UINT32_T, ::Fiddle::TYPE_UINT32_T, ::Fiddle::TYPE_VOIDP, ::Fiddle::TYPE_INT],
                                         ::Fiddle::TYPE_INT) }
        rescue LoadError, ::Fiddle::DLError, NameError
          nil
        end
      end

      # `host_statistics64(mach_host_self(), HOST_VM_INFO64, &stats, &count)`
      # fills a vm_statistics64 (152 bytes, `count` in 4-byte words), the
      # numbers that `vm_stat` prints.
      HOST_VM_INFO64 = 4
      VM_STATS = 152

      # The pages that macOS processes hold: the anonymous pages that are
      # not purgeable, the wired pages, and the compressor's pages (the
      # file cache can be dropped). Nil where the call is missing.
      #: () -> Integer?
      def self.used_pages
        return nil unless (stats = host_stats)

        buffer = ::Fiddle::Pointer.malloc(VM_STATS, ::Fiddle::RUBY_FREE)
        count = ::Fiddle::Pointer.malloc(4, ::Fiddle::RUBY_FREE)
        count[0, 4] = [VM_STATS / 4].pack("L<")
        return nil unless stats.fetch(:stats).call(stats.fetch(:host).call, HOST_VM_INFO64, buffer, count).zero?

        word = ->(at) { buffer[at, 4].unpack1("L<") } #: ^(Integer) -> Integer
        # internal_page_count - purgeable_count + wire_count + compressor_page_count
        word[140] - word[88] + word[12] + word[128]
      end

      #: () -> { host: Fiddle::Function, stats: Fiddle::Function }?
      def self.host_stats
        Session.current.memo(:host_stats) do
          require "fiddle"
          handle = ::Fiddle::Handle::DEFAULT
          { host: ::Fiddle::Function.new(handle["mach_host_self"], [], ::Fiddle::TYPE_UINT32_T),
            stats: ::Fiddle::Function.new(handle["host_statistics64"],
                                          [::Fiddle::TYPE_UINT32_T, ::Fiddle::TYPE_INT, ::Fiddle::TYPE_VOIDP, ::Fiddle::TYPE_VOIDP],
                                          ::Fiddle::TYPE_INT) }
        rescue LoadError, ::Fiddle::DLError, NameError
          nil
        end
      end

      #: () -> Fiddle::Function?
      def self.asker
        Session.current.memo(:pid_info) do
          require "fiddle"
          ::Fiddle::Function.new(::Fiddle::Handle::DEFAULT["proc_pidinfo"],
                                 [::Fiddle::TYPE_INT, ::Fiddle::TYPE_INT, ::Fiddle::TYPE_UINT64_T, ::Fiddle::TYPE_VOIDP, ::Fiddle::TYPE_INT],
                                 ::Fiddle::TYPE_INT)
        rescue LoadError, ::Fiddle::DLError, NameError
          nil
        end
      end
    end
  end
end
