# frozen_string_literal: true

module Ze0
  module Obj
    module MachO
      # The bytes of a binary that every program linked beside one base
      # shares, kept as a file the link clones instead of writing.
      #
      # A binary linked beside the runtime begins with a header page and
      # the runtime's `__TEXT`, 18 MB of the 22 the whole binary is, and
      # both stand at the same file offsets whatever the program: the
      # base is placed at fixed addresses, and the program's code comes
      # after it. Nothing a link does writes into the text blob -- the
      # slots dyld fills are in the GOT and the data -- so a link that
      # wrote the binary from the first byte wrote 18 MB that were the
      # same as the last link's. A spec tier links seven thousand times:
      # 160 GB a run.
      #
      # APFS clones a file in one call and shares its blocks until either
      # copy is written, so a link clones the skeleton and writes the
      # header page and everything after the text. The bytes are the same
      # as the plain road writes; a check holds the two equal.
      #
      # `clonefile(2)` is reached through Fiddle, which the checks' ruby
      # has. Where the clone is refused -- another volume, a filesystem
      # that is not APFS, a compiler with no Fiddle -- the answer is false
      # and the link takes the plain road, so nothing here decides what
      # a binary holds.
      module Skeleton
        # `bytes` of the skeleton of `base`: the header page, blank, and
        # the text blob after it.
        def self.bytes(base) = ("\0".b * Prelink::PAGE) + base.blobs.fetch(:text)

        # Clones `skeleton` to `out`, or answers false. `size` is what the
        # skeleton must be: the binary's `__TEXT` as a file; a skeleton of
        # any other size is somebody else's and is left alone.
        def self.clone(skeleton, out, size)
          return false unless skeleton && File.size?(skeleton) == size && (fn = clonefile)

          File.unlink(out) if File.exist?(out)
          fn.call(skeleton, out, 0).zero?
        rescue SystemCallError
          false
        end

        # `clonefile` from libSystem, once, or nil where it cannot be had.
        def self.clonefile
          return @clonefile if defined?(@clonefile)

          @clonefile = begin
            require "fiddle"
            handle = ::Fiddle::Handle::DEFAULT
            ::Fiddle::Function.new(handle["clonefile"], [::Fiddle::TYPE_VOIDP, ::Fiddle::TYPE_VOIDP, ::Fiddle::TYPE_INT],
                                   ::Fiddle::TYPE_INT)
          rescue LoadError, ::Fiddle::DLError
            nil
          end
        end
      end
    end
  end
end
