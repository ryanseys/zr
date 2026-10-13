# frozen_string_literal: true

# IO::Buffer: the interface that all views on bytes share. The class has
# no allocator. Its two kinds are IO::Buffer::Storage, which manages the
# memory (its own memory, a file's, a String's or memory lent to it), and
# IO::Buffer::Slice, a view into another buffer. A slice keeps the offset
# from its source's view, so it follows that view when the source moves,
# shrinks or grows again. A Storage made `for` a String reads and writes
# that String's bytes in place, which is what ruby means by "the string is
# locked for the duration of the block".
class IO
  class Buffer
    include Comparable

    Primitive.zr_undef_allocator(self)

    VERSION = 4
    PAGE_SIZE = 16384
    MAP_ALIGNMENT = PAGE_SIZE
    DEFAULT_SIZE = 65536

    EXTERNAL = 1
    INTERNAL = 2
    MAPPED = 4
    SHARED = 8
    PRIVATE = 64
    READONLY = 128
    FILE = 256
    # io_buffer.c keeps the file flag to itself, and these sets of flags.
    FLAGS = EXTERNAL | INTERNAL | MAPPED | SHARED | PRIVATE | READONLY
    ALLOCATION = INTERNAL | MAPPED
    MAPPING = SHARED | PRIVATE
    private_constant :FILE, :FLAGS, :ALLOCATION, :MAPPING

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

    # Bytes at an address outside the heap: the bytes of a buffer that is
    # MAPPED and SHARED, anonymous memory that mmap shares with a forked
    # child (MAP_SHARED), so each side sees the other's writes; or memory
    # that C gives a buffer (rb_io_buffer_new). It reads and writes as the
    # String that holds the bytes of any other buffer does.
    class RawMemory
      Primitive.attr! :hidden

      # Shared memory, or nil where the host cannot share memory. It goes
      # back to the system when nothing holds it.
      def self.map(size)
        address = Primitive.zr_mem_shared_map(size) or return nil

        memory = new(address, size)
        ObjectSpace.define_finalizer(memory, unmapper(address, size))
        memory
      end

      # C's memory, which the buffer owns when the flags say that malloc
      # (INTERNAL) or mmap (MAPPED) made it, and frees as ruby does.
      def self.at(address, size, flags)
        memory = new(address, size)
        if flags & INTERNAL != 0
          ObjectSpace.define_finalizer(memory, freer(address))
        elsif flags & MAPPED != 0
          ObjectSpace.define_finalizer(memory, unmapper(address, size))
        end
        memory
      end

      # Finalizers that hold no reference to the memory's object.
      def self.unmapper(address, size) = proc { Primitive.zr_mem_unmap(address, size) }
      def self.freer(address) = proc { Primitive.zr_mem_free(address) }

      def initialize(address, size)
        @address = address
        @size = size
      end

      attr_reader :address

      def bytesize = @size
      def getbyte(index) = Primitive.zr_mem_getbyte(@address + index)
      def setbyte(index, byte) = Primitive.zr_mem_setbyte(@address + index, byte & 0xff)
      def byteslice(start, length) = Primitive.zr_ffi_read(@address + start, length)

      def bytesplice(start, length, bytes)
        Primitive.zr_ffi_write(@address + start, bytes, 0, length)
        self
      end
    end
    private_constant :RawMemory

    # The fields of ruby's structs rb_io_buffer_view and _storage: hidden
    # state, so a buffer has no instance variables, and state that freeze
    # does not lock, as C frees and locks a frozen buffer. The methods
    # check freeze where ruby's do (unfrozen!).
    class Fields
      Primitive.attr! :hidden

      attr_accessor :memory, :offset, :size, :flags, :source, :mapping, :locks

      def initialize(memory: nil, offset: 0, size: 0, flags: 0, source: nil, mapping: nil)
        @memory = memory
        @offset = offset
        @size = size
        @flags = flags
        @source = source
        @mapping = mapping
        @locks = 0
      end
    end
    private_constant :Fields

    # IO::Buffer.new makes a Storage; a subclass makes its own kind.
    def self.new(...)
      return Storage.new(...) if equal?(Buffer)

      super(...)
    end

    def self.size_of(type)
      return type.sum { |one| size_of(one) } if type.is_a?(Array)

      row(type)[0]
    end

    # `for` shares the String's bytes. Without a block the window is on a
    # frozen copy (or the String itself when it is frozen) and read-only;
    # with one it is on the String, writable unless the String is frozen,
    # for the length of the block.
    def self.for(string)
      klass = storage_class
      Buffer.send(:announce)
      string = Primitive.zr_str_operand(string)
      return Primitive.zr_class_build(klass).send(:over, string.frozen? ? string : string.dup.freeze, READONLY) unless block_given?

      buffer = nil
      locked = false
      begin
        buffer = Primitive.zr_class_build(klass).send(:over, string, 0)
        unless string.frozen?
          Primitive.zr_str_locktmp_m(string)
          locked = true
        end
        yield buffer
      ensure
        buffer&.free
        Primitive.zr_str_unlocktmp_m(string) if locked
      end
    end

    # The String a block filled, which is how ruby builds one.
    def self.string(length)
      klass = storage_class
      Buffer.send(:announce)
      text = "\0".b * length
      klass.for(text) { |buffer| yield buffer }
      text
    end

    # A window on a file's bytes, as mmap gives one. The bytes are read in
    # when the map is made; a shared mapping writes each change back to
    # the file at once, and a private one keeps its changes to itself.
    def self.map(file, size = nil, offset = (no_offset = true; 0), flags = 0)
      klass = storage_class
      Buffer.send(:announce)
      unless file.is_a?(IO) || file.respond_to?(:fileno)
        raise TypeError, "expected IO or #fileno, #{Primitive.zr_class_name_of(file)} given"
      end
      file_size = file.size
      raise ArgumentError, +"Invalid negative or zero file size!" if file_size <= 0

      sized = !size.nil?
      if sized
        size = index_operand(size, "Size")
        raise ArgumentError, +"Size can't be zero!" if size.zero?
        raise ArgumentError, "Size (#{size}) can't be larger than file size (#{file_size})" if size > file_size
      else
        size = file_size
      end
      unless no_offset
        offset = Primitive.zr_index_operand_m(offset)
        raise ArgumentError, "Offset (#{offset}) can't be negative!" if offset.negative?
        raise ArgumentError, "Offset (#{offset}) can't be larger than file size (#{file_size})" if offset >= file_size

        if !sized
          size = file_size - offset
        elsif file_size - offset < size
          largest = (file_size - size) / MAP_ALIGNMENT * MAP_ALIGNMENT
          raise ArgumentError, "Offset (#{offset}) can't be larger than #{largest} for requested size (#{size})"
        end
      end
      flags = map_flags(flags_operand(flags))
      unless (offset % MAP_ALIGNMENT).zero?
        raise ArgumentError, "Offset (#{offset}) must be a multiple of IO::Buffer::MAP_ALIGNMENT (#{MAP_ALIGNMENT})!"
      end

      Primitive.zr_class_build(klass).send(:mapped, file, size, offset, flags)
    end

    # rb_io_buffer_new_locked over memory that the runtime lends a
    # scheduler hook: locked while the hook has it, and freed when the
    # hook returns.
    def self.lent(bytes, readonly: false)
      buffer = Primitive.zr_class_build(Storage).send(:borrowed, bytes, readonly ? READONLY : 0)
      yield buffer
    ensure
      buffer&.send(:free_locked)
    end

    # Ruby says once per process that the class may still change, when
    # the experimental category is on at that first time. The flag is
    # Buffer's, whichever class makes the buffer.
    def self.announce
      return if @announced

      @announced = true
      return unless Warning[:experimental]

      warn("IO::Buffer is experimental and both the Ruby and C interface may change in the future!", uplevel: 2, category: :experimental)
    end

    # io_buffer_storage_class: the class that `for`, `string` and `map`
    # make, which is Storage or a class under it.
    def self.storage_class
      Primitive.attr! :hidden
      return Storage if equal?(Buffer)
      return self if self <= Storage

      raise TypeError, +"Storage factory requires IO::Buffer::Storage!"
    end

    # io_flags_for_size: a page or more is mapped, less is internal.
    def self.flags_for(size)
      Primitive.attr! :hidden
      size >= PAGE_SIZE ? MAPPED : INTERNAL
    end

    # io_buffer_flags_for_new: no flags for no memory, and an allocation
    # kind that the size gives when the flags name none.
    def self.new_flags(flags, size)
      Primitive.attr! :hidden
      return 0 if size.zero?

      flags |= flags & MAPPING == 0 ? flags_for(size) : MAPPED if flags & ALLOCATION == 0
      raise ArgumentError, +"Flags can't include both IO::Buffer::INTERNAL and IO::Buffer::MAPPED!" if flags & ALLOCATION == ALLOCATION
      raise ArgumentError, +"IO::Buffer::EXTERNAL can't be used with IO::Buffer.new!" if flags & EXTERNAL != 0
      if flags & MAPPING != 0 && flags & ALLOCATION != MAPPED
        raise ArgumentError, +"IO::Buffer::SHARED and IO::Buffer::PRIVATE require IO::Buffer::MAPPED!"
      end
      raise ArgumentError, +"Flags can't include both IO::Buffer::SHARED and IO::Buffer::PRIVATE!" if flags & MAPPING == MAPPING

      flags
    end

    # io_buffer_flags_for_map: the flags a file mapping takes.
    def self.map_flags(flags)
      Primitive.attr! :hidden
      raise ArgumentError, +"IO::Buffer::INTERNAL can't be used with IO::Buffer.map!" if flags & INTERNAL != 0
      raise ArgumentError, +"IO::Buffer::EXTERNAL can't be used with IO::Buffer.map!" if flags & EXTERNAL != 0
      raise ArgumentError, +"Flags can't include both IO::Buffer::SHARED and IO::Buffer::PRIVATE!" if flags & MAPPING == MAPPING

      flags
    end

    # io_buffer_extract_size: an Integer that is not negative.
    def self.size_operand(size)
      Primitive.attr! :hidden
      raise TypeError, +"not an Integer" unless Integer === size
      raise ArgumentError, +"Size can't be negative!" if size.negative?

      size
    end

    # io_buffer_extract_flags: the flags that are known; others are left
    # out, as a later flag may be.
    def self.flags_operand(flags)
      Primitive.attr! :hidden
      raise TypeError, +"not an Integer" unless Integer === flags
      raise ArgumentError, +"Flags can't be negative!" if flags.negative?

      flags & FLAGS
    end

    # An offset, a length, an amount or a count: an Integer that is not
    # negative, which the error names.
    def self.index_operand(value, name)
      Primitive.attr! :hidden
      value = Primitive.zr_index_operand_m(value)
      raise ArgumentError, "#{name} can't be negative!" if value.negative?

      value
    end

    def self.row(type)
      Primitive.attr! :hidden
      raise TypeError, "wrong argument type #{Primitive.zr_class_name_of(type)} (expected Symbol)" unless type.is_a?(Symbol)

      TYPES[type] or raise ArgumentError, +"Invalid type name!"
    end

    def self.io_of(io)
      Primitive.attr! :hidden
      IO.try_convert(io) || raise(TypeError, "no implicit conversion of #{Primitive.zr_class_name_of(io)} into IO")
    end
    private_class_method :lent, :announce, :storage_class, :flags_for, :new_flags, :map_flags,
                         :size_operand, :flags_operand, :index_operand, :row, :io_of

    def size = fields.size

    def fields
      Primitive.attr! :hidden
      Primitive.zr_hidden_get(self, :__fields__) || Primitive.zr_state_set(self, :__fields__, Fields.new)
    end
    private :fields

    def source = view[0]

    # A view without a source is valid, null or not. A view on a source is
    # valid while its range fits in the source's current view.
    def valid? = !resolve.nil?

    def null?
      memory, = resolve
      memory.nil?
    end

    def empty? = size.zero?

    # A view is read-only when it says so, or when a source under it does
    # or is frozen.
    def readonly?
      holder = self
      loop do
        return true if holder.send(:flags) & READONLY != 0

        source = holder.send(:view)[0]
        return false if source.nil?
        return true if source.frozen?
        return false if source.is_a?(String)

        holder = source
      end
    end

    # The lock belongs to the Storage under all the slices.
    def locked?
      return false if is_a?(Slice) && source.nil?

      owner.send(:locks).positive?
    end

    # Locks may nest; free, resize and transfer refuse while one is held.
    def locked
      readable
      holder = owner
      holder.send(:lock!)
      begin
        yield self
      ensure
        holder.send(:unlock!)
      end
    end

    def slice(offset = nil, length = nil)
      offset, length = extent(offset, length)
      within(offset, length)
      Primitive.zr_class_build(Slice).send(:attach, self, offset, length)
    end

    # rb_io_buffer_advance: a view that owns no memory moves its start on
    # by `amount` and gets shorter by as much.
    def advance(amount)
      unfrozen!
      amount = Buffer.send(:index_operand, amount, "Amount")
      unfrozen!
      raise AccessError, +"Cannot advance an owning buffer!" if owning?
      raise InvalidatedError, +"Buffer has been invalidated!" unless valid?
      raise ArgumentError, +"Advance amount exceeds buffer size!" if amount > size

      moved(amount)
      self
    end

    def get_string(offset = nil, length = nil, encoding = Encoding::BINARY)
      offset, length = extent(offset, length)
      # The encoding converts first: its conversion may change this buffer.
      encoding = Encoding.find(Primitive.zr_str_operand(encoding)) unless encoding.is_a?(Encoding)
      memory, start = readable
      raise ArgumentError, +"Specified offset+length is bigger than the buffer size!" if offset + length > size
      return "".b.force_encoding(encoding) if memory.nil?

      memory.byteslice(start + offset, length).force_encoding(encoding)
    end

    def set_string(string, offset = nil, length = nil, source_offset = nil)
      modifiable
      string = Primitive.zr_str_operand(string)
      copied(string, string.bytesize, offset, length, source_offset)
    end

    # `copy` reads from `source` into this buffer.
    def copy(source, offset = nil, length = nil, source_offset = nil)
      raise TypeError, "wrong argument type #{conversion_name(source)} (expected IO::Buffer)" unless source.is_a?(Buffer)

      memory, start = source.send(:readable)
      modifiable
      bytes = memory.nil? ? "".b : memory.byteslice(start, source.size)
      copied(bytes, bytes.bytesize, offset, length, source_offset)
    end

    def get_value(type, offset)
      offset = Buffer.send(:index_operand, offset, "Offset")
      memory, start = readable
      value_at(memory, start, type, offset)
    end

    def get_values(types, offset)
      offset = Buffer.send(:index_operand, offset, "Offset")
      memory, start = readable
      raise ArgumentError, +"Argument buffer_types should be an array!" unless types.is_a?(Array)

      types.map do |type|
        value = value_at(memory, start, type, offset)
        offset += Buffer.size_of(type)
        value
      end
    end

    def set_value(type, offset, value)
      modifiable
      put(type, Buffer.send(:index_operand, offset, "Offset"), value)
    end

    def set_values(types, offset, values)
      modifiable
      raise ArgumentError, +"Argument buffer_types should be an array!" unless types.is_a?(Array)

      offset = Buffer.send(:index_operand, offset, "Offset")
      raise ArgumentError, +"Argument values should be an array!" unless values.is_a?(Array)
      raise ArgumentError, +"Argument buffer_types and values should have the same length!" unless types.size == values.size

      types.each_index { |i| offset = put(types[i], offset, values[i]) }
      offset
    end

    # `each` walks one type across the window and gives the offset next
    # to each value; `values` returns only the values. The buffer stays
    # locked while `each` yields.
    def each(type = :U8, offset = nil, count = nil, &block)
      return to_enum(:each, type, offset, count) unless block

      locked_over do |memory, start|
        offset, count = counted(type, offset, count)
        count.times do
          at = offset
          value = value_at(memory, start, type, at)
          offset += Buffer.size_of(type)
          yield at, value
        end
      end
    end

    def values(type = :U8, offset = nil, count = nil)
      memory, start = readable
      offset, count = counted(type, offset, count)
      Array.new(count) do |i|
        value_at(memory, start, type, offset + (i * Buffer.size_of(type)))
      end
    end

    def each_byte(offset = nil, count = nil, &block)
      return to_enum(:each_byte, offset, count) unless block

      locked_over do |memory, start|
        offset, count = counted(:U8, offset, count)
        raise ArgumentError, +"Specified offset+count is bigger than the buffer size!" if offset + count > size

        count.times { |i| yield memory.getbyte(start + offset + i) }
      end
    end

    def clear(value = 0, offset = nil, length = nil)
      byte = Primitive.zr_index_operand_m(value) & 0xff
      offset, length = extent(offset, length)
      modifiable
      within(offset, length)
      store(writable, offset, byte.chr * length)
      self
    end

    # The sizes compare first, then the bytes, as memcmp orders them.
    def <=>(other)
      memory, start = readable
      raise TypeError, "wrong argument type #{conversion_name(other)} (expected IO::Buffer)" unless other.is_a?(Buffer)

      other_memory, other_start = other.send(:readable)
      return size <=> other.size unless size == other.size
      return 0 if size.zero?

      mine = memory.byteslice(start, size)
      theirs = other_memory.byteslice(other_start, size)
      i = 0
      i += 1 while i < size && mine.getbyte(i) == theirs.getbyte(i)
      i == size ? 0 : mine.getbyte(i) - theirs.getbyte(i)
    end

    def &(mask) = combined(mask) { |a, b| a & b }
    def |(mask) = combined(mask) { |a, b| a | b }
    def ^(mask) = combined(mask) { |a, b| a ^ b }

    def ~
      memory, start = readable
      fresh(Array.new(size) { |i| ~memory.getbyte(start + i) & 0xff }.pack("C*"))
    end

    def and!(mask) = in_place(mask) { |a, b| a & b }
    def or!(mask) = in_place(mask) { |a, b| a | b }
    def xor!(mask) = in_place(mask) { |a, b| a ^ b }

    def not!
      modifiable
      target = writable
      memory, start = target
      store(target, 0, Array.new(size) { |i| ~memory.getbyte(start + i) & 0xff }.pack("C*"))
      self
    end

    # The bits that are set in the range.
    def bit_count(offset = nil, length = nil)
      offset, length = extent(offset, length)
      memory, start = within(offset, length)
      return 0 if length.zero?

      memory.byteslice(start + offset, length).each_byte.sum(&:bit_count)
    end

    # rb_io_buffer_read and the related methods: one system call over at
    # most `length` bytes of the buffer from `offset`, or the scheduler's
    # hook where a non-blocking fiber's scheduler has one. Each returns
    # the bytes moved, which may be fewer than `length`, or the negative
    # errno. The p-forms take a file position and leave the stream's own
    # position alone.
    def read(io, offset = nil, length = nil)
      offset, length = extent(offset, length)
      io = Buffer.send(:io_of, io)
      modifiable
      within(offset, length)
      return 0 if length.zero?

      scheduler = IO.send(:scheduler_taking, :io_read)
      return scheduler.io_read(io, self, offset, length) if scheduler

      target = writable
      fd = io.fileno
      io.send(:park_until, IO::READABLE) unless io.send(:nonblock_flag?)
      taken(target, offset, Primitive.zr_io_read(fd, length))
    end

    def pread(io, from, offset = nil, length = nil)
      from = Primitive.zr_index_operand_m(from)
      offset, length = extent(offset, length)
      io = Buffer.send(:io_of, io)
      modifiable
      within(offset, length)
      return 0 if length.zero?

      scheduler = IO.send(:scheduler_taking, :io_pread)
      return scheduler.io_pread(io, self, from, offset, length) if scheduler

      target = writable
      taken(target, offset, Primitive.zr_io_pread(io.fileno, length, from))
    end

    def write(io, offset = nil, length = nil)
      offset, length = extent(offset, length)
      io = Buffer.send(:io_of, io)
      within(offset, length)
      return 0 if length.zero?

      scheduler = IO.send(:scheduler_taking, :io_write)
      return scheduler.io_write(io, self, offset, length) if scheduler

      memory, start = readable
      fd = io.send(:write_descriptor)
      io.send(:park_until, IO::WRITABLE, fd) unless io.send(:nonblock_flag?)
      text = memory.byteslice(start + offset, length)
      Primitive.zr_io_write_some(fd, text, 0, text.bytesize)
    end

    def pwrite(io, from, offset = nil, length = nil)
      from = Primitive.zr_index_operand_m(from)
      offset, length = extent(offset, length)
      io = Buffer.send(:io_of, io)
      within(offset, length)
      return 0 if length.zero?

      scheduler = IO.send(:scheduler_taking, :io_pwrite)
      return scheduler.io_pwrite(io, self, from, offset, length) if scheduler

      memory, start = readable
      Primitive.zr_io_pwrite(io.send(:write_descriptor), memory.byteslice(start + offset, length), from)
    end

    # The header ruby shows: the class, the address, the size, NULL where
    # there is no memory, the flags that are set, SLICE where the bytes
    # belong to another buffer or a String, and INVALID where they no
    # longer fit in it. The address of memory is the identity of its
    # object.
    def to_s
      memory, start = resolve
      address = memory.nil? ? 0 : (memory.object_id * 16) + start
      flags = send(:flags)
      shown = ["#<#{Primitive.zr_class_path(Primitive.zr_real_class(self))} #{format('0x%016x', address)}+#{size}"]
      shown << "NULL" if memory.nil?
      shown << "EXTERNAL" if flags & EXTERNAL != 0
      shown << "INTERNAL" if flags & INTERNAL != 0
      shown << "MAPPED" if flags & MAPPED != 0
      shown << "FILE" if flags & FILE != 0
      shown << "SHARED" if flags & SHARED != 0
      shown << "LOCKED" if locked?
      shown << "PRIVATE" if flags & PRIVATE != 0
      shown << "READONLY" if readonly?
      shown << "SLICE" unless source.nil?
      shown << "INVALID" unless valid?
      "#{shown.join(' ')}>"
    end

    # The bytes go under the header, up to the first 256 of them.
    def inspect
      memory, start = resolve
      return to_s if memory.nil?

      shown = [size, 256].min
      text = [to_s, *rows(memory, start, 0, shown, 16)].join("\n")
      size > 256 ? "#{text}\n(and #{size - 256} more bytes not printed)" : text
    end

    # `width` bytes a row: the offset, the bytes in hex in a column of a
    # fixed width, then the printable text. A null buffer has no dump.
    def hexdump(offset = nil, length = nil, width = 16)
      offset, length = extent(offset, length)
      width = Buffer.send(:index_operand, width, "Width")
      raise ArgumentError, +"Width must be at least 1!" if width < 1
      raise ArgumentError, +"Width must be at most 1024!" if width > 1024

      memory, start = within(offset, length)
      return nil if memory.nil?

      rows(memory, start, offset, length, width).join("\n")
    end

    private

    # rb_check_frozen with the message that names the buffer.
    def unfrozen!
      Primitive.attr! :hidden
      return unless frozen?

      raise FrozenError.new("can't modify frozen #{Primitive.zr_class_path(Primitive.zr_real_class(self))}: #{inspect}", receiver: self)
    end

    # io_buffer_try_get_bytes: the memory that holds this view's bytes,
    # where they start in it, and the Storage that manages it; nil where
    # a range no longer fits in its source. Each slice keeps its offset
    # from its source's view, so the walk adds them up.
    def resolve
      Primitive.attr! :hidden
      holder = self
      source, offset, length = view
      start = 0
      while source.is_a?(Buffer)
        outer_source, outer_offset, outer_length = source.send(:view)
        return nil if offset > outer_length || length > outer_length - offset

        start += offset
        holder = source
        source = outer_source
        offset = outer_offset
        length = outer_length
      end
      return holder.send(:base, start) if source.nil?
      return nil if offset > source.bytesize || length > source.bytesize - offset

      [source, start + offset, holder]
    end

    # rb_io_buffer_get_bytes_for_reading: the bytes of a valid view.
    def readable
      Primitive.attr! :hidden
      resolve or raise InvalidatedError, +"Buffer has been invalidated!"
    end

    # rb_io_buffer_get_bytes_for_writing: the bytes of a valid view that
    # is not read-only.
    def writable
      Primitive.attr! :hidden
      raise AccessError, +"Buffer is not writable!" if readonly?

      resolve or raise InvalidatedError, +"Buffer is invalid!"
    end

    # get_io_buffer_view_for_writing: a buffer that is not frozen, with
    # bytes that it may write.
    def modifiable
      Primitive.attr! :hidden
      unfrozen!
      writable
    end

    # io_buffer_validate_range: the bytes of a valid view that holds
    # `length` bytes from `offset`.
    def within(offset, length)
      Primitive.attr! :hidden
      bytes = readable
      raise ArgumentError, +"Specified offset+length is bigger than the buffer size!" if offset + length > size

      bytes
    end

    # io_buffer_extract_offset_length: the offset, 0 where none is given,
    # and the length, which is the rest of the buffer where none is given.
    def extent(offset, length)
      Primitive.attr! :hidden
      offset = offset.nil? ? 0 : Buffer.send(:index_operand, offset, "Offset")
      return [offset, Buffer.send(:index_operand, length, "Length")] unless length.nil?
      raise ArgumentError, +"The given offset is bigger than the buffer size!" if offset > size

      [offset, size - offset]
    end

    # io_buffer_extract_offset_count: the offset, and the count of values
    # of `type` that fit after it where none is given.
    def counted(type, offset, count)
      Primitive.attr! :hidden
      offset = offset.nil? ? 0 : Buffer.send(:index_operand, offset, "Offset")
      return [offset, Buffer.send(:index_operand, count, "Count")] unless count.nil?
      raise ArgumentError, +"The given offset is bigger than the buffer size!" if offset > size

      [offset, (size - offset) / Buffer.size_of(type)]
    end

    # The block gets the bytes while the Storage under this view is
    # locked, so it cannot be freed or resized meanwhile.
    def locked_over
      Primitive.attr! :hidden
      holder = owner
      holder.send(:lock!)
      begin
        memory, start = readable
        yield memory, start
      ensure
        holder.send(:unlock!)
      end
      self
    end

    # Puts `bytes` in at `offset` of the bytes that `writable` gave, which
    # a shared file mapping then writes back to its file.
    def store(target, offset, bytes)
      Primitive.attr! :hidden
      memory, start, holder = target
      at = start + offset
      if memory.is_a?(RawMemory)
        memory.bytesplice(at, bytes.bytesize, bytes)
      else
        i = 0
        while i < bytes.bytesize
          memory.setbyte(at + i, bytes.getbyte(i))
          i += 1
        end
      end
      holder.send(:written, at, bytes.bytesize)
    end

    # io_buffer_copy_from: `length` bytes of `bytes` from `source_offset`,
    # put in at `offset`. The bytes are read first, so a source that
    # overlaps this buffer copies as memmove does.
    def copied(bytes, source_size, offset, length, source_offset)
      Primitive.attr! :hidden
      offset = offset.nil? ? 0 : Buffer.send(:index_operand, offset, "Offset")
      source_offset = source_offset.nil? ? 0 : Buffer.send(:index_operand, source_offset, "Offset")
      raise ArgumentError, +"The given source offset is bigger than the source itself!" if source_offset > source_size

      length = length.nil? ? source_size - source_offset : Buffer.send(:index_operand, length, "Length")
      target = writable
      raise ArgumentError, +"Specified offset+length is bigger than the buffer size!" if offset + length > size
      raise ArgumentError, +"The computed source range exceeds the size of the source buffer!" if source_offset + length > source_size
      return length if length.zero?

      store(target, offset, bytes.byteslice(source_offset, length))
      length
    end

    # What a read gave, set in at `offset`: its length, 0 at the end, or
    # the negative errno as it came.
    def taken(target, offset, chunk)
      Primitive.attr! :hidden
      return chunk if chunk.is_a?(Integer)
      return 0 if chunk.nil?

      store(target, offset, chunk)
      chunk.bytesize
    end

    def value_at(memory, start, type, offset)
      Primitive.attr! :hidden
      width, signed, host, float = Buffer.send(:row, type)
      fits(offset, width)
      value = 0
      i = 0
      while i < width
        value = (value << 8) | memory.getbyte(start + offset + (host ? width - 1 - i : i))
        i += 1
      end
      return [value].pack(width == 4 ? "N" : "Q>").unpack1(width == 4 ? "g" : "G") if float

      signed && value >= (1 << ((width * 8) - 1)) ? value - (1 << (width * 8)) : value
    end

    # io_buffer_write_<type>: the range is checked, then the value
    # converts, then the range is checked again, as the conversion may
    # change this buffer. Returns the offset after the value.
    def put(type, offset, value)
      Primitive.attr! :hidden
      width, signed, host, float = Buffer.send(:row, type)
      writable
      fits(offset, width)
      value = float ? [value.to_f].pack(width == 4 ? "g" : "G").unpack1(width == 4 ? "N" : "Q>") : integer_value(value.to_int, width, signed)
      target = writable
      fits(offset, width)
      bytes = Array.new(width) { |i| (value >> ((host ? i : width - 1 - i) * 8)) & 0xff }
      store(target, offset, bytes.pack("C*"))
      offset + width
    end

    def fits(offset, width)
      Primitive.attr! :hidden
      return if offset + width <= size

      raise ArgumentError, "Type extends beyond end of buffer! (offset=#{offset} > size=#{size})"
    end

    # An Integer for a type of `width` bytes, checked as CRuby's NUM2ULL,
    # NUM2LL, NUM2UINT and NUM2INT check it: 8 bytes as a long long, the
    # narrower types as an int (and then their bytes wrap).
    def integer_value(n, width, signed)
      Primitive.attr! :hidden
      # The 128-bit types take any Integer, whose low bytes they keep.
      return n if width > 8

      if width == 8
        if signed
          raise RangeError, +"bignum too big to convert into 'long long'" unless n.between?(-2**63, 2**63 - 1)
        else
          raise RangeError, +"bignum too big to convert into 'unsigned long long'" if n > 2**64 - 1
          raise RangeError, +"bignum out of range of unsigned long long" if n < -2**63
        end
      elsif signed
        raise RangeError, "integer #{n} too #{n.negative? ? "small" : "big"} to convert to 'int'" unless n.between?(-2**31, 2**31 - 1)
      else
        raise RangeError, "integer #{n} too big to convert to 'unsigned int'" if n > 2**32 - 1
        raise RangeError, "integer #{n} too small to convert to 'unsigned int'" if n < -2**31
      end
      n
    end

    # The rows of a hexdump from `offset` up to `offset + length`.
    def rows(memory, start, offset, length, width)
      Primitive.attr! :hidden
      finish = offset + length
      (offset...finish).step(width).map do |at|
        bytes = Array.new([width, finish - at].min) { |i| memory.getbyte(start + at + i) }
        hex = bytes.map { |b| format(" %02x", b) }.join + ("   " * (width - bytes.size))
        "#{format('0x%08x', at)} #{hex} #{bytes.map { |b| b >= 32 && b < 127 ? b.chr : '.' }.join}"
      end
    end

    # A mask repeats over the buffer, so a shorter one is fine and only
    # an empty one is refused.
    def mask_bytes(mask)
      Primitive.attr! :hidden
      raise TypeError, "wrong argument type #{conversion_name(mask)} (expected IO::Buffer)" unless mask.is_a?(Buffer)

      memory, start = mask.send(:readable)
      raise MaskError, +"Zero-length mask given!" if mask.size.zero?

      memory.byteslice(start, mask.size).bytes
    end

    def combined(mask)
      Primitive.attr! :hidden
      raise TypeError, "wrong argument type #{conversion_name(mask)} (expected IO::Buffer)" unless mask.is_a?(Buffer)

      memory, start = readable
      bytes = mask_bytes(mask)
      fresh(Array.new(size) { |i| yield(memory.getbyte(start + i), bytes[i % bytes.size]) }.pack("C*"))
    end

    def in_place(mask)
      Primitive.attr! :hidden
      modifiable
      raise TypeError, "wrong argument type #{conversion_name(mask)} (expected IO::Buffer)" unless mask.is_a?(Buffer)
      raise MaskError, +"Zero-length mask given!" if mask.size.zero?
      raise MaskError, +"Mask overlaps source buffer!" if overlaps?(mask)

      target = writable
      memory, start = target
      bytes = mask_bytes(mask)
      store(target, 0, Array.new(size) { |i| yield(memory.getbyte(start + i), bytes[i % bytes.size]) }.pack("C*"))
      self
    end

    def overlaps?(other)
      Primitive.attr! :hidden
      mine = resolve
      theirs = other.send(:resolve)
      return false if mine.nil? || theirs.nil? || mine[0].nil? || !mine[0].equal?(theirs[0])
      return false if size.zero? || other.size.zero?

      mine[1] <= theirs[1] ? theirs[1] - mine[1] < size : mine[1] - theirs[1] < other.size
    end

    # rb_io_buffer_new: a Storage that owns a copy of `bytes`.
    def fresh(bytes)
      Primitive.attr! :hidden
      out = Primitive.zr_class_build(Storage).send(:allocated, bytes.bytesize, Buffer.send(:flags_for, bytes.bytesize))
      out.send(:store, out.send(:base, 0), 0, bytes) unless bytes.empty?
      out
    end

    # The bytes that C reads or writes in place
    # (rb_io_buffer_get_bytes_for_reading and _for_writing): the String
    # that holds them, or the address of shared memory, then where the
    # buffer starts in it and its size. C may not write a read-only
    # buffer.
    def c_window(writing)
      Primitive.attr! :hidden
      memory, start = writing ? writable : readable
      [memory.is_a?(RawMemory) ? memory.address : memory, start, size]
    end

    # rb_io_buffer_get_bytes: the same window, and the flags, read-only
    # when the view or a source under it is; nil for a view that is not
    # valid.
    def c_bytes
      Primitive.attr! :hidden
      memory, start = resolve
      return if start.nil?

      [memory.is_a?(RawMemory) ? memory.address : memory, start, size, flags | (readonly? ? READONLY : 0)]
    end

    # rb_io_buffer_lock, _unlock and _try_unlock: the lock count of the
    # Storage under all the slices.
    def c_lock
      Primitive.attr! :hidden
      owner.send(:lock!)
      self
    end

    def c_unlock
      Primitive.attr! :hidden
      owner.send(:unlock!)
      self
    end

    def c_try_unlock # rubocop:disable Naming/PredicateMethod -- ruby's name, which unlocks
      Primitive.attr! :hidden
      holder = owner
      return false if holder.send(:locks).zero?

      holder.send(:unlock!)
      true
    end

    # rb_io_buffer_locked_for_reading and _for_writing: the bytes must be
    # there to read, or to write in a buffer that is not frozen, before
    # the lock.
    def c_hold(writing)
      Primitive.attr! :hidden
      writing ? modifiable : readable
      c_lock
    end

    # The C API (kernel/capi/io_buffer.rb) sends `name` to `buffer` as
    # ruby's C checks it: get_io_buffer_view refuses what is no buffer,
    # and get_io_buffer_storage refuses a Slice for the calls that manage
    # memory.
    def self.c_call(buffer, name, *args)
      Primitive.attr! :hidden
      raise TypeError, "wrong argument type #{conversion_name(buffer)} (expected IO::Buffer)" unless buffer.is_a?(Buffer)
      raise AccessError, +"Slice does not manage an allocation!" if C_STORAGE_CALLS.include?(name) && buffer.is_a?(Slice)

      buffer.send(name, *args)
    end
    private_class_method :c_call
    C_STORAGE_CALLS = %i[c_free free_locked transfer].freeze
    private_constant :C_STORAGE_CALLS

    # The Storage manages memory and has a lock count; a String-backed
    # one, a lent one and one without memory own none.
    class Storage < Buffer
      Primitive.zr_define_alloc(self)

      # rb_io_buffer_initialize: the size and the flags are Integers. With
      # no allocation kind in the flags, a buffer of a page or more is
      # mapped and a smaller one is internal.
      def initialize(size = DEFAULT_SIZE, flags = (none = true; 0))
        Buffer.send(:announce)
        unfrozen!
        size = Buffer.send(:size_operand, size)
        flags = none ? 0 : Buffer.send(:flags_operand, flags)
        flags = Buffer.send(:new_flags, flags, size)
        raise LockedError, +"Cannot initialize locked buffer!" if locks.positive?

        allocated(size, flags)
      end

      # A copy owns its bytes, so it is writable even when the original
      # is a read-only window on a String.
      def initialize_copy(source)
        return self if equal?(source)

        # The copy has fields of its own (dup copies the hidden ones).
        Primitive.zr_state_set(self, :__fields__, Fields.new)
        unfrozen!
        raise TypeError, "wrong argument type #{conversion_name(source)} (expected IO::Buffer)" unless source.is_a?(Buffer)

        memory, start = source.send(:readable)
        bytes = memory.nil? ? "".b : memory.byteslice(start, source.size)
        allocated(bytes.bytesize, Buffer.send(:flags_for, bytes.bytesize))
        store(base(0), 0, bytes) unless bytes.empty?
        self
      end

      def external? = flags & EXTERNAL != 0
      def internal? = flags & INTERNAL != 0
      def mapped? = flags & MAPPED != 0
      def shared? = flags & SHARED != 0
      def private? = flags & PRIVATE != 0

      # A freed buffer keeps its object and lets go of its memory, its
      # source and its flags.
      def free
        unfrozen!
        c_free
      end

      # The new buffer takes the memory, with its flags and its source;
      # this one has none of them after.
      def transfer
        unfrozen!
        raise LockedError, +"Cannot transfer ownership of locked buffer!" if locks.positive?

        other = Primitive.zr_class_build(Primitive.zr_real_class(self))
        other.send(:adopted, fields.memory, fields.offset, size, flags, fields.source, fields.mapping)
        released
        other
      end

      # rb_io_buffer_resize: a buffer without memory gets new memory; an
      # internal one grows or shrinks in place, and a size of zero frees
      # it; any other one is copied into new memory. A slice follows the
      # new memory, while its range still fits.
      def resize(size)
        unfrozen!
        size = Buffer.send(:size_operand, size)
        readable
        raise LockedError, +"Cannot resize locked buffer!" if locks.positive?
        raise AccessError, +"Cannot resize external buffer!" if external?
        return allocated(size, Buffer.send(:flags_for, size)) if fields.memory.nil?
        return released if size.zero?

        if internal? && fields.memory.is_a?(String)
          if size < self.size
            fields.memory.replace(fields.memory.byteslice(0, size))
          else
            fields.memory << ("\0".b * (size - self.size))
          end
          fields.size = size
          return self
        end
        kept = fields.memory.byteslice(fields.offset, [size, self.size].min)
        allocated(size, Buffer.send(:flags_for, size) | (flags & READONLY))
        store(base(0), 0, kept)
        self
      end

      private

      def view
        Primitive.attr! :hidden
        [fields.source, fields.offset, size]
      end

      def base(start)
        Primitive.attr! :hidden
        [fields.memory, fields.offset + start, self]
      end

      def flags
        Primitive.attr! :hidden
        fields.flags
      end

      def locks
        Primitive.attr! :hidden
        fields.locks
      end

      def owner
        Primitive.attr! :hidden
        self
      end

      def owning?
        Primitive.attr! :hidden
        flags & ALLOCATION != 0
      end

      def lock!
        Primitive.attr! :hidden
        fields.locks = locks + 1
      end

      def unlock!
        Primitive.attr! :hidden
        raise LockedError, +"Buffer not locked!" if locks.zero?

        fields.locks = locks - 1
      end

      # rb_io_buffer_free, which C may call on a frozen buffer.
      def c_free
        Primitive.attr! :hidden
        raise LockedError, +"Buffer is locked!" if locks.positive?

        released
      end

      # rb_io_buffer_free_locked: the one lock goes, then the memory.
      def free_locked
        Primitive.attr! :hidden
        unlock!
        released
      end

      def moved(amount)
        Primitive.attr! :hidden
        fields.offset = fields.offset + amount unless fields.memory.nil? && fields.source.nil?
        fields.size = size - amount
      end

      def adopted(memory, offset, size, flags, source, mapping)
        Primitive.attr! :hidden
        Primitive.zr_state_set(self, :__fields__, Fields.new(memory:, offset:, size:, flags:, source:, mapping:))
        self
      end

      def released
        Primitive.attr! :hidden
        adopted(nil, 0, 0, 0, nil, nil)
      end

      # rb_io_buffer_new: the `size` bytes of C's memory at `address`, as
      # `flags` describe them; with no address, new memory that the flags
      # choose, or none for a size of zero.
      def self.c_new(address, size, flags)
        Primitive.attr! :hidden
        buffer = Primitive.zr_class_build(self)
        return buffer.send(:adopted, RawMemory.at(address, size, flags), 0, size, flags, nil, nil) unless address.zero?
        return buffer.send(:released) if size.zero?
        raise AllocationError, +"Could not allocate buffer!" if flags.nobits?(INTERNAL | MAPPED)

        buffer.send(:allocated, size, flags)
      end
      private_class_method :c_new

      # io_buffer_storage_initialize: memory of `size` bytes, or none and
      # no flags for a size of zero.
      def allocated(size, flags)
        Primitive.attr! :hidden
        return released if size.zero?

        shared = (flags & (MAPPED | SHARED)) == (MAPPED | SHARED)
        adopted((RawMemory.map(size) if shared) || ("\0".b * size), 0, size, flags, nil, nil)
      end

      # io_buffer_for_make_instance: the whole of a String, whose bytes
      # this buffer shares.
      def over(string, flags)
        Primitive.attr! :hidden
        adopted(nil, 0, string.bytesize, EXTERNAL | flags | (string.frozen? ? READONLY : 0), string, nil)
      end

      # rb_io_buffer_new_locked: memory that the runtime lends, with one
      # lock held.
      def borrowed(bytes, flags)
        Primitive.attr! :hidden
        adopted(bytes, 0, bytes.bytesize, flags, nil, nil)
        lock!
        self
      end

      # io_buffer_storage_map_file: the file's bytes from `offset`, and
      # where they go back to when the mapping is shared and writable.
      def mapped(file, size, offset, flags)
        Primitive.attr! :hidden
        mode = MAPPED | FILE | (flags & READONLY)
        if flags & PRIVATE != 0
          adopted(file.pread(size, offset).b, 0, size, mode | PRIVATE, nil, nil)
        else
          adopted(file.pread(size, offset).b, 0, size, mode | EXTERNAL | SHARED, nil, [file, offset])
        end
      end

      # A change to a shared mapping reaches the file, as it would through
      # the pages that mmap shares with the file.
      def written(at, length)
        Primitive.attr! :hidden
        return if fields.mapping.nil? || length.zero?

        file, file_offset = fields.mapping
        file.pwrite(fields.memory.byteslice(at, length), file_offset + at)
      end
    end

    # A view of another buffer. It manages no memory: resize and advance
    # change only its range in its source.
    class Slice < Buffer
      Primitive.zr_define_alloc(self)

      class << self
        undef_method :for, :string, :map
      end

      def initialize(source, offset = nil, length = nil)
        unfrozen!
        raise RuntimeError, +"Slice is already initialized!" unless fields.source.nil?
        raise TypeError, "wrong argument type #{conversion_name(source)} (expected IO::Buffer)" unless source.is_a?(Buffer)

        offset, length = source.send(:extent, offset, length)
        source.send(:within, offset, length)
        attach(source, offset, length)
      end

      # A copy is a view of the same source, not a copy of the bytes.
      def initialize_copy(other)
        return self if equal?(other)

        unfrozen!
        raise TypeError, "wrong argument type #{conversion_name(other)} (expected IO::Buffer)" unless other.is_a?(Buffer)
        raise TypeError, +"Expected IO::Buffer::Slice!" unless other.is_a?(Slice)

        attach(*other.send(:view))
      end

      # The range may shrink, or grow as far as the source's view goes.
      def resize(size)
        unfrozen!
        size = Buffer.send(:size_operand, size)
        raise InvalidatedError, +"Uninitialized slice!" if fields.source.nil?

        fields.source.send(:resolve) or raise InvalidatedError, +"Buffer is invalid!"
        outer = fields.source.size
        raise InvalidatedError, +"Buffer is invalid!" if fields.offset > outer
        raise ArgumentError, +"Resized slice exceeds its source buffer!" if size > outer - fields.offset

        fields.size = size
        self
      end

      private

      def view
        Primitive.attr! :hidden
        [fields.source, fields.offset, size]
      end

      # A slice with no source has not been initialized, and has no bytes.
      def base(_start)
        Primitive.attr! :hidden
        nil
      end

      def flags
        Primitive.attr! :hidden
        0
      end

      def owner
        Primitive.attr! :hidden
        raise InvalidatedError, +"Uninitialized slice!" if fields.source.nil?

        fields.source.send(:owner)
      end

      def owning?
        Primitive.attr! :hidden
        false
      end

      def moved(amount)
        Primitive.attr! :hidden
        fields.offset += amount
        fields.size -= amount
      end

      def attach(source, offset, length)
        Primitive.attr! :hidden
        Primitive.zr_state_set(self, :__fields__, Fields.new(offset:, size: length, source:))
        self
      end
    end
  end
end
