# frozen_string_literal: true

module Ze0
  module Obj
    module MachO
      # The bytes of a binary that every program linked beside one base
      # shares, kept as a file the link clones instead of writing -- or
      # left where they are, when the last binary at the same path holds
      # them already.
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
      # A clone is not free to run, though. Its pages are nobody's yet, so
      # the first exec reads the whole text from disk (measured: 20 MB
      # and 40 ms a binary, and eight workers reading at once wait on
      # each other), where a file written whole runs from the pages the
      # write left in memory -- and is flushed to disk for that. So where
      # a binary stands at `out` already with the base's text in it, the
      # link writes over it: the header page and everything after the
      # text, the text's pages untouched, clean and in memory. That is
      # the road the checks take, one file a worker; `ze0 build` to the
      # same path takes it too. The clone is for a path with nothing at
      # it, and the plain road for a filesystem that will not clone.
      #
      # `clonefile(2)` is reached through Fiddle, which the checks' ruby
      # has. Where the clone is refused -- another volume, a filesystem
      # that is not APFS, a compiler with no Fiddle -- the answer is false
      # and the link takes the plain road, so nothing here decides what
      # a binary holds.
      module Skeleton
        PAGE = Prelink::PAGE

        # `bytes` of the skeleton of `base`: the header page, blank, and
        # the text blob after it.
        def self.bytes(base) = ("\0".b * PAGE) + base.blobs.fetch(:text)

        # Opens `out` for a binary whose bytes past the header page begin
        # with `text`: over the binary there when it holds that text,
        # else over a clone of `skeleton`, else fresh. Yields the file at
        # its start and whether the text is in place; the block writes the
        # header page, seeks past the text where it is in place and writes
        # it where it is not, then writes the rest. The file ends where
        # the block stopped, and is left executable.
        def self.write_over(out, skeleton, text)
          size = PAGE + text.bytesize
          kept = kept?(out, text) || clone(skeleton, out, size)
          File.open(out, kept ? "r+b" : "wb") do |file|
            yield file, kept
            file.truncate(file.pos)
          end
          File.chmod(0o755, out)
          written[out] = [stamp(out), text]
        end

        # Whether the file at `out` holds `text` after its header page:
        # read and compared, unless this process wrote it there and the
        # file has not changed since.
        def self.kept?(out, text)
          stamp = stamp(out) or return false
          left, held = written[out]
          return true if left == stamp && held.equal?(text)

          stamp[1] >= PAGE + text.bytesize && IO.binread(out, text.bytesize, PAGE) == text
        rescue SystemCallError
          false
        end

        # The files this process wrote a text into, each with the stamp
        # it left and the text.
        def self.written = @written ||= {}

        # What tells one file's contents from the next: the inode and the
        # size, and when it was last written or changed.
        def self.stamp(out)
          stat = File.stat(out)
          [stat.ino, stat.size, stat.mtime, stat.ctime]
        rescue SystemCallError
          nil
        end

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
