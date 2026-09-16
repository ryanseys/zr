# The zlib port against ruby's zlib, in one process. The port is the
# kernel unit rt/kernel/zlib_*.rb (never zlib.rb, the seam, which needs
# the whole kernel), compiled by the Ruby backend and loaded into this
# ruby through Obj::JIT; the oracle is the zlib ruby 4.0.6 links, 1.3.1,
# reached through Zlib itself where the API reaches it and through
# Fiddle where the harness must control every call.
#
#   ruby -Ilib tools/zlib_diff.rb --check [--cases N] [--seed S]
#
# --check: adler32, crc32, their combines and the crc table.
require "zlib"
require "fiddle"
require "ze0/machine/lower"
require "ze0/native/build"
require "ze0/obj/jit/fiddle"

module ZlibDiff
  ROOT = File.expand_path("..", __dir__)

  # The port's functions, called through Fiddle.
  class Port
    TYPES = { "Word" => Fiddle::TYPE_LONG, "Ptr" => Fiddle::TYPE_VOIDP, "I32" => Fiddle::TYPE_INT, "I8" => Fiddle::TYPE_CHAR, "Bool" => Fiddle::TYPE_CHAR, "Void" => Fiddle::TYPE_VOID }.freeze

    def initialize
      paths = Dir[File.join(ROOT, "rt/kernel/zlib_*.rb")].sort
      lower = Ze0::Machine.unit(paths)
      unit = Ze0::Native::Build.unit(lower.functions, lower.data, raw: lower.raw)
      @symbols = Ze0::Obj::JIT.load(unit, host: Ze0::Obj::JIT::Fiddle.new)
      @defs = lower.instance_variable_get(:@defs)
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

  def self.main(argv)
    mode = argv.find { |a| a.start_with?("--") && !a.include?("=") && !%w[--cases --seed].include?(a) }
    cases = (argv.index("--cases") ? argv[argv.index("--cases") + 1] : "300").to_i
    seed = (argv.index("--seed") ? argv[argv.index("--seed") + 1] : "1").to_i
    abort "ruby's zlib is #{Zlib::ZLIB_VERSION}, not 1.3.1: the recordings would not be ruby's" unless Zlib::ZLIB_VERSION == "1.3.1"
    port = Port.new
    case mode
    when "--check" then Check.new(port, seed, cases).run
    else abort "usage: ruby -Ilib tools/zlib_diff.rb --check [--cases N] [--seed S]"
    end
  end
end

ZlibDiff.main(ARGV) if $PROGRAM_NAME == __FILE__
