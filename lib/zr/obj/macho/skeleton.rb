# frozen_string_literal: true

module Zr
  module Obj
    module MachO
      # The skeleton: the bytes that all binaries linked against one base
      # share. A binary starts with a header page and the runtime's
      # `__TEXT` (18 MB of 22 MB), at the same file offsets for every
      # program. A link never writes into that text (dyld fills slots in
      # the GOT and the data), so the link does not write it again. A spec
      # tier links about 7000 times, so this saves about 160 GB a run.
      #
      # The link uses one of three paths, in this order:
      # 1. When `out` already contains the base's text, the link writes
      #    only the header page and the bytes after the text. The text
      #    pages stay clean and in memory. The tests and a repeated
      #    `zr build` to one path use this path.
      # 2. Otherwise, on APFS, the link clones the skeleton file with
      #    `clonefile(2)` (through Fiddle). A clone shares blocks until a
      #    write, but its first exec reads the text from disk (20 MB and
      #    40 ms a binary, and parallel workers wait on each other).
      # 3. Otherwise (another volume, not APFS, no Fiddle) the link writes
      #    the full file. All three paths give the same bytes; a test
      #    checks this.
      module Skeleton
        PAGE = Prelink::PAGE

        # Returns the skeleton of `base`: a blank header page, then the
        # text blob.
        def self.bytes(base) = ("\0".b * PAGE) + base.blobs.fetch(:text)

        # Opens `out` for a binary whose bytes after the header page start
        # with `text`. It uses the existing file when it contains that
        # text, else a clone of `skeleton`, else a new file. Yields the
        # file at offset 0 and whether the text is in place. The block
        # writes the header page, skips or writes the text, then writes the
        # rest. The file ends where the block stops and is executable.
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

        # Checks whether the file at `out` contains `text` after its header
        # page. It reads and compares the bytes, unless this process wrote
        # the text there and the file did not change after that.
        def self.kept?(out, text)
          stamp = stamp(out) or return false
          left, held = written[out]
          return true if left == stamp && held.equal?(text)

          stamp[1] >= PAGE + text.bytesize && IO.binread(out, text.bytesize, PAGE) == text
        rescue SystemCallError
          false
        end

        # The files that this process wrote a text into, each with its
        # file stamp and the text.
        def self.written = @written ||= {}

        # The file stamp: the inode, the size, the mtime and the ctime.
        def self.stamp(out)
          stat = File.stat(out)
          [stat.ino, stat.size, stat.mtime, stat.ctime]
        rescue SystemCallError
          nil
        end

        # Clones `skeleton` to `out`, or returns false. `size` is the
        # expected skeleton size (the binary's `__TEXT` as a file). A
        # skeleton of a different size belongs to another base; this does
        # not use it.
        def self.clone(skeleton, out, size)
          return false unless skeleton && File.size?(skeleton) == size && (fn = clonefile)

          File.unlink(out) if File.exist?(out)
          fn.call(skeleton, out, 0).zero?
        rescue SystemCallError
          false
        end

        # Returns `clonefile` from libSystem (looked up once), or nil when
        # it is not available.
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
