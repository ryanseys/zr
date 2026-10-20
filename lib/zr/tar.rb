# frozen_string_literal: true

module Zr
  # The ustar archive (POSIX.1-1988) that a runtime bundle is, inside
  # gzip: `tar -tzf` lists it. Only regular files, each with mode 0644,
  # owner 0 and time 0, so the same files make the same bytes. zr writes
  # its own because RubyGems' TarWriter needs RubyGems loaded, and zr also
  # runs under `--disable-gems`.
  module Tar
    BLOCK = 512

    # A name that does not fit the header's 100 bytes and 155 of prefix.
    class TooLong < ArgumentError; end

    # An archive that ends inside a header or a file.
    class Truncated < ArgumentError; end

    module_function

    # Writes the file `name` of `size` bytes to `io`; the block writes the
    # bytes to the io that it gets.
    #: (IO | Zlib::GzipWriter io, String name, Integer size) { (IO | Zlib::GzipWriter) -> void } -> void
    def add(io, name, size)
      io.write(header(name, size))
      yield io
      pad = -size % BLOCK
      io.write("\0" * pad) if pad.positive?
    end

    # The two empty blocks that end an archive.
    #: (IO | Zlib::GzipWriter io) -> void
    def finish(io) = io.write("\0" * (2 * BLOCK))

    # Yields the name and the size of each file of the archive in `io`,
    # in order, with `io` at the file's first byte. The block must read
    # exactly `size` bytes, or none: an unread file is skipped.
    #: (IO | Zlib::GzipReader io) { (String, Integer) -> void } -> void
    def each(io)
      loop do
        block = io.read(BLOCK)
        raise Truncated, "the archive ends without its last block" if block.nil? || block.bytesize < BLOCK
        break if block.count("\0") == BLOCK

        name, size = parse(block)
        before = io.respond_to?(:pos) ? io.pos : nil
        yield name, size
        read = before ? io.pos - before : size
        skip(io, size - read) if read < size
        skip(io, -size % BLOCK)
      end
    end

    #: (String name, Integer size) -> String
    def header(name, size)
      prefix, base = split(name)
      head = [base, "0000644", "0000000", "0000000", format("%011o", size), format("%011o", 0), " " * 8, "0", "",
              "ustar", "00", "", "", "", "", prefix, ""].pack("a100a8a8a8a12a12a8aa100a6a2a32a32a8a8a155a12")
      sum = head.sum(32) & 0o777777
      head[148, 8] = format("%06o\0 ", sum)
      head
    end

    # The prefix and name fields of `name`.
    #: (String name) -> [String, String]
    def split(name)
      return ["", name] if name.bytesize <= 100

      at = name.rindex("/", 155) or raise TooLong, "#{name} is too long for a tar header"
      prefix = name[0, at].to_s
      base = name[(at + 1)..].to_s
      raise TooLong, "#{name} is too long for a tar header" if prefix.bytesize > 155 || base.bytesize > 100

      [prefix, base]
    end

    # The name and size of a header block, after its checksum.
    #: (String block) -> [String, Integer]
    def parse(block)
      sum = block[148, 8].to_s.delete("\0 ").to_i(8)
      blank = block.dup
      blank[148, 8] = " " * 8
      raise ArgumentError, "a tar header's checksum is wrong" unless (blank.sum(32) & 0o777777) == sum
      raise ArgumentError, "the archive holds a #{block[156].inspect} entry, not a file" unless ["0", "\0"].include?(block[156])

      base = block[0, 100].to_s.unpack1("Z*").to_s
      prefix = block[345, 155].to_s.unpack1("Z*").to_s
      [prefix.empty? ? base : "#{prefix}/#{base}", Integer(block[124, 12].to_s.delete("\0 "), 8)]
    end

    #: (IO | Zlib::GzipReader io, Integer bytes) -> void
    def skip(io, bytes)
      while bytes.positive?
        chunk = io.read([bytes, 1 << 20].min) or raise Truncated, "the archive ends inside a file"
        bytes -= chunk.bytesize
      end
    end
  end
end
