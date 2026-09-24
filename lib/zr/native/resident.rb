# frozen_string_literal: true

module Zr
  module Native
    # What a process resides in. Ruby has no portable way to ask -- macOS
    # has no `/proc` -- so the system is asked directly where Fiddle can
    # reach it: `proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)`
    # answers how many bytes of `info` it filled (a proc_taskinfo is 96)
    # and the task's resident size is the second word of them. It runs in
    # a microsecond, where `ps` is a child of 2 ms. Anywhere else, or in
    # a zr binary (which carries no Fiddle), the answer is nil and the
    # caller reads what it can.
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

      # The same in megabytes, as a report prints it.
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
