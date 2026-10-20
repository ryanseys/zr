# frozen_string_literal: true

module Zr
  module Harness
    # What a dyld failure to map the shared cache says about the binary
    # that it names: its segments, each marked when it reaches the shared
    # region (Obj::MachO::Executable::SHARED_REGION). dyld on macOS 14 and
    # 15 loads no image with a segment there.
    module Segments
      FAILED = "syscall to map cache into shared region failed"
      # dyld's "Referenced from: <UUID> /path/to/binary".
      BINARY = /Referenced from: <[^>]*> (\S+)/

      module_function

      # `text` and, when it has dyld's message, the segments of the binary
      # that the message names.
      def explain(text)
        return text unless text.include?(FAILED)

        path = text[BINARY, 1]
        return text unless path && File.file?(path)

        "#{text}\nzr test: the segments of #{path}:\n#{report(File.binread(path))}"
      rescue StandardError => e
        "#{text}\nzr test: no segments: #{e.message}\n"
      end

      # One line for each segment of the Mach-O image `bytes`. The linker
      # loads only for a failure: each child's output passes `explain`.
      def report(bytes)
        require_relative "../../../lib/zr/obj/macho/image"
        require_relative "../../../lib/zr/obj/macho/executable"
        region = Obj::MachO::Executable::SHARED_REGION
        Obj::MachO::Image.read(bytes).segments.map do |s|
          finish = s.vmaddr + s.vmsize
          inside = finish > region && s.vmaddr < 0x3_0000_0000
          format("  %-16s 0x%011x-0x%011x%s\n", s.name, s.vmaddr, finish, inside ? "  <- in the shared region" : "")
        end.join
      end
    end
  end
end
