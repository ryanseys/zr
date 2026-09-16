# The zlib port against ruby's zlib, in one process. The port is the
# kernel unit rt/kernel/zlib_*.rb (never zlib.rb, the seam, which needs
# the whole kernel), compiled by the Ruby backend and loaded into this
# ruby through Obj::JIT; the oracle is the zlib ruby 4.0.6 links, 1.3.1,
# reached through Zlib itself where the API reaches it and through
# Fiddle, inside ruby's own zlib.bundle, where the harness must control
# every call. One loop drives both sides call by call and compares the
# answer, the bytes and the stream's fields after each.
#
#   ruby -Ilib tools/zlib_diff.rb --check [--cases N] [--seed S]
#   ruby -Ilib tools/zlib_diff.rb --inflate [--cases N] [--seed S]
#   ruby -Ilib tools/zlib_diff.rb --inflate-corrupt [--cases N] [--seed S]
#
# --check: adler32, crc32, their combines and the crc table.
# --inflate: streams ruby deflated under every wrapper, level and
#   strategy, inflated under chunkings of the input and the output.
# --inflate-corrupt: the same streams truncated, flipped, and given
#   wrong windows and dictionaries.
require "zlib"
require "fiddle"
require "ze0/machine/lower"
require "ze0/native/build"
require "ze0/obj/jit/fiddle"

