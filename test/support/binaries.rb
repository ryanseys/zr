# frozen_string_literal: true

require "digest"
require "fileutils"
require "stringio"
require "zlib"
require_relative "../../lib/zr/zr"
require_relative "../../lib/zr/native/build"
require_relative "../../lib/zr/obj/macho/skeleton"

module Zr
  module Spec
    # The binaries the examples built, kept for the next run.
    #
    # An example is a build and a run, and on a warm cache the build is
    # more than half of it. A run after an edit that reached no part of
    # the compiler -- a spec's own sentence, a fixture, a test file --
    # builds every example again to the same bytes, since a build is a
    # function of its inputs and `rake stage1` proves it. So each
    # example's binary is kept under the cache, named by every input of
    # its bytes, and a later run takes the binary and skips to the run.
    #
    # A binary is 24 MB, and all but a few hundred kilobytes of it are
    # the runtime's: the text the link clones from its skeleton, the
    # `__DATA` segment, and the base's symbol and string tables, which
    # every binary linked beside one prelink holds byte for byte. A kept
    # binary leaves those out and says where they went, and a take puts
    # them back from the prelink in memory -- the text as the link
    # leaves it -- and what is kept is deflated. A whole spec tier is
    # then five gigabytes, not two hundred, and `trim` keeps the
    # directory under `ZR_BINARIES_GB` by dropping what was used
    # longest ago. A module has no prelink to draw on and is kept whole,
    # so it is kept only when asked (`ZR_BINARIES=1`); `ZR_BINARIES=0`
    # keeps nothing.
    #
    # The key fails closed. It holds the runtime's digest for the target
    # (everything that lowers and emits the runtime), the link digest,
    # the target, the environment names that reach a build's bytes, the
    # program's path and source, and every fixture written beside it,
    # a link by where it points. An example that writes no key -- one
    # whose fixtures this cannot describe -- is built as before. A hole
    # is cut only where the binary's bytes equal the prelink's, and a
    # take that cannot put a binary back whole answers false, and the
    # example builds.
    module Binaries
      VERSION = 3
      # The environment a build reads that decides its bytes -- and
      # `ZR_VERIFY`, which decides whether the lowering checks itself,
      # so a verifying run lowers rather than takes.
      ENVIRONMENT = %w[ZR_LINK ZR_EVAL ZR_VERIFY ZR_WASM_NAMES ZR_WASM_WIDTH].freeze
      PAGE = Obj::MachO::Prelink::PAGE

      module_function

      def wanted?(target)
        case ENV["ZR_BINARIES"]
        when "1" then true
        when "0" then false
        else target.link
        end
      end

      def directory = File.join(Zr.cache, "binaries")

      def limit = Float(ENV.fetch("ZR_BINARIES_GB", 8)) * (1 << 30)

      # Where the binary of this example is kept, or nil where no key
      # can describe it.
      def path(target, source, rb, files)
        parts = files.sort.map { |name, bytes| [name, bytes.is_a?(Hash) ? "-> #{bytes.fetch(:symlink)}" : bytes] }
        return nil unless parts.all? { |_, bytes| bytes.is_a?(String) }

        key = Digest::SHA256.new
        [VERSION, Zr.runtime(target).digest, Zr.link_digest, target.triple,
         *ENVIRONMENT.map { |name| ENV[name].to_s }, rb, source, *parts.flatten].each { |part| key << part.to_s << "\0" }
        File.join(directory, "#{key.hexdigest}#{'.wasm' unless target.link}")
      end

      # The kept binary put back at `bin`, or false where there is none
      # or it cannot be put back whole.
      def take(kept, bin)
        return false unless kept && File.exist?(kept)

        now = Time.now
        File.utime(now, now, kept)
        kept.end_with?(".wasm") ? copy(kept, bin) : restore(kept, bin)
        true
      rescue SystemCallError, TypeError, ArgumentError, KeyError, Zlib::Error
        File.unlink(bin) if File.exist?(bin)
        false
      end

      # `bin`, the binary of `program` built under `work`, kept: sparse
      # where it was linked beside the cache's objects, whole otherwise.
      #
      # A binary that spells the directory it was built in is not kept:
      # a required file's path is resolved when it is compiled, and a
      # box that loads beside it at run time would look in a directory
      # the run before this one has removed. Such a binary is a
      # function of where it was built as well as of what, and the key
      # does not say where.
      def keep(kept, bin, program, work)
        return unless kept

        bytes = File.binread(bin)
        return if bytes.include?(work)

        # A binary built while a source moved under the tier is a
        # function of two versions of the tree, and its key names one:
        # kept, it would answer for that key until the source moved
        # again. The tier stops on the file's name instead.
        Zr.settled!
        FileUtils.mkdir_p(directory)
        tmp = "#{kept}.#{Process.pid}"
        objects = objects_of(program)
        sparse = !kept.end_with?(".wasm") && Native::Build.prelink_path(objects)
        File.binwrite(tmp, sparse ? sparse(bytes, objects) : bytes)
        File.rename(tmp, kept)
      end

      # Drops the binaries used longest ago until what is kept fits
      # `limit`. Run once, ahead of the workers.
      def trim(limit = self.limit, directory = self.directory)
        files = Dir[File.join(directory, "*")].map { |path| [path, File.mtime(path), File.size(path)] }
        held = files.sum { |_, _, size| size }
        files.sort_by { |_, used, _| used }.each do |path, _, size|
          break unless held > limit

          File.unlink(path)
          held -= size
        end
      end

      # The cached objects `program` was linked beside: the runtime, and
      # the road where the program evals (`Native::Build.program`).
      def objects_of(program)
        objects = [Native::Build.runtime_object(program.runtime)]
        objects << Native::Build.road_object(program.evals) if program.evals
        objects
      end

      # A clone where the filesystem clones, else a copy.
      def copy(from, to)
        Obj::MachO::Skeleton.clone(from, to, File.size(from)) || FileUtils.cp(from, to)
      end

      # --- the sparse form ---------------------------------------------

      # `bytes` of a binary linked beside `objects`, less every hole
      # whose bytes are the prelink's: a head that says the binary's
      # size, the objects and the holes, then the bytes between them,
      # deflated. Machine code deflates by half at the fastest level,
      # in 10 ms a megabyte; inflating is a third of that.
      def sparse(bytes, objects)
        base = Native::Build.prelink(objects)
        holes = cuts(bytes, base).select { |at, size, name| bytes[at, size] == filling(base, name) }
        head = Marshal.dump({ size: bytes.bytesize, objects: objects.map { |o| File.basename(o) }, holes: holes })
        body = +"".b
        at = 0
        holes.each do |hole_at, size, _|
          body << bytes[at, hole_at - at]
          at = hole_at + size
        end
        body << bytes[at..]
        [head.bytesize].pack("Q<") + head + Zlib::Deflate.deflate(body, Zlib::BEST_SPEED)
      end

      # Where the holes of a binary linked beside `base` would be, each
      # `[at, size, name]`: the text after the header page, the `__DATA`
      # segment, and the base's parts of the two symbol tables.
      def cuts(bytes, base)
        data = symbols = strings = nil
        each_command(bytes) do |cmd, at|
          case cmd
          when Obj::MachO::Executable::LC_SEGMENT_64
            data = bytes.unpack("Q<2", offset: at + 40) if bytes[at + 8, 16].delete("\0") == "__DATA"
          when Obj::MachO::Executable::LC_SYMTAB
            symbols, _, strings = bytes.unpack("L<3", offset: at + 8)
          end
        end
        raise ArgumentError, "no __DATA or no symbol table" unless data && symbols && strings

        [[PAGE, base.text_size - PAGE, :text], [*data, :data],
         [symbols, base.symbols.bytesize, :symbols], [strings, base.strings.bytesize, :strings]]
      end

      def each_command(bytes)
        at = 32
        bytes.unpack1("L<", offset: 16).times do
          cmd, size = bytes.unpack("L<2", offset: at)
          yield cmd, at
          at += size
        end
      end

      # The prelink's bytes for the hole `name`.
      def filling(base, name)
        case name
        when :text then base.blobs.fetch(:text)
        when :data then base.blobs.fetch(:data)
        when :symbols then base.symbols
        when :strings then base.strings
        else raise KeyError, "no hole named #{name}"
        end
      end

      # The binary at `bin` from its sparse form at `kept`, whole: the
      # text left in place or cloned as a link leaves it
      # (`Skeleton.write_over`), every other hole written from the
      # prelink.
      def restore(kept, bin)
        File.open(kept, "rb") do |file|
          head = Marshal.load(file.read(file.read(8).to_s.unpack1("Q<").to_i))
          src = StringIO.new(Zlib::Inflate.inflate(file.read))
          objects = head.fetch(:objects).map { |name| File.join(Zr.cache, name) }
          base = Native::Build.prelink(objects)
          holes = head.fetch(:holes)
          text = base.blobs.fetch(:text)
          raise ArgumentError, "the text hole is not the base's text" unless holes.first == [PAGE, text.bytesize, :text]

          Obj::MachO::Skeleton.write_over(bin, Native::Build.skeleton(objects), text) do |out, kept_text|
            at = 0
            holes.each do |hole_at, size, name|
              out.write(src.read(hole_at - at)) if hole_at > at
              if kept_text && name == :text
                out.seek(hole_at + size)
              else
                out.write(filling(base, name))
              end
              at = hole_at + size
            end
            out.write(src.read)
          end
          raise ArgumentError, "the binary came back #{File.size(bin)} bytes, not #{head.fetch(:size)}" unless File.size(bin) == head.fetch(:size)
        end
      end
    end
  end
end
