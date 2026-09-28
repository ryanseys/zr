# frozen_string_literal: true

# IO::Buffer: a window on bytes, either its own or a String's. A buffer
# made `for` a String keeps that String and reads and writes its bytes
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
    FILE = 256
    # io_buffer.c keeps these two flags to itself.
    private_constant :SLICE, :FILE

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
      TYPES[type] or raise ArgumentError, +"Invalid type name!"
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

    # A window on a file's bytes, as mmap gives one. The bytes are read in
    # when the map is made; a shared mapping writes each change back to
    # the file at once, and a private one keeps its changes to itself.
    def self.map(file, size = nil, offset = 0, flags = 0)
      announce
      file_size = file.size
      raise ArgumentError, +"Invalid negative or zero file size!" if file_size <= 0

      unless size.nil?
        size = Primitive.zr_index_operand_m(size)
        raise ArgumentError, +"Size can't be zero!" if size.zero?
        raise ArgumentError, +"Size can't be larger than file size!" if size > file_size
      end
      offset = Primitive.zr_index_operand_m(offset)
      raise ArgumentError, +"Offset can't be negative!" if offset.negative?
      raise ArgumentError, +"Offset too large!" if offset >= file_size

      size ||= file_size - offset
      raise ArgumentError, +"Offset too large!" if file_size - offset < size

      buffer = allocate
      buffer.send(:mapped, file, size, offset, flags)
      buffer
    end

    def initialize(size = DEFAULT_SIZE, flags = 0)
      Buffer.send(:announce)
      size = Primitive.zr_index_operand_m(size)
      raise ArgumentError, +"Size can't be negative!" if size < 0

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
      @mapping = nil
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
      raise LockedError, +"Buffer is locked!" if locked?

      @bytes = nil
      @start = 0
      @size = 0
      @mapping = nil
      self
    end

    def locked
      raise LockedError, +"Buffer already locked!" if locked?

      @flags |= LOCKED
      begin
        yield self
      ensure
        @flags &= ~LOCKED
      end
    end

    def resize(size)
      raise LockedError, +"Cannot resize locked buffer!" if locked?
      raise AccessError, +"Cannot resize external buffer!" if external?

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
      part.send(:window, @bytes, @start + offset, length, (@flags & ~INTERNAL) | SLICE, @mapping)
      part
    end

    def get_string(offset = 0, length = nil, encoding = Encoding::BINARY)
      length = @size - offset if length.nil?
      bounds(offset, length)
      return "".b.force_encoding(encoding) if @bytes.nil?

      @bytes.byteslice(@start + offset, length).force_encoding(encoding)
    end

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
      written(offset, length)
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
      written(offset, width)
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

    # `each` walks one type across the window and gives the offset next
    # to each value; `values` returns only the values.
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
      written(offset, length)
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
      written(0, @size)
      self
    end

    # rb_io_buffer_read and the related methods. A non-blocking fiber gives
    # the transfer to its scheduler's hook when the scheduler has one.
    # Otherwise the system call runs over the rest of the buffer, again
    # until at least `length` bytes have moved or the stream ends. A
    # `length` of zero is exactly one call. Each returns the bytes moved,
    # or the negative errno. The p-forms take a file position and do not
    # move the stream's own position.
    def read(io, length = nil, offset = nil)
      io = Buffer.send(:io_of, io)
      length, offset = extent(length, offset)
      scheduler = IO.send(:scheduler_taking, :io_read)
      return scheduler.io_read(io, self, length, offset) if scheduler

      writable
      bounds(offset, length)
      fd = io.fileno
      moved(length, offset) do |at|
        io.send(:park_until, IO::READABLE) unless io.send(:nonblock_flag?)
        taken(Primitive.zr_io_read(fd, @size - at), at)
      end
    end

    def pread(io, from, length = nil, offset = nil)
      io = Buffer.send(:io_of, io)
      from = Primitive.zr_index_operand_m(from)
      length, offset = extent(length, offset)
      scheduler = IO.send(:scheduler_taking, :io_pread)
      return scheduler.io_pread(io, self, from, length, offset) if scheduler

      writable
      bounds(offset, length)
      fd = io.fileno
      moved(length, offset) { |at| taken(Primitive.zr_io_pread(fd, @size - at, from + at - offset), at) }
    end

    def write(io, length = nil, offset = nil)
      io = Buffer.send(:io_of, io)
      length, offset = extent(length, offset)
      scheduler = IO.send(:scheduler_taking, :io_write)
      return scheduler.io_write(io, self, length, offset) if scheduler

      bounds(offset, length)
      fd = io.send(:write_descriptor)
      text = get_string(offset)
      moved(length, offset) do |at|
        io.send(:park_until, IO::WRITABLE, fd) unless io.send(:nonblock_flag?)
        Primitive.zr_io_write_some(fd, text, at - offset, text.bytesize)
      end
    end

    def pwrite(io, from, length = nil, offset = nil)
      io = Buffer.send(:io_of, io)
      from = Primitive.zr_index_operand_m(from)
      length, offset = extent(length, offset)
      scheduler = IO.send(:scheduler_taking, :io_pwrite)
      return scheduler.io_pwrite(io, self, from, length, offset) if scheduler

      bounds(offset, length)
      fd = io.send(:write_descriptor)
      text = get_string(offset)
      moved(length, offset) do |at|
        rest = text.byteslice(at - offset, text.bytesize)
        rest.empty? ? 0 : Primitive.zr_io_pwrite(fd, rest, from + at - offset)
      end
    end

    # rb_io_buffer_new over memory that the runtime lends a scheduler hook:
    # locked while the hook has it, and freed when the hook returns.
    def self.lent(bytes, readonly: false)
      buffer = allocate
      buffer.send(:window, bytes, 0, bytes.bytesize, LOCKED | (readonly ? READONLY : 0))
      yield buffer
    ensure
      buffer&.send(:release)
    end

    def self.io_of(io)
      Primitive.attr! :hidden
      IO.try_convert(io) || raise(TypeError, "no implicit conversion of #{Primitive.zr_class_name_of(io)} into IO")
    end
    private_class_method :lent, :io_of

    def transfer
      other = Buffer.allocate
      other.send(:window, @bytes, @start, @size, @flags, @mapping)
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
                 @flags & FILE != 0 ? "FILE" : nil, shared? ? "SHARED" : nil, locked? ? "LOCKED" : nil, private? ? "PRIVATE" : nil,
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
        "#{format('0x%08x', base + span.first)}  #{hex}#{bytes.map { |b| b >= 32 && b < 127 ? b.chr : +'.' }.join}"
      end
      rows.join("\n")
    end

    private

    # The length and the offset a transfer names, and the length the
    # offset leaves where it names none.
    def extent(length, offset)
      Primitive.attr! :hidden
      offset = offset.nil? ? 0 : Primitive.zr_index_operand_m(offset)
      raise ArgumentError, +"Offset can't be negative!" if offset.negative?
      return [@size - offset, offset] if length.nil? && offset <= @size
      raise ArgumentError, +"The given offset is bigger than the buffer size!" if length.nil?

      length = Primitive.zr_index_operand_m(length)
      raise ArgumentError, +"Length can't be negative!" if length.negative?

      [length, offset]
    end

    # The system call the block makes at each place in turn, until
    # `length` bytes moved or one moved none: the bytes moved, or the
    # negative errno of the call that failed.
    def moved(length, offset)
      Primitive.attr! :hidden
      total = 0
      loop do
        result = yield(offset + total)
        return result if result.negative?
        return total if result.zero?

        total += result
        return total if total >= length
      end
    end

    # What a read gave, set in at `at`: its length, 0 at the end, or the
    # negative errno as it came.
    def taken(chunk, at)
      Primitive.attr! :hidden
      return chunk if chunk.is_a?(Integer)
      return 0 if chunk.nil?

      set_string(chunk, at)
    end

    # rb_io_buffer_free_locked.
    def release
      Primitive.attr! :hidden
      @flags &= ~LOCKED
      free
    end

    def external(string, readonly)
      Primitive.attr! :hidden
      @bytes = string
      @start = 0
      @size = string.bytesize
      @flags = EXTERNAL | SLICE | (readonly ? READONLY : 0)
      self
    end

    def window(bytes, start, size, flags, mapping = nil)
      Primitive.attr! :hidden
      @bytes = bytes
      @start = start
      @size = size
      @flags = flags
      @mapping = mapping
      self
    end

    # io_buffer_map_file: the file's bytes from `offset`, and where they
    # go back to when the mapping is shared and writable.
    def mapped(file, size, offset, flags)
      Primitive.attr! :hidden
      @bytes = file.pread(size, offset).b
      @start = 0
      @size = size
      @flags = MAPPED | FILE | (flags & READONLY)
      if flags & PRIVATE != 0
        @flags |= PRIVATE
      else
        @flags |= EXTERNAL | SHARED
        @mapping = [file, offset]
      end
      self
    end

    # A change to a shared mapping reaches the file, as it would through
    # the pages that mmap shares with the file.
    def written(offset, length)
      Primitive.attr! :hidden
      return if @mapping.nil? || length.zero?

      file, file_offset = @mapping
      file.pwrite(@bytes.byteslice(@start + offset, length), file_offset + @start + offset)
    end

    def allocate_like
      Primitive.attr! :hidden
      Buffer.allocate
    end

    def writable
      Primitive.attr! :hidden
      raise AccessError, +"Buffer is not writable!" if readonly?
      raise InvalidatedError, +"Buffer has been invalidated!" if null?
    end

    def bounds(offset, length, type = nil)
      Primitive.attr! :hidden
      raise ArgumentError, +"Offset can't be negative!" if offset < 0
      raise ArgumentError, +"Length can't be negative!" if length < 0
      return if offset + length <= @size

      raise ArgumentError, "Type extends beyond end of buffer! (offset=#{offset} > size=#{@size})" if type

      raise ArgumentError, +"Specified offset+length is bigger than the buffer size!"
    end

    # A mask repeats over the buffer, so a shorter one is fine and only
    # an empty one is refused.
    def mask(other)
      Primitive.attr! :hidden
      raise MaskError, +"Zero-length mask given!" if other.size.zero?

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
      written(0, @size)
      self
    end

    def masked(other)
      Primitive.attr! :hidden
      bytes = mask(other)
      get_string.bytes.each_with_index.map { |b, i| yield(b, bytes[i % bytes.size]) }.pack("C*")
    end
  end
end