module ZlibDiff
  ROOT = File.expand_path("..", __dir__)
  Z_OK = 0
  Z_STREAM_END = 1
  Z_NEED_DICT = 2
  Z_STREAM_ERROR = -2
  Z_DATA_ERROR = -3
  Z_BUF_ERROR = -5
  Z_NO_FLUSH = 0
  Z_SYNC_FLUSH = 2
  Z_FINISH = 4

  # The port's functions, called through Fiddle.
  class Port
    TYPES = { "Word" => Fiddle::TYPE_LONG, "Ptr" => Fiddle::TYPE_VOIDP, "I32" => Fiddle::TYPE_INT, "I8" => Fiddle::TYPE_CHAR, "Bool" => Fiddle::TYPE_CHAR, "Void" => Fiddle::TYPE_VOID }.freeze

    attr_reader :layouts

    def initialize
      paths = Dir[File.join(ROOT, "rt/kernel/zlib_*.rb")].sort
      lower = Ze0::Machine.unit(paths)
      unit = Ze0::Native::Build.unit(lower.functions, lower.data, raw: lower.raw)
      @symbols = Ze0::Obj::JIT.load(unit, host: Ze0::Obj::JIT::Fiddle.new)
      @defs = lower.instance_variable_get(:@defs)
      @layouts = Ze0::Machine::Description.of(lower)
      @fns = {}
    end

    def call(name, *args)
      fn = @fns[name] ||= begin
        d = @defs.fetch(name) { raise "no def #{name} in the port" }
        Fiddle::Function.new(@symbols.fetch(name), d.params.map { |_, t| TYPES.fetch(t) }, TYPES.fetch(d.ret))
      end
      fn.call(*args)
    end

    # `n` bytes at the address def `name` answers.
    def bytes(name, n)
      Fiddle::Pointer.new(call(name))[0, n]
    end
  end

  # ruby's zlib, through Fiddle, inside ruby's own zlib.bundle.
  class Libz
    FIELDS = { next_in: 0, avail_in: 8, total_in: 16, next_out: 24, avail_out: 32, total_out: 40, msg: 48, data_type: 88, adler: 96 }.freeze
    SIZE = 112
    WIDTHS = { avail_in: 4, avail_out: 4, data_type: 4 }.freeze

    def initialize
      path = $LOADED_FEATURES.grep(/zlib\.bundle\z/).first or abort "ruby's zlib.bundle is not loaded"
      @lib = Fiddle.dlopen(path)
      @version = Fiddle::Function.new(@lib["zlibVersion"], [], Fiddle::TYPE_VOIDP).call.to_s
      abort "ruby's zlib is #{@version}, not 1.3.1" unless @version == "1.3.1"
      @fns = {}
      @version_ptr = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
      @version_ptr[0, 6] = "1.3.1\0"
    end

    attr_reader :version_ptr

    def fn(name, params, ret)
      @fns[name] ||= Fiddle::Function.new(@lib[name], params, ret)
    end
  end

  # One side of the comparison: a stream and the calls on it. `fields`
  # answers what rt/ext/zlib.rb reads after every call.
  class Side
    attr_reader :strm

    def initialize
      @keep = []
    end

    def input(bytes)
      buf = Fiddle::Pointer.malloc(bytes.bytesize + 1, Fiddle::RUBY_FREE)
      buf[0, bytes.bytesize] = bytes
      @keep = [buf]
      set(:next_in, buf.to_i)
      set(:avail_in, bytes.bytesize)
    end

    # One call with `room` bytes of output: [rc, the bytes written].
    def call(op, flush, room)
      out = Fiddle::Pointer.malloc(room + 1, Fiddle::RUBY_FREE)
      set(:next_out, out.to_i)
      set(:avail_out, room)
      rc = run(op, flush)
      [rc, out[0, room - get(:avail_out)]]
    end

    def fields
      msg = get(:msg)
      [get(:avail_in), get(:total_in), get(:avail_out), get(:total_out), get(:data_type), get(:adler), msg.zero? ? nil : Fiddle::Pointer.new(msg).to_s]
    end
  end

  class PortSide < Side
    def initialize(port)
      super()
      @port = port
      layout = port.layouts.struct_for("ZStream")
      @fields = layout.fields
      @strm = Fiddle::Pointer.malloc(layout.size, Fiddle::RUBY_FREE)
      @strm[0, layout.size] = "\0" * layout.size
    end

    def get(name) = @strm[@fields.fetch(name.to_s)[0], 8].unpack1("q")
    def set(name, value) = @strm[@fields.fetch(name.to_s)[0], 8] = [value].pack("q")

    def init_inflate(wbits) = @port.call("zr_inflate_init2", @strm, wbits)
    def end_stream = @port.call("zr_inflate_end", @strm)
    def reset = @port.call("zr_inflate_reset", @strm)
    def sync = @port.call("zr_inflate_sync", @strm)
    def sync_point = @port.call("zr_inflate_sync_point", @strm)
    def dictionary(bytes) = @port.call("zr_inflate_set_dictionary", @strm, bytes, bytes.bytesize)

    def run(op, flush)
      case op
      when :inflate then @port.call("zr_inflate", @strm, flush)
      else raise "no op #{op}"
      end
    end
  end

  class LibzSide < Side
    def initialize(libz)
      super()
      @libz = libz
      @strm = Fiddle::Pointer.malloc(Libz::SIZE, Fiddle::RUBY_FREE)
      @strm[0, Libz::SIZE] = "\0" * Libz::SIZE
    end

    def get(name)
      at = Libz::FIELDS.fetch(name)
      Libz::WIDTHS.key?(name) ? @strm[at, 4].unpack1("l") : @strm[at, 8].unpack1("q")
    end

    def set(name, value)
      at = Libz::FIELDS.fetch(name)
      Libz::WIDTHS.key?(name) ? @strm[at, 4] = [value].pack("l") : @strm[at, 8] = [value].pack("q")
    end

    P = Fiddle::TYPE_VOIDP
    I = Fiddle::TYPE_INT

    def init_inflate(wbits) = @libz.fn("inflateInit2_", [P, I, P, I], I).call(@strm, wbits, @libz.version_ptr, Libz::SIZE)
    def end_stream = @libz.fn("inflateEnd", [P], I).call(@strm)
    def reset = @libz.fn("inflateReset", [P], I).call(@strm)
    def sync = @libz.fn("inflateSync", [P], I).call(@strm)
    def sync_point = @libz.fn("inflateSyncPoint", [P], I).call(@strm)
    def dictionary(bytes) = @libz.fn("inflateSetDictionary", [P, P, I], I).call(@strm, bytes, bytes.bytesize)

    def run(op, flush)
      case op
      when :inflate then @libz.fn("inflate", [P, I], I).call(@strm, flush)
      else raise "no op #{op}"
      end
    end
  end

  # The two sides driven together; the first disagreement stops the run
  # and names the step.
  class Pair
    def initialize(port, libz, name)
      @port = PortSide.new(port)
      @libz = LibzSide.new(libz)
      @name = name
      @step = 0
      @log = []
    end

    def each_side = [@libz, @port]

    def same(what, expected, got)
      return if expected == got

      abort "#{@name}, step #{@step} (#{what}): ruby's zlib #{expected.inspect}, port #{got.inspect}\n  steps: #{@log.last(8).join(" | ")}"
    end

    def check(what, &block)
      @step += 1
      expected = block.call(@libz)
      got = block.call(@port)
      @log << "#{what} -> #{expected.inspect[0, 60]}"
      same(what, expected, got)
      same("fields after #{what}", @libz.fields, @port.fields)
      expected
    end

    def init_inflate(wbits) = check("inflateInit2(#{wbits})") { |s| s.init_inflate(wbits) }
    def input(bytes) = each_side.each { |s| s.input(bytes) }
    def call(op, flush, room) = check("#{op}(flush #{flush}, room #{room})") { |s| s.call(op, flush, room) }
    def end_stream = check("end") { |s| s.end_stream }
    def reset = check("reset") { |s| s.reset }
    def sync = check("inflateSync") { |s| s.sync }
    def sync_point = check("inflateSyncPoint") { |s| s.sync_point }
    def dictionary(bytes) = check("inflateSetDictionary(#{bytes.bytesize})") { |s| s.dictionary(bytes) }
    def avail_in = @libz.get(:avail_in)
  end

  # Sample inputs, seeded.
  class Samples
    def initialize(random)
      @random = random
      @words = File.read(__FILE__).split(/\W+/).uniq
    end

    def any
      case @random.rand(8)
      when 0 then ""
      when 1 then @random.bytes(1)
      when 2 then @random.bytes(@random.rand(2..300))
      when 3 then @random.bytes(@random.rand(300..300_000))
      when 4 then [@random.rand(256)].pack("C") * @random.rand(1..200_000)
      when 5 then text(@random.rand(1..200_000))
      when 6 then periodic(@random.rand(1..40_000), @random.rand(1..200_000))
      else mixed
      end
    end

    def text(n)
      s = +""
      s << @words.sample(random: @random) << [" ", " ", " ", "\n"].sample(random: @random) while s.bytesize < n
      s.byteslice(0, n)
    end

    def periodic(period, n) = (@random.bytes(period) * (n / period + 1)).byteslice(0, n)

    def mixed
      parts = @random.rand(2..6).times.map { [any, text(@random.rand(1000)), periodic(@random.rand(1..100), @random.rand(5000))].sample(random: @random) }
      parts.join.byteslice(0, 400_000)
    end

    def chunk_size = [1, 2, 3, 7, 64, 1000, 4096, 16_384, 32_768, 65_535, 65_536, 100_000].sample(random: @random)
    def room = [1, 5, 6, 7, 32, 100, 257, 258, 1024, 4096, 16_384, 65_535, 65_541, 1_000_000].sample(random: @random)
    def level = @random.rand(-1..9)
    def strategy = @random.rand(5)
    def memlevel = @random.rand(1..9)

    # wbits for a deflate, and the wbits an inflate of it can take.
    def wbits
      case @random.rand(3)
      when 0 then n = @random.rand(9..15); [n, [n, 0, n + 32, 47, 15].sample(random: @random)]
      when 1 then n = @random.rand(9..15); [-n, [-n, -15].sample(random: @random)]
      else n = @random.rand(9..15); [n + 16, [n + 16, 31, n + 32, 47].sample(random: @random)]
      end
    end
  end

  class Check
    def initialize(port, seed, cases)
      @port = port
      @random = Random.new(seed)
      @cases = cases
      @seen = 0
    end

    def sample
      case @random.rand(6)
      when 0 then ""
      when 1 then @random.bytes(1)
      when 2 then @random.bytes(@random.rand(2..15))
      when 3 then @random.bytes(@random.rand(16..5551))
      when 4 then @random.bytes(@random.rand(5552..70_000))
      else [@random.rand(256)].pack("C") * @random.rand(1..20_000)
      end
    end

    def same(what, expected, got)
      @seen += 1
      return if expected == got

      abort "#{what}: expected #{expected.inspect}, port answered #{got.inspect}"
    end

    def run
      table = @port.bytes("zr_crc_table", 1024)
      same("crc table", Zlib.crc_table, table.unpack("V256"))
      same("crc32 of nothing", Zlib.crc32, @port.call("zr_crc32", 0, nil, 0))
      same("adler32 of nothing", Zlib.adler32, @port.call("zr_adler32", 1, nil, 0))
      @cases.times do
        a = sample
        b = sample
        start = @random.rand(4).zero? ? @random.rand(1 << 32) : nil
        crc = start || 0
        adler = start || 1
        same("crc32 #{a.bytesize} bytes from #{crc}", Zlib.crc32(a, crc), @port.call("zr_crc32", crc, a, a.bytesize))
        same("adler32 #{a.bytesize} bytes from #{adler}", Zlib.adler32(a, adler), @port.call("zr_adler32", adler, a, a.bytesize))
        ca = Zlib.crc32(a)
        cb = Zlib.crc32(b)
        same("crc32_combine #{a.bytesize} + #{b.bytesize}", Zlib.crc32_combine(ca, cb, b.bytesize), @port.call("zr_crc32_combine", ca, cb, b.bytesize))
        aa = Zlib.adler32(a)
        ab = Zlib.adler32(b)
        same("adler32_combine #{a.bytesize} + #{b.bytesize}", Zlib.adler32_combine(aa, ab, b.bytesize), @port.call("zr_adler32_combine", aa, ab, b.bytesize))
        len = @random.rand(1 << 40)
        same("crc32_combine over #{len}", Zlib.crc32_combine(ca, cb, len), @port.call("zr_crc32_combine", ca, cb, len))
        same("adler32_combine over #{len}", Zlib.adler32_combine(aa, ab, len), @port.call("zr_adler32_combine", aa, ab, len))
      end
      same("adler32_combine of a negative length", Zlib.adler32_combine(1, 1, -1), @port.call("zr_adler32_combine", 1, 1, -1))
      puts "check: #{@seen} answers agree"
    end
  end

  # Inflate: a stream ruby deflated, given to both sides in chunks.
  class Inflate
    def initialize(port, libz, seed, cases, corrupt: false)
      @port = port
      @libz = libz
      @random = Random.new(seed)
      @samples = Samples.new(@random)
      @cases = cases
      @corrupt = corrupt
      @bytes = 0
    end

    # A deflate of `data` under random parameters: [bytes, inflate wbits, dictionary or nil].
    def deflated(data)
      dwbits, iwbits = @samples.wbits
      z = Zlib::Deflate.new(@samples.level, dwbits, @samples.memlevel, @samples.strategy)
      dict = nil
      if dwbits < 16 && @random.rand(5).zero?
        dict = @samples.text(@random.rand(1..40_000))
        z.set_dictionary(dict)
      end
      out = z.deflate(data, Zlib::FINISH)
      z.close
      [out, iwbits, dict]
    end

    # Drive one inflate of `stream` on both sides to its end, or to an
    # error both agree on. Answers the last rc.
    def drive(pair, stream, wbits, dict, name)
      pair.init_inflate(wbits)
      pair.dictionary(dict) if dict && wbits.negative?
      chunks = []
      rest = stream
      until rest.empty?
        n = [@samples.chunk_size, rest.bytesize].min
        chunks << rest.byteslice(0, n)
        rest = rest.byteslice(n..)
      end
      chunks << "" if chunks.empty?
      rc = Z_OK
      steps = 0
      @out = +""
      loop do
        pair.input(chunks.shift) if pair.avail_in.zero? && !chunks.empty?
        flush = [Z_NO_FLUSH, Z_NO_FLUSH, Z_SYNC_FLUSH, Z_FINISH, 5, 6].sample(random: @random)
        rc, bytes = pair.call(:inflate, flush, @samples.room)
        @out << bytes
        steps += 1
        if rc == Z_NEED_DICT
          if dict && (!@corrupt || @random.rand(4) != 0)
            pair.dictionary(dict)
          else
            pair.dictionary(@samples.text(100))
            break
          end
        elsif rc == Z_STREAM_END || rc == Z_DATA_ERROR || rc == Z_STREAM_ERROR
          break
        elsif rc == Z_BUF_ERROR && chunks.empty? && pair.avail_in.zero?
          break
        elsif steps > 200_000
          abort "#{name}: no end after #{steps} steps"
        end
      end
      pair.sync_point
      rc
    end

    def run
      @cases.times do |i|
        data = @samples.any
        stream, wbits, dict = deflated(data)
        name = "inflate case #{i} (#{data.bytesize} bytes, wbits #{wbits}#{dict ? ", dictionary" : ""})"
        if @corrupt
          corrupt(stream, wbits, dict, name)
        else
          pair = Pair.new(@port, @libz, name)
          rc = drive(pair, stream, wbits, dict, name)
          pair.end_stream
          abort "#{name}: ended with #{rc}" unless rc == Z_STREAM_END
          abort "#{name}: the output is not the input" unless @out == data
          @bytes += data.bytesize
        end
      end
      puts "#{@corrupt ? "inflate-corrupt" : "inflate"}: #{@cases} cases agree#{@corrupt ? "" : ", #{@bytes} bytes round-tripped"}"
    end

    # The stream broken in the ways a corrupt file is.
    def corrupt(stream, wbits, dict, name)
      broken = case @random.rand(6)
               when 0 then stream.byteslice(0, @random.rand(stream.bytesize + 1))
               when 1
                 s = stream.dup
                 at = @random.rand(s.bytesize)
                 s.setbyte(at, s.getbyte(at) ^ (1 << @random.rand(8)))
                 s
               when 2
                 s = stream.dup
                 at = @random.rand(s.bytesize)
                 s.setbyte(at, @random.rand(256))
                 s
               when 3 then stream + @random.bytes(@random.rand(1..100))
               when 4 then @random.bytes(@random.rand(1..2000))
               else stream
               end
      broken = "" if broken.nil?
      case @random.rand(4)
      when 0 then wbits = [8, -8, 9, 24, 40, 47].sample(random: @random)
      when 1 then dict = @samples.text(50)
      end
      pair = Pair.new(@port, @libz, "#{name}, corrupted")
      rc = drive(pair, broken, wbits, dict, name)
      if @random.rand(2).zero? && rc != Z_STREAM_END
        pair.input(stream.byteslice(@random.rand(stream.bytesize)..) || "")
        pair.sync
        pair.call(:inflate, Z_NO_FLUSH, @samples.room)
      end
      pair.reset
      pair.end_stream
    end
  end

  def self.main(argv)
    mode = argv.find { |a| a.start_with?("--") && !%w[--cases --seed].include?(a) }
    cases = (argv.index("--cases") ? argv[argv.index("--cases") + 1] : "300").to_i
    seed = (argv.index("--seed") ? argv[argv.index("--seed") + 1] : "1").to_i
    abort "ruby's zlib is #{Zlib::ZLIB_VERSION}, not 1.3.1: the recordings would not be ruby's" unless Zlib::ZLIB_VERSION == "1.3.1"
    port = Port.new
    case mode
    when "--check" then Check.new(port, seed, cases).run
    when "--inflate" then Inflate.new(port, Libz.new, seed, cases).run
    when "--inflate-corrupt" then Inflate.new(port, Libz.new, seed, cases, corrupt: true).run
    else abort "usage: ruby -Ilib tools/zlib_diff.rb --check|--inflate|--inflate-corrupt [--cases N] [--seed S]"
    end
  end
end

ZlibDiff.main(ARGV) if $PROGRAM_NAME == __FILE__
