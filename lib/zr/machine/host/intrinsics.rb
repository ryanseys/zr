# frozen_string_literal: true

# `Host`'s intrinsics: `Machine.*` on CRuby.

module Zr
  module Machine
    class Host
      # The intrinsics, `Machine.*`, as the lowering defines them
      # (`Function#intrinsic`). A name's id, static and address do not
      # change, so each is found once.
      class Intrinsics
        # @rbs @host: Host
        # @rbs @ids: Hash[Symbol, Integer]
        # @rbs @statics: Hash[Symbol, Integer]
        # @rbs @addrs: Hash[Symbol, Integer]
        # @rbs @bytes: Hash[String, Integer]

        #: (Host host) -> void
        def initialize(host)
          @host = host
          @ids = {}
          @statics = {}
          @addrs = {}
          bytes = {} #: Hash[String, Integer]
          @bytes = bytes.compare_by_identity
        end

        #: (Symbol name) -> Integer
        def id(name) = @ids[name] ||= @host.symbols.id(name.to_s)

        # The bodies of the declarations `def self.name(...) =
        # Machine.import`, `def self.call(fn, ...) = Machine.indirect` and
        # `def name(...) = Machine.raw`. The host binds each declaration
        # when it loads the kernel, so a body that runs is a host bug.
        #: (?from: String?) -> bot
        def import(from: nil) = raise(NotImplementedError, "an import that the host did not bind#{" (#{from})" if from}")
        #: () -> bot
        def indirect = raise(NotImplementedError, "a signature that the host did not bind")
        #: () -> bot
        def raw = raise(NotImplementedError, "a raw function that the host does not have")
        #: (String string) -> Integer
        def bytesize(string) = string.bytesize
        #: (String string) -> Integer
        def bytes(string) = @bytes[string] ||= @host.bytes(string)
        #: (Symbol name) -> Integer
        def extern(name) = @host.extern(name.to_s)
        #: (Symbol name, Integer size) -> Integer
        def static(name, size) = @statics[name] ||= @host.static(name.to_s, size)
        # An exported area of a C name (`Machine.global`): a static here,
        # in a namespace of its own.
        #: (Symbol name, ?Integer size) -> Integer
        def global(name, size = 8) = static(:"global #{name}", size)
        #: (Integer size) -> Integer
        def slot(size) = @host.slot(size)
        #: (Symbol name) -> Integer
        def addr(name) = @addrs[name] ||= @host.addr(name.to_s)

        LOAD64 = Memory.reader(TYPES["Word"], 0) #: ^(Integer) -> untyped
        LOAD32 = Memory.reader(TYPES["I32"], 0) #: ^(Integer) -> untyped
        LOAD8 = Memory.reader(TYPES["I8"], 0) #: ^(Integer) -> untyped
        STORE64 = Memory.writer(TYPES["Word"], 0) #: ^(Integer, untyped) -> untyped
        STORE32 = Memory.writer(TYPES["I32"], 0) #: ^(Integer, untyped) -> untyped
        STORE8 = Memory.writer(TYPES["I8"], 0) #: ^(Integer, untyped) -> untyped

        #: (Integer p, Integer off) -> Integer
        def load64(p, off) = LOAD64.call(p + off)
        #: (Integer p, Integer off) -> Integer
        def load32(p, off) = LOAD32.call(p + off)
        #: (Integer p, Integer off) -> Integer
        def load8(p, off) = LOAD8.call(p + off)
        #: (Integer p, Integer off, Integer value) -> untyped
        def store64(p, off, value) = STORE64.call(p + off, value)
        #: (Integer p, Integer off, Integer value) -> untyped
        def store32(p, off, value) = STORE32.call(p + off, value)
        #: (Integer p, Integer off, Integer value) -> untyped
        def store8(p, off, value) = STORE8.call(p + off, value)

        # The gate word is in a register, and in the static `gates`, which
        # `gates_enter` reads (`Function#gates_addr`). Here the host keeps
        # the register's copy (`Host#gates`), which the walker reads.
        #: () -> Integer
        def gates = @host.gates

        #: (Integer word) -> void
        def gates_set(word)
          @host.gates = word
          STORE64.call(static(:gates, 8), word)
        end

        # The walker has no machine stack for a C caller's arguments: a
        # variadic C-API function runs only in a binary.
        #: (Integer _kind) -> Integer
        def va_list(_kind) = raise(NotImplementedError, "a variadic C-API function runs only in a binary")

        #: () -> void
        def gates_enter
          @host.gates = LOAD64.call(static(:gates, 8))
        end

        # A Word of `x`: an Integer in the signed range is one already.
        #: (Integer | bool | View | nil x) -> Integer
        def word(x) = x.is_a?(Integer) && x.bit_length < 64 ? x : Host.signed(Host.bits(x))
        #: (Integer | bool | View | nil x) -> Integer
        def sword(x) = word(x)
        #: (Integer | bool | View | nil x) -> Integer
        def value(x) = @host.pin(word(x))
        #: (Integer | bool | View | nil x) -> Integer
        def ptr(x) = Host.unsigned(Host.bits(x))
        #: (Integer x) -> Integer
        def u8(x) = x & 0xFF
        #: (Integer x) -> Integer
        def u32(x) = x & 0xFFFF_FFFF
        #: (Integer | bool | nil x) -> Integer
        def i8(x) = narrow(Host.bits(x), 8)
        #: (Integer | bool | nil x) -> Integer
        def i32(x) = narrow(Host.bits(x), 32)

        #: (Integer a, Integer b) -> Integer
        def add_wrap(a, b) = Host.signed(a + b)
        #: (Integer a, Integer b) -> Integer
        def sub_wrap(a, b) = Host.signed(a - b)
        #: (Integer a, Integer b) -> Integer
        def mul_wrap(a, b) = Host.signed(a * b)
        #: (Integer a, Integer b) -> Integer
        def shl_wrap(a, b) = Host.signed(a << (b & 63))
        #: (Integer a, Integer b) -> Integer
        def uadd_wrap(a, b) = Host.unsigned(a + b)
        #: (Integer a, Integer b) -> Integer
        def usub_wrap(a, b) = Host.unsigned(a - b)
        #: (Integer a, Integer b) -> Integer
        def umul_wrap(a, b) = Host.unsigned(a * b)
        #: (Integer a, Integer b) -> Integer
        def ushl_wrap(a, b) = Host.unsigned(a << (b & 63))

        # Division that truncates toward zero, as C's.
        #: (Integer a, Integer b) -> Integer
        def sdiv(a, b)
          q = a.abs / b.abs
          (a.negative? ^ b.negative?) ? -q : q
        end

        #: (Integer a, Integer b) -> Integer
        def srem(a, b) = a - (b * sdiv(a, b))

        # `unpack1` has no one type.
        #: (Integer w) -> untyped
        def f64(w) = [w & MASK].pack("Q<").unpack1("E")
        #: (Float f) -> untyped
        def bits(f) = [f].pack("E").unpack1("q<")
        #: (Integer w) -> Float
        def to_f64(w) = w.to_f

        # A double as a Word, saturated at the ends of the range; NaN is 0.
        #: (Float f) -> Integer
        def to_int(f)
          return 0 if f.nan?
          return SIGN - 1 if f >= SIGN
          return -SIGN if f < -SIGN

          f.to_i
        end

        #: (Integer x) -> Integer
        def ctz(x)
          u = x & MASK
          u.zero? ? 64 : (u & -u).bit_length - 1
        end

        #: (Integer x) -> Integer
        def clz(x) = 64 - (x & MASK).bit_length
        #: (Integer x) -> Integer
        def popcnt(x) = (x & MASK).digits(2).count(1)
        #: (Integer x) -> Integer
        def bswap(x)
          swapped = [x & MASK].pack("Q<").unpack1("Q>") #: Integer
          Host.signed(swapped)
        end

        #: (Float f) -> Float
        def sqrt(f) = f.negative? ? Float::NAN : Math.sqrt(f)
        #: (Float f) -> Float
        def floor(f) = integral(f) { f.floor }
        #: (Float f) -> Float
        def ceil(f) = integral(f) { f.ceil }
        #: (Float f) -> Float
        def trunc(f) = integral(f) { f.truncate }
        #: (Float f) -> Float
        def nearest(f) = integral(f) { f.round(half: :even) }
        #: (Float f) -> Float
        def fabs(f) = f.abs

        private

        #: (Integer n, Integer width) -> Integer
        def narrow(n, width)
          n &= (1 << width) - 1
          n >= (1 << (width - 1)) ? n - (1 << width) : n
        end

        # An IEEE rounding: NaN and infinities stay, and a zero keeps the
        # sign of `f`.
        #: (Float f) { () -> Integer } -> Float
        def integral(f)
          return f if f.nan? || f.infinite?

          r = yield.to_f
          r.zero? && (f.negative? || (f.zero? && 1.0 / f < 0)) ? -0.0 : r
        end
      end

      # The slots of the defs that run: an area that grows down, like a
      # stack. A def that takes a slot gets back the slots it took when it
      # returns. Each fiber has its own area (`fiber_slots`).
      SLOT_BYTES = 64 << 20
    end
  end
end
