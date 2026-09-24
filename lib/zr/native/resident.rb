# frozen_string_literal: true

module Zr
  module Native
    # The resident memory size of a process. Ruby has no portable way to
    # read it, and macOS has no `/proc`. Thus this calls the system through
    # Fiddle: `proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)`
    # returns the number of bytes of `info` that it filled (a
    # proc_taskinfo is 96). The resident size is the second word. The call
    # takes a microsecond; a `ps` child takes 2 ms. On other systems, or in
    # a zr binary (which has no Fiddle), this returns nil and the caller
    # uses a different value.
    module Resident
      TASKINFO = 4
      SIZE = 96

      # The resident bytes of `pid`, or nil.
      def self.bytes_of(pid)
        return nil unless (ask = asker)

        info = ::Fiddle::Pointer.malloc(SIZE, ::Fiddle::RUBY_FREE)
        return nil unless ask.call(pid, TASKINFO, 0, info, SIZE) == SIZE

        info[8, 8].unpack1("Q<")
      end

      # The same in megabytes, for a report.
      def self.of(pid)
        bytes = bytes_of(pid)
        bytes && bytes / (1 << 20)
      end

      def self.asker
        return @asker if defined?(@asker)

        @asker = begin
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
