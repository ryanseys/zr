# frozen_string_literal: true

require "digest"
require "fileutils"
require "stringio"
require "zlib"
require_relative "../../lib/zr/runtime"
require_relative "../../lib/zr/native/build"
require_relative "../../lib/zr/obj/macho/skeleton"

module Zr
  module Test
    # Keeps the binaries that the program tests build, for the next run.
    #
    # On a warm cache, the build is more than half the time of a test.
    # A build is a function of its inputs (`zr-dev stage 1` checks this). So
    # each binary is kept in the cache under a key made from all its
    # inputs. A later run with the same key uses the kept binary and does
    # not build. This helps most after an edit to a test, its files or a
    # test file, which does not change the compiler.
    #
    # A binary is 24 MB. Almost all of it is the same in each binary linked
    # with one prelinked image: the text cloned from the skeleton, the
    # `__DATA` segment, and the symbol and string tables of the image. The
    # kept form leaves out these parts ("holes"), records where they were,
    # and deflates the rest. `take` writes the holes back from the prelinked
    # image in memory. A full program tier is then 5 GB, not 200 GB. The
    # binaries are entries of the store (kind `binary`), and `trim` keeps
    # them under `ZR_TEST_BINARIES_GB`, the least recently used first. A WASI module has no prelinked image, so
    # it is kept whole, and only with `ZR_TEST_BINARIES=1`.
    # `ZR_TEST_BINARIES=0` keeps nothing.
    #
    # The key fails closed. It contains the runtime digest for the target
    # (all code that lowers and emits the runtime), the link digest, the
    # library files that a program can require (`libraries`), the target, the environment variables that change the bytes of a build,
    # the path and source of the program, and each fixture written next to
    # it (a symbolic link by its target). A test whose files have no
    # key builds as usual. A hole is cut only where the bytes of the binary
    # are equal to the bytes of the prelinked image. When `take` cannot
    # restore the whole binary, it returns false and the test builds.
    module Binaries
      VERSION = 4
      # The environment variables that change the bytes of a build. Also
      # `ZR_VERIFY`, which makes the lowering verify itself: with it, a
      # run lowers again and does not use a kept binary.
      ENVIRONMENT = %w[ZR_LINKER ZR_EVAL ZR_VERIFY ZR_WASM_NAMES ZR_WASM_WIDTH].freeze
      PAGE = Obj::MachO::Prelink::PAGE

      module_function

      def wanted?(target)
        case ENV["ZR_TEST_BINARIES"]
        when "1" then true
        when "0" then false
        else target.link
        end
      end

      # Returns the path of the kept binary for this test, or nil when
      # no key can describe it.
      def path(target, source, rb, files)
        parts = files.sort.map { |name, bytes| [name, bytes.is_a?(Hash) ? "-> #{bytes.fetch(:symlink)}" : bytes] }
        return nil unless parts.all? { |_, bytes| bytes.is_a?(String) }

        key = Digest::SHA256.new
        [VERSION, Zr.runtime(target).digest, Zr::Digests.link, libraries, target.triple,
         *ENVIRONMENT.map { |name| ENV[name].to_s }, rb, source, *parts.flatten].each { |part| key << part.to_s << "\0" }
        Zr::Cache::Store.path(:binary, "#{key.hexdigest}#{".wasm" unless target.link}")
      end

      # The digest of the library files that a program can require and that
      # the runtime's digest does not cover: zr's libraries under runtime/ext
      # and runtime/lib, and the vendored library, whose lock has the
      # digest of each of its files. A program compiles in the ones it
      # requires, so an edit to one must miss.
      def libraries = @libraries ||= library_digest(Zr::Paths::ROOT)

      def library_digest(root)
        key = Digest::SHA256.new
        Dir[File.join(root, "runtime/{ext,lib}/**/*")].sort.each do |path|
          key << path << "\0" << File.binread(path) << "\0" if File.file?(path)
        end
        lock = File.join(root, "vendor/vendor.lock")
        key << File.binread(lock) if File.file?(lock)
        key.hexdigest
      end

      # Restores the kept binary to `bin`. Returns false when there is no
      # kept binary, or when it cannot restore the whole binary.
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

      # Keeps `bin`, the binary of `program` built in `work`. It keeps the
      # sparse form when the binary was linked with the cached objects,
      # and the whole binary otherwise.
      #
      # It does not keep a binary that contains the path of `work`. The
      # compiler resolves the path of a required file at compile time. At
      # run time, that binary looks in a directory that an earlier run
      # removed. The key does not include the build directory.
      def keep(kept, bin, program, work)
        return unless kept

        bytes = File.binread(bin)
        return if bytes.include?(work)

        # If a source file changed during the tier, the binary comes from
        # two versions of the tree, but the key identifies only one. So
        # do not keep it: `settled!` stops the tier and gives the file name.
        Zr.settled!
        objects = objects_of(program)
        sparse = !kept.end_with?(".wasm") && Native::Build.prelink_path(objects)
        Zr::Paths.write_atomic(kept, sparse ? sparse(bytes, objects) : bytes)
      end

      # Removes the least recently used binaries beyond their quota. Call
      # it once, before the workers start.
      def trim = Zr::Cache::Store.evict(kinds: [:binary])

      # Returns the cached objects that `program` links with: the runtime,
      # and eval support when the program evals (`Native::Build.program`).
      def objects_of(program)
        objects = [Native::Build.runtime_object(program.runtime)]
        objects << Native::Build.eval_support_object(program.evals) if program.evals
        objects
      end

      # A clone where the filesystem clones, else a copy.
      def copy(from, to)
        Obj::MachO::Skeleton.clone(from, to, File.size(from)) || FileUtils.cp(from, to)
      end

      # --- the sparse form ---------------------------------------------

      # Returns the sparse form of `bytes`, a binary linked with `objects`.
      # It leaves out each hole whose bytes are equal to the prelinked
      # image. The form is a head (binary size, objects, holes), then the
      # deflated bytes between the holes. At the fastest level, machine
      # code deflates to half its size at 10 ms per MB. Inflate takes a
      # third of that time.
      def sparse(bytes, objects)
        base = Native::Build.prelink(objects)
        holes = cuts(bytes, base).select { |at, size, name| bytes[at, size] == filling(base, name) }
        head = Marshal.dump({ size: bytes.bytesize, objects: objects.map { |o| File.basename(o, ".o") }, holes: holes })
        body = +"".b
        at = 0
        holes.each do |hole_at, size, _|
          body << bytes[at, hole_at - at]
          at = hole_at + size
        end
        body << bytes[at..]
        [head.bytesize].pack("Q<") + head + Zlib::Deflate.deflate(body, Zlib::BEST_SPEED)
      end

      # Returns the possible holes of a binary linked with `base`, each
      # `[at, size, name]`: the text after the header page, the `__DATA`
      # segment, and the parts of the two symbol tables that come from `base`.
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

      # Returns the bytes of the prelinked image for the hole `name`.
      def filling(base, name)
        case name
        when :text then base.blobs.fetch(:text)
        when :data then base.blobs.fetch(:data)
        when :symbols then base.symbols
        when :strings then base.strings
        else raise KeyError, "no hole named #{name}"
        end
      end

      # Writes the whole binary to `bin` from its sparse form in `kept`.
      # The text is cloned or kept in place, as the linker does
      # (`Skeleton.write_over`). Each other hole comes from the prelinked
      # image.
      def restore(kept, bin)
        File.open(kept, "rb") do |file|
          head = Marshal.load(file.read(file.read(8).to_s.unpack1("Q<").to_i))
          src = StringIO.new(Zlib::Inflate.inflate(file.read))
          objects = head.fetch(:objects).map { |key| Zr::Cache::Store.path(:object, key) }
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
