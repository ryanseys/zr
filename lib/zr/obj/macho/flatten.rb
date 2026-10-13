# frozen_string_literal: true

require "digest/sha1"
require "digest/sha2"
require_relative "../../refused"
require_relative "image"
require_relative "relink"

module Zr
  module Obj
    module MachO
      # A copy of a bundle that links ruby's shared library (the
      # `libruby.4.1.dylib` of a ruby built with --enable-shared) that a zr
      # binary can load with dlopen. Each import from libruby binds by flat
      # lookup, so dyld finds it in the binary's exported C API, as it does
      # for its other imports: mkmf links with `-undefined dynamic_lookup`
      # too. The binds are chained imports or LC_DYLD_INFO opcodes. The library's
      # load command becomes a weak one of a path that names no file, so
      # dyld loads no libruby and keeps the other dylibs' ordinals. The
      # code signature then hashes the changed pages again.
      #
      #   Flatten.libruby?(bytes)  # => true for such a bundle
      #   Flatten.call(bytes)      # => the copy's bytes
      #
      # The layout follows <mach-o/loader.h>, <mach-o/fixup-chains.h> and
      # <kern/cs_blobs.h>.
      module Flatten
        LC_CODE_SIGNATURE = 0x1D
        # A path that names no file: dyld leaves out a weak dylib that is
        # missing.
        NOWHERE = "/var/empty/zr-flat-libruby.dylib"
        # BIND_SPECIAL_DYLIB_FLAT_LOOKUP in an import's ordinal field, for
        # each field width.
        FLAT = { 8 => 0xFE, 16 => 0xFFFE }.freeze
        # Each chained import format: its size, its ordinal's width.
        IMPORTS = { Image::Chains::IMPORT => [4, 8], Image::Chains::IMPORT_ADDEND => [8, 8],
                    Image::Chains::IMPORT_ADDEND64 => [16, 16] }.freeze
        # The bind opcode that sets the flat lookup: the special ordinal's
        # low bits in the immediate.
        FLAT_OPCODE = Image::Opcodes::BIND_SET_DYLIB_SPECIAL_IMM | (Image::FLAT_LOOKUP & 0x0F)
        CSMAGIC_EMBEDDED_SIGNATURE = 0xFADE0CC0
        CSMAGIC_CODEDIRECTORY = 0xFADE0C02
        DIGESTS = { 1 => Digest::SHA1, 2 => Digest::SHA256 }.freeze

        module_function

        # Whether `bytes` are a Mach-O image that loads ruby's shared
        # library.
        #: (String bytes) -> bool
        def libruby?(bytes)
          return false unless bytes.unpack1("L<") == Image::MH_MAGIC_64 || bytes.unpack1("N") == Image::FAT_MAGIC

          Image.read(bytes).dylibs.any? { |name| Relink::LIBRUBY.match?(name) }
        end

        # The bytes of the copy: the arm64 image of `bytes`.
        #: (String bytes) -> String
        def call(bytes)
          out = Image.arm64_slice(bytes).b
          ordinal, command = libruby_command(out)
          fixups = chained_fixups(out)
          fixups ? rebind(out, fixups, ordinal) : rebind_opcodes(out, ordinal)
          weaken(out, command)
          resign(out)
          out
        end

        # The ordinal of the libruby dylib and the offset of its command.
        #: (String out) -> [Integer, Integer]
        def libruby_command(out)
          found = nil #: [Integer, Integer]?
          ordinal = 0
          each_command(out) do |cmd, at|
            next unless Image::DYLIB_COMMANDS.include?(cmd)

            ordinal += 1
            name_at = out.unpack1("L<", offset: at + 8) #: Integer
            name = out.byteslice(at + name_at, out.bytesize)&.unpack1("Z*") #: String
            found = [ordinal, at] if Relink::LIBRUBY.match?(name)
          end
          found or raise ArgumentError, "the image links no libruby"
        end

        # The file offset of the chained fixups, or nil for a bundle whose
        # binds are LC_DYLD_INFO opcodes.
        #: (String out) -> Integer?
        def chained_fixups(out)
          each_command(out) { |cmd, at| return out.unpack1("L<", offset: at + 8) if cmd == Image::LC_DYLD_CHAINED_FIXUPS }
          nil
        end

        # Each import whose dylib is `ordinal` binds by flat lookup.
        #: (String out, Integer fixups, Integer ordinal) -> void
        def rebind(out, fixups, ordinal)
          fields = out.unpack("L<6", offset: fixups) #: Array[Integer]
          imports_at, count, format = fields.values_at(2, 4, 5)
          size, bits = IMPORTS.fetch(format) { raise ArgumentError, "chained import format #{format}" }
          directive = size == 4 ? "L<" : "Q<"
          mask = (1 << bits) - 1
          count.times do |i|
            at = fixups + imports_at + (i * size)
            word = out.unpack1(directive, offset: at) #: Integer
            next unless word & mask == ordinal

            out.bytesplice(at, size == 16 ? 8 : size, [(word & ~mask) | FLAT.fetch(bits)].pack(directive))
          end
        end

        # The bind and lazy bind streams of LC_DYLD_INFO: an opcode that
        # sets dylib `ordinal` in its immediate sets the flat lookup, in a
        # byte of the same size. An ordinal past 15 takes a ULEB, which no
        # opcode of one byte replaces.
        #: (String out, Integer ordinal) -> void
        def rebind_opcodes(out, ordinal)
          ops = Image::Opcodes
          bind_streams(out).each do |span|
            c = Image::Cursor.over(out, span)
            while c.more?
              at = c.at
              op = c.byte
              case op & 0xF0
              when ops::BIND_SET_DYLIB_ORDINAL_IMM then out.setbyte(at, FLAT_OPCODE) if op & 0x0F == ordinal
              when ops::BIND_SET_DYLIB_ORDINAL_ULEB
                raise Zr::Refused, "a bundle loads libruby as its dylib #{ordinal}, past the 15 that zr rebinds" if c.uleb == ordinal
              when ops::BIND_SET_SYMBOL_TRAILING_FLAGS_IMM then c.cstring
              when ops::BIND_SET_ADDEND_SLEB then c.sleb
              when ops::BIND_SET_SEGMENT_AND_OFFSET_ULEB, ops::BIND_ADD_ADDR_ULEB, ops::BIND_DO_BIND_ADD_ADDR_ULEB then c.uleb
              when ops::BIND_DO_BIND_ULEB_TIMES_SKIPPING_ULEB then 2.times { c.uleb }
              when ops::BIND_DONE, ops::BIND_SET_DYLIB_SPECIAL_IMM, ops::BIND_SET_TYPE_IMM, ops::BIND_DO_BIND,
                   ops::BIND_DO_BIND_ADD_ADDR_IMM_SCALED then nil
              else raise ArgumentError, format("bind opcode 0x%02x", op)
              end
            end
          end
        end

        # The bind and the lazy bind streams of LC_DYLD_INFO.
        #: (String out) -> Array[Image::Span]
        def bind_streams(out)
          each_command(out) do |cmd, at|
            next unless cmd == Image::LC_DYLD_INFO || cmd == Image::LC_DYLD_INFO_ONLY

            fields = out.unpack("L<8", offset: at + 8) #: Array[Integer]
            return [Image::Span.new(offset: fields[2], size: fields[3]), Image::Span.new(offset: fields[6], size: fields[7])]
          end
          []
        end

        # The libruby command loads NOWHERE, weakly.
        #: (String out, Integer at) -> void
        def weaken(out, at)
          size, name_at = out.unpack("L<2", offset: at + 4) #: [Integer, Integer]
          room = size - name_at
          raise Zr::Refused, "the libruby path of a bundle is shorter than #{NOWHERE}" if NOWHERE.bytesize >= room

          out.bytesplice(at, 4, [Image::LC_LOAD_WEAK_DYLIB].pack("L<"))
          out.bytesplice(at + name_at, room, NOWHERE.b.ljust(room, "\0"))
        end

        # Each CodeDirectory hashes the pages again: the page hashes, its
        # code slots, cover the file up to its code limit. The special
        # slots hash the other blobs, which do not change.
        #: (String out) -> void
        def resign(out)
          signature = nil #: Integer?
          each_command(out) { |cmd, at| signature = out.unpack1("L<", offset: at + 8) if cmd == LC_CODE_SIGNATURE }
          raise Zr::Refused, "a bundle that links libruby has no code signature" unless signature

          magic, _length, count = out.unpack("L>3", offset: signature) #: [Integer, Integer, Integer]
          raise ArgumentError, "a code signature of magic 0x#{magic.to_s(16)}" unless magic == CSMAGIC_EMBEDDED_SIGNATURE

          count.times do |i|
            _type, offset = out.unpack("L>2", offset: signature + 12 + (i * 8)) #: [Integer, Integer]
            blob = signature + offset
            rehash(out, blob) if out.unpack1("L>", offset: blob) == CSMAGIC_CODEDIRECTORY
          end
        end

        #: (String out, Integer blob) -> void
        def rehash(out, blob)
          fields = out.unpack("L>9C4", offset: blob) #: Array[Integer]
          hash_offset, slots, limit = fields.values_at(4, 7, 8)
          hash_size, hash_type, _platform, page_bits = fields.last(4)
          digest = DIGESTS.fetch(hash_type) { raise ArgumentError, "a code signature of hash type #{hash_type}" }
          page = 1 << page_bits
          slots.times do |n|
            start = n * page
            hash = digest.digest(out.byteslice(start, [page, limit - start].min) || "")
            out.bytesplice(blob + hash_offset + (n * hash_size), hash_size, hash.byteslice(0, hash_size) || "")
          end
        end

        # Yields each load command's `cmd` and offset.
        #: (String out) { (Integer, Integer) -> void } -> void
        def each_command(out)
          ncmds = out.unpack1("L<", offset: 16) #: Integer
          at = 32
          ncmds.times do
            cmd, size = out.unpack("L<2", offset: at) #: [Integer, Integer]
            yield cmd, at
            at += size
          end
        end
      end
    end
  end
end
