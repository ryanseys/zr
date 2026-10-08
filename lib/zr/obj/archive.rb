# frozen_string_literal: true

require_relative "macho/object_file"

module Zr
  module Obj
    # Reads a static library: an `ar` archive of object files, in the BSD
    # form that Apple's tools write (`#1/len` names, a `__.SYMDEF` index)
    # or the GNU form (`/` index, `//` long names). A link takes from it
    # only the members that define a symbol it needs (`select`), as `ld`
    # does.
    class Archive
      MAGIC = "!<arch>\n"
      HEADER = 60

      # One object file of the archive. `offset` is where its header
      # starts, the number that the index gives.
      # @rbs skip
      Member = Data.define(:name, :offset, :bytes)

      attr_reader :members #: Array[Member]

      # The symbols that the index names, each with the member that
      # defines it.
      attr_reader :index #: Hash[String, Member]

      #: (String bytes) -> Archive
      def self.read(bytes) = new(bytes)

      #: (String bytes) -> void
      def initialize(bytes)
        raise ArgumentError, "not an ar archive" unless bytes.start_with?(MAGIC)

        @bytes = bytes
        @members = []
        @index = {}
        @long_names = ""
        entries = [] #: Array[[String, Integer]]
        each_member do |name, offset, data|
          case name
          when "__.SYMDEF", "__.SYMDEF SORTED" then entries = bsd_index(data, wide: false)
          when "__.SYMDEF_64", "__.SYMDEF_64 SORTED" then entries = bsd_index(data, wide: true)
          when "/", "/SYM64/" then entries = gnu_index(data, wide: name == "/SYM64/")
          when "//" then @long_names = data
          else @members << Member.new(name: gnu_name(name), offset: offset, bytes: data)
          end
        end
        by_offset = @members.to_h { |m| [m.offset, m] }
        entries.each { |symbol, offset| @index[symbol] ||= by_offset.fetch(offset) }
      end

      # The members that a link needs for the undefined symbols `roots`:
      # each member that defines one, then each member that defines a
      # symbol that a chosen member leaves undefined, until none is left.
      # They are in the archive's order.
      #: (Array[String] roots) -> Array[Member]
      def select(roots)
        # Keyed by offset: a Member's hash would read all of its bytes.
        chosen = {} #: Hash[Integer, true]
        wanted = roots.dup
        while (symbol = wanted.pop)
          member = @index[symbol]
          next if member.nil? || chosen.key?(member.offset)

          chosen[member.offset] = true
          wanted.concat(undefined_of(member))
        end
        @members.select { |m| chosen.key?(m.offset) }
      end

      private

      # Yields each member's name, the offset of its header, and its data.
      # A BSD name of the form `#1/len` is the first `len` bytes of the
      # data. A member starts on an even offset.
      #: () { (String, Integer, String) -> void } -> void
      def each_member
        at = MAGIC.bytesize
        while at + HEADER <= @bytes.bytesize
          header = @bytes.byteslice(at, HEADER) || ""
          raise ArgumentError, "a bad ar member header at #{at}" unless header.end_with?("`\n")

          name = (header.byteslice(0, 16) || "").rstrip
          size = Integer((header.byteslice(48, 10) || "").strip, 10)
          data = @bytes.byteslice(at + HEADER, size) || ""
          if name.start_with?("#1/")
            length = Integer(name.delete_prefix("#1/"), 10)
            name = (data.byteslice(0, length) || "").delete("\0")
            data = data.byteslice(length, size - length) || ""
          end
          yield name, at, data
          at += HEADER + size
          at += 1 if at.odd?
        end
      end

      # The `ranlib` entries of a BSD index: the byte size of the entries,
      # each a string offset and a member offset, then the strings.
      #: (String data, wide: bool) -> Array[[String, Integer]]
      def bsd_index(data, wide:)
        word = wide ? "Q<" : "L<"
        step = wide ? 8 : 4
        size = data.unpack1(word) #: Integer
        strings_at = step + size + step
        Array.new(size / (2 * step)) do |i|
          strx, offset = data.unpack("#{word}2", offset: step + (i * 2 * step)) #: [Integer, Integer]
          [cstring(data, strings_at + strx), offset]
        end
      end

      # A GNU index: a big-endian count, that many member offsets, then
      # the names, each ended by a NUL.
      #: (String data, wide: bool) -> Array[[String, Integer]]
      def gnu_index(data, wide:)
        word = wide ? "Q>" : "N"
        step = wide ? 8 : 4
        count = data.unpack1(word) #: Integer
        offsets = data.unpack("#{word}#{count}", offset: step) #: Array[Integer]
        names = (data.byteslice(step * (count + 1), data.bytesize) || "").split("\0")
        names.zip(offsets).map { |name, offset| [name, offset || 0] }
      end

      # A GNU member name: `/n` is at offset n of the long names, each of
      # which ends with `/\n`; a short name ends with `/`.
      #: (String name) -> String
      def gnu_name(name)
        if name.match?(%r{\A/\d+\z})
          start = Integer(name.delete_prefix("/"), 10)
          (@long_names.byteslice(start, @long_names.bytesize) || "").split("/\n").first || name
        else
          name.delete_suffix("/")
        end
      end

      #: (String data, Integer at) -> String
      def cstring(data, at)
        stop = data.index("\0", at) || data.bytesize
        data.byteslice(at, stop - at) || ""
      end

      # The external symbols that `member` uses and does not define.
      #: (Member member) -> Array[String]
      def undefined_of(member)
        object = MachO::ObjectFile.read(member.bytes)
        Array.new(object.count) { |i| i }.filter_map do |i|
          type = object.type(i)
          object.name(i) if type & MachO::ObjectFile::N_EXT != 0 && type & 0x0E == MachO::ObjectFile::N_UNDF
        end
      end
    end
  end
end
