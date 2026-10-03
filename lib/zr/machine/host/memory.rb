# frozen_string_literal: true

require "fiddle"

module Zr
  module Machine
    class Host
      P = Fiddle::Pointer

      # The real memory of this process. An address is an Integer.
      #
      # Most of the memory that the kernel uses is the host's region
      # (`Region`): the bytes of one String, which an IO::Buffer reads and
      # writes in place. That costs a fifth of a Fiddle read, which makes a
      # new String for each load. An address outside the region (memory
      # that C gave) goes through Fiddle.
      module Memory
        # The host's memory: the bytes of one String of zero bytes. ruby
        # allocates such a String zeroed (calloc), so the system gives a
        # page only when it is first written, and a fork gets its own copy.
        #
        # It answers the kernel's malloc and free: a block has a header
        # with its size class before it, and a freed block waits in the
        # list of its class for the next request of that class. A request
        # that the region cannot hold goes to C.
        class Region
          # @rbs @bytes: String
          # @rbs @holder: Fiber
          # @rbs @top: Integer
          # @rbs @free: Hash[Integer, Array[Integer]]

          # The bytes before each block: its size class, and padding that
          # keeps the block 16-byte aligned, as malloc's are.
          HEADER = 16

          attr_reader :base, :size #: Integer
          attr_reader :buffer #: IO::Buffer

          #: (Integer size) -> void
          def initialize(size)
            @bytes = "\0".b * size
            @base = P[@bytes].to_i
            @size = size
            # IO::Buffer.for writes the String in place only inside its
            # block, so a fiber stays in the block for the life of the
            # process. ruby warns once that IO::Buffer is experimental.
            @holder = Fiber.new { IO::Buffer.for(@bytes) { |buffer| Fiber.yield(buffer) } }
            verbose, $VERBOSE = $VERBOSE, nil
            @buffer = @holder.resume
            $VERBOSE = verbose
            @top = 0
            @free = Hash.new { |lists, size_class| lists[size_class] = [] }
          end

          #: (Integer addr) -> bool
          def include?(addr) = addr >= @base && addr < @base + @size

          # A block of at least `bytes`, or nil when the region is full.
          #: (Integer bytes) -> Integer?
          def malloc(bytes) = @free[rounded(bytes)].pop || fresh(rounded(bytes), 16)

          # A block of at least `bytes` at a multiple of `align`, a power
          # of two, or nil when the region is full.
          #: (Integer align, Integer bytes) -> Integer?
          def memalign(align, bytes)
            size_class = rounded(bytes)
            list = @free[size_class]
            at = list.index { |block| (block & (align - 1)).zero? }
            at ? list.delete_at(at) : fresh(size_class, align)
          end

          #: (Integer addr) -> void
          def free(addr)
            size = usable(addr)
            release(addr, size) if size >= RELEASE
            @free[size] << addr
          end

          # The bytes that the block at `addr` holds.
          #: (Integer addr) -> Integer
          def usable(addr) = @buffer.get_value(:u64, addr - HEADER - @base)

          # `size` bytes never used before, so zero, at a multiple of
          # `align`; or nil when the region is full.
          #: (Integer size, Integer align) -> Integer?
          def fresh(size, align)
            at = @base + @top + HEADER
            at += (-at) % align
            return nil if at + size > @base + @size

            @buffer.set_value(:u64, at - HEADER - @base, size)
            @top = at + size - @base
            at
          end

          private

          # A freed block this large gives its pages back to the system, as
          # malloc unmaps a large block: a program that makes and drops
          # large buffers stays as small as it is in a binary.
          RELEASE = 1 << 20

          # mmap(2) of fresh zero pages over the whole pages of a block, in
          # place: the system takes the old pages back.
          MMAP = Fiddle::Function.new(Fiddle::Handle::DEFAULT["mmap"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_INT,
                                                                       Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_LONG_LONG],
                                      Fiddle::TYPE_VOIDP) #: Fiddle::Function
          READ_WRITE = 3
          MAP_PRIVATE = 0x2
          MAP_FIXED = 0x10
          MAP_ANON = RUBY_PLATFORM.include?("linux") ? 0x20 : 0x1000 #: Integer
          PAGE = IO::Buffer::PAGE_SIZE #: Integer

          #: (Integer addr, Integer size) -> void
          def release(addr, size)
            from = (addr + PAGE - 1) & -PAGE
            to = (addr + size) & -PAGE
            MMAP.call(from, to - from, READ_WRITE, MAP_PRIVATE | MAP_FIXED | MAP_ANON, -1, 0) if to > from
          end

          # The size class of a request: a multiple of 16 up to 1 KiB,
          # then four classes in each doubling, so a block wastes at most a
          # quarter of itself.
          #: (Integer bytes) -> Integer
          def rounded(bytes)
            return (bytes + 15) & -16 if bytes <= 1024

            shift = bytes.bit_length - 3
            ((bytes + (1 << shift) - 1) >> shift) << shift
          end
        end

        # The region takes this much address space. A system that refuses
        # so much (Linux counts a calloc against its memory) gets one half
        # as large, and so on.
        REGION_BYTES = 16 << 30

        #: (?Integer bytes) -> Region
        def self.reserve(bytes = REGION_BYTES)
          Region.new(bytes)
        rescue NoMemoryError
          raise if bytes <= (256 << 20)

          reserve(bytes / 2)
        end

        REGION = reserve #: Region
        BUFFER = REGION.buffer #: IO::Buffer
        BASE = REGION.base #: Integer
        LIMIT = REGION.size #: Integer

        module_function

        #: (Integer addr, Integer len) -> String
        def read(addr, len)
          off = addr - BASE
          off >= 0 && off < LIMIT ? BUFFER.get_string(off, len) : P.read(addr, len)
        end

        #: (Integer addr, String bytes) -> void
        def write(addr, bytes)
          off = addr - BASE
          off >= 0 && off < LIMIT ? BUFFER.set_string(bytes, off) : P.write(addr, bytes)
        end

        #: (Integer addr) -> Integer
        def word(addr)
          off = addr - BASE
          off >= 0 && off < LIMIT ? BUFFER.get_value(:s64, off) : P.read(addr, 8).unpack1("q<") #: Integer
        end

        #: (Integer addr, Integer value) -> void
        def set_word(addr, value)
          off = addr - BASE
          off >= 0 && off < LIMIT ? BUFFER.set_value(:u64, off, value) : P.write(addr, [value].pack("q<"))
        end

        # The IO::Buffer types of `n` words, for each `n` up to WORDS: one
        # call reads or writes them all.
        WORDS = 64
        LOAD_WORDS = Array.new(WORDS + 1) { |n| Array.new(n, :s64).freeze }.freeze #: Array[Array[Symbol]]
        STORE_WORDS = Array.new(WORDS + 1) { |n| Array.new(n, :u64).freeze }.freeze #: Array[Array[Symbol]]

        # `n` words from `addr`, as an Array.
        #: (Integer addr, Integer n) -> Array[Integer]
        def words(addr, n)
          return [] if n.zero?

          off = addr - BASE
          off >= 0 && off < LIMIT && n <= WORDS ? BUFFER.get_values(LOAD_WORDS[n], off) : read(addr, n * 8).unpack("q<*") #: Array[Integer]
        end

        # `values` as words at `addr`.
        #: (Integer addr, Array[Integer] values) -> void
        def set_words(addr, values)
          n = values.size
          off = addr - BASE
          off >= 0 && off < LIMIT && n <= WORDS ? BUFFER.set_values(STORE_WORDS[n], off, values) : write(addr, values.pack("q<*"))
        end

        # The load of a `type` (`Host::Type`) at `offset` from a pointer,
        # as a lambda that reads the memory itself, so a field's reader is
        # one call.
        #: (Type type, Integer offset) -> ^(Integer) -> untyped
        def reader(type, offset)
          raise ArgumentError, "no load of a Void" if type.size.zero?

          buffer = BUFFER
          limit = LIMIT
          delta = offset - BASE
          # A type that is not Void has a load and a packing. The load of
          # an F64 is a float type; the integer type here only picks the
          # overload of `get_value`.
          kind = type.loads #: IO::Buffer::int_get_type
          size = type.size
          format = type.packing #: String
          if type.name == "Bool"
            ->(p) { (off = p + delta) >= 0 && off < limit ? buffer.get_value(:U8, off) != 0 : P.read(p + offset, 1).getbyte(0) != 0 }
          else
            ->(p) { (off = p + delta) >= 0 && off < limit ? buffer.get_value(kind, off) : P.read(p + offset, size).unpack1(format) }
          end
        end

        # The store of a `type` at `offset` from a pointer, as a lambda. An
        # unsigned store takes a value of the signed range too.
        #: (Type type, Integer offset) -> ^(Integer, untyped) -> untyped
        def writer(type, offset)
          raise ArgumentError, "no store of a Void" if type.size.zero?

          buffer = BUFFER
          limit = LIMIT
          delta = offset - BASE
          # A type that is not Void has a store and a packing.
          kind = type.stores #: IO::Buffer::int_get_type | IO::Buffer::float_get_type
          format = type.packing #: String
          case type.name
          when "Bool", "I8"
            lambda do |p, value|
              bits = Host.bits(value)
              (off = p + delta) >= 0 && off < limit ? buffer.set_value(kind, off, bits) : P.write(p + offset, [bits].pack(format))
            end
          when "I32"
            lambda do |p, value|
              bits = value & 0xFFFF_FFFF
              (off = p + delta) >= 0 && off < limit ? buffer.set_value(kind, off, bits) : P.write(p + offset, [bits].pack(format))
            end
          else
            ->(p, value) { (off = p + delta) >= 0 && off < limit ? buffer.set_value(kind, off, value) : P.write(p + offset, [value].pack(format)) }
          end
        end

        # rubocop:disable ThreadSafety/ClassInstanceVariable -- `@at` in
        # these procs is the view's: each is a method body of a View.

        # `reader` for a field of a view (`Host::View`): the body of the
        # field's method, which reads the view's `@at` itself. Thus a field
        # read is one call, the host's most frequent. `pin` pins a Value
        # (`Host#pin`).
        #: (Type type, Integer offset, ?pin: Host?) -> Proc
        def field_reader(type, offset, pin: nil)
          raise ArgumentError, "no load of a Void" if type.size.zero?

          buffer = BUFFER
          limit = LIMIT
          delta = offset - BASE
          kind = type.loads #: IO::Buffer::int_get_type
          size = type.size
          format = type.packing #: String
          if type.name == "Bool"
            proc do
              # @type self: View
              (off = @at + delta) >= 0 && off < limit ? buffer.get_value(:U8, off) != 0 : P.read(@at + offset, 1).getbyte(0) != 0
            end
          elsif pin
            proc do
              # @type self: View
              pin.pin((off = @at + delta) >= 0 && off < limit ? buffer.get_value(kind, off) : P.read(@at + offset, size).unpack1(format))
            end
          else
            proc do
              # @type self: View
              (off = @at + delta) >= 0 && off < limit ? buffer.get_value(kind, off) : P.read(@at + offset, size).unpack1(format)
            end
          end
        end

        # `writer` for a field of a view, as `field_reader` is `reader`.
        # `barrier` runs the write barrier of the cell (`Host#barrier`).
        #: (Type type, Integer offset, ?barrier: Host?) -> Proc
        def field_writer(type, offset, barrier: nil)
          if %w[Bool I8 I32].include?(type.name)
            store = writer(type, offset)
            return proc do |value|
              # @type self: View
              store.call(@at, value)
            end
          end

          buffer = BUFFER
          limit = LIMIT
          delta = offset - BASE
          kind = type.stores #: IO::Buffer::int_get_type | IO::Buffer::float_get_type
          format = type.packing #: String
          if barrier
            proc do |value|
              # @type self: View
              at = @at
              (off = at + delta) >= 0 && off < limit ? buffer.set_value(kind, off, value) : P.write(at + offset, [value].pack(format))
              barrier.barrier(at, value)
            end
          else
            proc do |value|
              # @type self: View
              (off = @at + delta) >= 0 && off < limit ? buffer.set_value(kind, off, value) : P.write(@at + offset, [value].pack(format))
            end
          end
        end

        # rubocop:enable ThreadSafety/ClassInstanceVariable

        # `size` zeroed bytes that stay until the process ends.
        #: (Integer size, ?Integer align) -> Integer
        def zeroed(size, align = 16)
          REGION.fresh(size, align) || begin
            addr = Fiddle.malloc(size + align)
            addr += (-addr) % align
            P.write(addr, "\0".b * size) if size.positive?
            addr
          end
        end

        # The C functions that only read and write memory, or allocate it,
        # in Ruby (`Host#answer`): through Fiddle each costs more than the
        # work it does, and none of them sets errno. `c` calls the C
        # function, for memory that the region does not hold.
        #
        # Each lambda becomes a method of `Libc`, so it names `Memory`.
        #: (String name, Proc c) -> Proc?
        def function(name, c)
          region = REGION
          case name
          when "memmove" then ->(to, from, n) { Memory.copy(to, from, n) }
          when "memset" then ->(p, byte, n) { Memory.fill(p, byte, n) }
          when "memchr" then ->(p, byte, n) { Memory.find(p, byte, n) }
          when "malloc" then ->(n) { region.malloc(n) || c.call(n) }
          when "free"
            lambda do |p|
              region.include?(p) ? region.free(p) : c.call(p)
              nil
            end
          when "posix_memalign"
            lambda do |out, align, n|
              at = region.memalign(align, n) or next c.call(out, align, n)
              Memory.set_word(out, at)
              0
            end
          when "malloc_size", "malloc_usable_size" then ->(p) { region.include?(p) ? region.usable(p) : c.call(p) }
          when "munmap"
            lambda do |p, n|
              next c.call(p, n) unless region.include?(p)

              region.free(p)
              0
            end
          end
        end

        # memmove(3): returns `to`.
        #: (Integer to, Integer from, Integer n) -> Integer
        def copy(to, from, n)
          return to unless n.positive?

          if REGION.include?(to) && REGION.include?(from)
            BUFFER.copy(BUFFER, to - BASE, n, from - BASE)
          else
            write(to, read(from, n))
          end
          to
        end

        # memchr(3): the address of the first `byte` in the `n` bytes at
        # `p`, or 0. A caller may give an `n` past the end of the memory
        # (a search for a string's NUL), so the search reads a page at a
        # time and stops at the byte, as C's does.
        #: (Integer p, Integer byte, Integer n) -> Integer
        def find(p, byte, n)
          target = (byte & 0xFF).chr
          at = 0
          while at < n
            len = [n - at, PAGE - ((p + at) % PAGE)].min
            found = read(p + at, len).index(target)
            return p + at + found if found

            at += len
          end
          0
        end

        # The smallest page of the systems the host runs on: no read that
        # stays inside one can fault after a byte that is mapped.
        PAGE = 4096

        # memset(3): returns `p`.
        #: (Integer p, Integer byte, Integer n) -> Integer
        def fill(p, byte, n)
          return p unless n.positive?

          if REGION.include?(p)
            BUFFER.clear(byte & 0xFF, p - BASE, n)
          else
            P.write(p, (byte & 0xFF).chr * n)
          end
          p
        end
      end
    end
  end
end
