# IO::Buffer: a window on bytes, either its own or a String's. A buffer
# made `for` a String holds that String and reads and writes its bytes
# in place, which is what ruby means by "the string is locked for the
# duration of the block".
class IO
  class Buffer
    include Comparable

    PAGE_SIZE = 16384
    DEFAULT_SIZE = 65536

    EXTERNAL = 1
    INTERNAL = 2
    MAPPED = 4
    SHARED = 8
    SLICE = 16
    LOCKED = 32
    PRIVATE = 64
    READONLY = 128

    LITTLE_ENDIAN = 4
    BIG_ENDIAN = 8
    HOST_ENDIAN = LITTLE_ENDIAN
    NETWORK_ENDIAN = BIG_ENDIAN

    class AccessError < RuntimeError; end
    class AllocationError < RuntimeError; end
    class InvalidatedError < RuntimeError; end
    class LockedError < RuntimeError; end
    class MaskError < ArgumentError; end

    # Each data type: its width in bytes, whether it is signed, whether
    # the low byte comes first, and whether it is a Float. An uppercase
    # name is network order, a lowercase one the host's.
    TYPES = {
      U8: [1, false, false, false], S8: [1, true, false, false],
      U16: [2, false, false, false], S16: [2, true, false, false],
      U32: [4, false, false, false], S32: [4, true, false, false],
      U64: [8, false, false, false], S64: [8, true, false, false],
      u16: [2, false, true, false], s16: [2, true, true, false],
      u32: [4, false, true, false], s32: [4, true, true, false],
      u64: [8, false, true, false], s64: [8, true, true, false],
      U128: [16, false, false, false], S128: [16, true, false, false],
      u128: [16, false, true, false], s128: [16, true, true, false],
      F32: [4, true, false, true], F64: [8, true, false, true],
      f32: [4, true, true, true], f64: [8, true, true, true]
    }.freeze
    private_constant :TYPES

    def self.size_of(type)
      return type.sum { |one| size_of(one) } if type.is_a?(Array)

      row(type)[0]
    end

    # Ruby says once per process that the class may still change, when
    # the experimental category is on at that first time.
    def self.announce
      return if @announced

      @announced = true
      return unless Warning[:experimental]

      warn("IO::Buffer is experimental and both the Ruby and C interface may change in the future!", uplevel: 2, category: :experimental)
    end
    private_class_method :announce

    def self.row(type)
      Primitive.attr! :hidden
      TYPES[type] or raise ArgumentError, "Invalid type name!"
    end
    private_class_method :row

    # `for` shares the String's bytes. Without a block the window is
    # read-only; with one it is writable for the length of the block.
    def self.for(string)
      buffer = allocate
      buffer.send(:external, string, !block_given?)
      return buffer unless block_given?

      begin
        yield buffer
      ensure
        buffer.free
      end
    end

    # The String a block filled, which is how ruby builds one.
    def self.string(length)
      text = "\0".b * length
      self.for(text) { |buffer| yield buffer }
      text
    end

    def self.map(file, size = nil, offset = 0, flags = 0)
      raise NotImplementedError, "IO::Buffer.map is not implemented yet"
    end

    def initialize(size = DEFAULT_SIZE, flags = 0)
      Buffer.send(:announce)
      size = Primitive.zr_index_operand_m(size)
      raise ArgumentError, "Size can't be negative!" if size < 0

      @bytes = "\0".b * size
      @start = 0
      @size = size
      @flags = INTERNAL | flags
    end

    attr_reader :size

    # A copy owns its bytes, so it is writable even when the original
    # is a read-only window on a String.
    def initialize_copy(other)
      @bytes = other.get_string
      @start = 0
      @size = @bytes.bytesize
      @flags = INTERNAL
      self
    end

    def external? = @flags & EXTERNAL != 0
    def internal? = @flags & INTERNAL != 0
    def mapped? = @flags & MAPPED != 0
    def shared? = @flags & SHARED != 0
    def private? = @flags & PRIVATE != 0
    def readonly? = @flags & READONLY != 0
    def locked? = @flags & LOCKED != 0
    # A buffer stays valid over `free` and `transfer`; only a mapping
    # that went away makes one invalid.
    def valid? = true
    def null? = @bytes.nil? || @size.zero?
    def empty? = @size.zero?

    # A freed buffer keeps its object and lets go of its bytes.
    def free
      raise LockedError, "Buffer is locked!" if locked?

      @bytes = nil
      @start = 0
      @size = 0
      self
    end

    def locked
      raise LockedError, "Buffer already locked!" if locked?

      @flags |= LOCKED
      begin
        yield self
      ensure
        @flags &= ~LOCKED
      end
    end

    def resize(size)
      raise LockedError, "Cannot resize locked buffer!" if locked?
      raise AccessError, "Cannot resize external buffer!" if external?

      @bytes = @bytes.byteslice(0, size).b
      @bytes << ("\0".b * (size - @bytes.bytesize)) if @bytes.bytesize < size
      @size = size
      self
    end

    # A window on the same bytes, offset into this one.
    def slice(offset = 0, length = nil)
      length = @size - offset if length.nil?
      bounds(offset, length)
      part = allocate_like
      part.send(:window, @bytes, @start + offset, length, (@flags & ~INTERNAL) | SLICE)
      part
    end

    def get_string(offset = 0, length = nil, encoding = Encoding::BINARY)
      length = @size - offset if length.nil?
      bounds(offset, length)
      return "".b.force_encoding(encoding) if @bytes.nil?

      @bytes.byteslice(@start + offset, length).force_encoding(encoding)
    end

    alias to_str get_string

    def set_string(string, offset = 0, length = nil, source_offset = 0)
      string = Primitive.zr_str_operand(string)
      length = string.bytesize - source_offset if length.nil?
      writable
      bounds(offset, length)
      i = 0
      while i < length
        @bytes.setbyte(@start + offset + i, string.getbyte(source_offset + i))
        i += 1
      end
      length
    end

    def get_value(type, offset)
      width, signed, host, float = Buffer.send(:row, type)
      bounds(offset, width, type)
      value = 0
      i = 0
      while i < width
        value = (value << 8) | @bytes.getbyte(@start + offset + (host ? width - 1 - i : i))
        i += 1
      end
      return [value].pack(width == 4 ? "N" : "Q>").unpack1(width == 4 ? "g" : "G") if float

      signed && value >= (1 << ((width * 8) - 1)) ? value - (1 << (width * 8)) : value
    end

    def set_value(type, offset, value)
      width, _signed, host, float = Buffer.send(:row, type)
      writable
      bounds(offset, width, type)
      value = float ? [value.to_f].pack(width == 4 ? "g" : "G").unpack1(width == 4 ? "N" : "Q>") : value.to_int
      i = 0
      while i < width
        @bytes.setbyte(@start + offset + (host ? i : width - 1 - i), (value >> (i * 8)) & 0xff)
        i += 1
      end
      offset + width
    end

    def get_values(types, offset = 0)
      types.map do |type|
        value = get_value(type, offset)
        offset += Buffer.size_of(type)
        value
      end
    end

    def set_values(types, offset, values)
      types.each_with_index do |type, i|
        set_value(type, offset, values[i])
        offset += Buffer.size_of(type)
      end
      offset
    end

    # `each` walks one type across the window and answers the offset
    # beside each value; `values` answers the values alone.
    def each(type = :U8, offset = 0, count = nil, &block)
      return to_enum(:each, type, offset, count) unless block

      width = Buffer.size_of(type)
      count = (@size - offset) / width if count.nil?
      i = 0
      while i < count
        at = offset + (i * width)
        yield at, get_value(type, at)
        i += 1
      end
      self
    end

    def values(type = :U8, offset = 0, count = nil)
      out = []
      each(type, offset, count) { |_at, value| out << value }
      out
    end

    def each_byte(offset = 0, count = nil, &block)
      return to_enum(:each_byte, offset, count) unless block

      each(:U8, offset, count) { |_at, value| yield value }
    end

    def clear(value = 0, offset = 0, length = nil)
      length = @size - offset if length.nil?
      writable
      bounds(offset, length)
      i = 0
      while i < length
        @bytes.setbyte(@start + offset + i, value)
        i += 1
      end
      self
    end

    # `copy` reads from `source` into this buffer.
    def copy(source, offset = 0, length = nil, source_offset = 0)
      raise TypeError, "wrong argument type #{conversion_name(source)} (expected IO::Buffer)" unless source.is_a?(Buffer)

      set_string(source.get_string, offset, length, source_offset)
    end

    def <=>(other)
      raise TypeError, "wrong argument type #{conversion_name(other)} (expected IO::Buffer)" unless other.is_a?(Buffer)

      get_string <=> other.get_string
    end

    def &(other) = combine(other) { |a, b| a & b }
    def |(other) = combine(other) { |a, b| a | b }
    def ^(other) = combine(other) { |a, b| a ^ b }
    def ~
      out = Buffer.new(@size)
      out.set_string(get_string.bytes.map { |b| (~b) & 0xff }.pack("C*")) unless @size.zero?
      out
    end

    def and!(other) = in_place(other) { |a, b| a & b }
    def or!(other) = in_place(other) { |a, b| a | b }
    def xor!(other) = in_place(other) { |a, b| a ^ b }

    def not!
      writable
      i = 0
      while i < @size
        @bytes.setbyte(@start + i, (~@bytes.getbyte(@start + i)) & 0xff)
        i += 1
      end
      self
    end

    # `length` is the least ruby insists on moving; the transfer covers
    # the rest of the buffer, which is what ruby's own loop does. The
    # p-forms name a file position and leave the stream's own where it
    # was.
    def read(io, length = nil, offset = 0) = set_string(io.read(@size - offset).to_s, offset)

    def write(io, length = nil, offset = 0) = io.write(get_string(offset, @size - offset))

    def pread(io, from, length = nil, offset = 0) = at(io, from) { read(io, length, offset) }

    def pwrite(io, from, length = nil, offset = 0) = at(io, from) { write(io, length, offset) }

    def transfer
      other = Buffer.allocate
      other.send(:window, @bytes, @start, @size, @flags)
      free
      other
    end

    # The header ruby shows: the address, the size, and the flags that
    # are set. A window on nothing shows NULL alone.
    def to_s
      shown = if null?
                ["NULL"]
              else
                [internal? ? "INTERNAL" : nil, external? ? "EXTERNAL" : nil, mapped? ? "MAPPED" : nil,
                 shared? ? "SHARED" : nil, locked? ? "LOCKED" : nil, private? ? "PRIVATE" : nil,
                 readonly? ? "READONLY" : nil, @flags & SLICE != 0 ? "SLICE" : nil].compact
              end
      "#<IO::Buffer #{format('0x%016x', object_id)}+#{@size}#{shown.empty? ? '' : " #{shown.join(' ')}"}>"
    end

    # The bytes go under the header, up to the first 256 of them.
    def inspect
      return to_s if null?
      return "#{to_s}\n#{hexdump}" if @size <= 256

      "#{to_s}\n#{hexdump(0, 256)}\n(and #{@size - 256} more bytes not printed)"
    end

    # 16 bytes a row: the offset, the bytes in hex in a column of a
    # fixed width, then the printable text.
    def hexdump(offset = 0, length = nil, width = 16, base = offset)
      length = @size - offset if length.nil?
      rows = (0...length).each_slice(width).map do |span|
        bytes = span.map { |i| get_value(:U8, offset + i) }
        hex = bytes.map { |b| format("%02x ", b) }.join.ljust(width * 3)
        "#{format('0x%08x', base + span.first)}  #{hex}#{bytes.map { |b| b >= 32 && b < 127 ? b.chr : '.' }.join}"
      end
      rows.join("\n")
    end

    private

    def at(io, from)
      Primitive.attr! :hidden
      held = io.tell
      begin
        io.seek(from)
        yield
      ensure
        io.seek(held)
      end
    end

    def external(string, readonly)
      Primitive.attr! :hidden
      @bytes = string
      @start = 0
      @size = string.bytesize
      @flags = EXTERNAL | SLICE | (readonly ? READONLY : 0)
      self
    end

    def window(bytes, start, size, flags)
      Primitive.attr! :hidden
      @bytes = bytes
      @start = start
      @size = size
      @flags = flags
      self
    end

    def allocate_like
      Primitive.attr! :hidden
      Buffer.allocate
    end

    def writable
      Primitive.attr! :hidden
      raise AccessError, "Buffer is not writable!" if readonly?
      raise InvalidatedError, "Buffer has been invalidated!" if null?
    end

    def bounds(offset, length, type = nil)
      Primitive.attr! :hidden
      raise ArgumentError, "Offset can't be negative!" if offset < 0
      raise ArgumentError, "Length can't be negative!" if length < 0
      return if offset + length <= @size

      raise ArgumentError, "Type extends beyond end of buffer! (offset=#{offset} > size=#{@size})" if type

      raise ArgumentError, "Specified offset+length is bigger than the buffer size!"
    end

    # A mask repeats over the buffer, so a shorter one is fine and only
    # an empty one is refused.
    def mask(other)
      Primitive.attr! :hidden
      raise MaskError, "Zero-length mask given!" if other.size.zero?

      other.get_string.bytes
    end

    def combine(other, &block)
      Primitive.attr! :hidden
      out = Buffer.new(@size)
      out.set_string(masked(other, &block)) unless @size.zero?
      out
    end

    def in_place(other, &block)
      Primitive.attr! :hidden
      text = masked(other, &block)
      writable
      i = 0
      while i < @size
        @bytes.setbyte(@start + i, text.getbyte(i))
        i += 1
      end
      self
    end

    def masked(other)
      Primitive.attr! :hidden
      bytes = mask(other)
      get_string.bytes.each_with_index.map { |b, i| yield(b, bytes[i % bytes.size]) }.pack("C*")
    end
  end
end
