# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# msgpack, a real gem with a C extension, in a zr binary that links the C
# that this ruby compiled when it installed the gem (`--native-ext`). Each
# program gives ruby's output, also under ZR_GC_STRESS, where each
# allocation collects while msgpack's C holds Values.
class CExtMsgpackTest < Minitest::Test
  # Each program is a test for each run, by the name's suffix, so a test
  # runs one binary in the worker's time limit; the build is cached.
  RUNS = { "" => {}, "_under_stress" => { "ZR_GC_STRESS" => "1" } }.freeze
  VERIFIED = RUNS.merge("_verified" => { "ZR_GC_STRESS" => "1", "ZR_GC_VERIFY" => "1" }).freeze

  def self.same_as_ruby(name, program, runs: RUNS)
    runs.each { |suffix, env| define_method(:"test_#{name}#{suffix}") { assert_same_as_ruby(program, env) } }
  end

  def setup
    skip Zr::Test::CExt::UNSUPPORTED unless Zr::Test::CExt.supported?
    @version = Zr::Test::CExt.installed("msgpack")
    skip "msgpack is not installed in this ruby" unless @version
  end

  def assert_same_as_ruby(program, env)
    ruby, (zr,) = Zr::Test::CExt.gem_outputs("msgpack", @version, program, [env])
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [zr.stdout, zr.status], "zr's output differs from ruby's under #{env}\nzr stderr:\n#{zr.stderr}"
  end

  same_as_ruby "each_core_type_packs_to_rubys_bytes_and_back", <<~RUBY
    require "msgpack"
    values = [nil, true, false, 0, 1, 127, 128, 255, 256, 65_535, 65_536, 2**32 - 1, 2**32, 2**62, 2**64 - 1,
              -1, -32, -33, -128, -129, -32_768, -32_769, -(2**31), -(2**31) - 1, -(2**63),
              0.0, -1.5, 3.14159, 1e300, Float::INFINITY,
              "", "abc", "x" * 31, "x" * 32, "y" * 300, "caf\\u00e9", "\\xff\\x00".b, :sym,
              [], [1, [2, [3]]], {}, { "k" => { "n" => [nil] } }, { 1 => 2, nil => true }]
    values.each do |v|
      packed = MessagePack.pack(v)
      back = MessagePack.unpack(packed)
      p [packed.bytes.first(6), packed.bytesize, back, back.class, (back.encoding if back.is_a?(String))]
    end
    p MessagePack.pack(values).bytesize, MessagePack.unpack(MessagePack.pack(values)).size
    [2**64, -(2**63) - 1].each do |big|
      MessagePack.pack(big)
    rescue RangeError => e
      p [e.class, e.message]
    end
  RUBY

  same_as_ruby "a_packer_and_an_unpacker_stream", <<~RUBY
    require "msgpack"
    pk = MessagePack::Packer.new
    pk.write_array_header(3).write(1).write("two").write_nil
    pk.write_map_header(1).write(:a).write(2.5)
    packed = pk.to_s
    p packed.bytes
    u = MessagePack::Unpacker.new
    u.feed(packed)
    u.each { |obj| p obj }
    u.feed(packed[0, 3])
    p u.each.to_a rescue p $!.class
    u.feed(packed[3..])
    u.each { |obj| p [:rest, obj] }
    u2 = MessagePack::Unpacker.new
    u2.feed([1, 2].to_msgpack + "z".to_msgpack)
    p u2.read_array_header, u2.read, u2.read, u2.read
    begin
      u2.read
    rescue EOFError => e
      p e.class
    end
    p MessagePack.unpack({ "a" => 1 }.to_msgpack, symbolize_keys: true)
    frozen = MessagePack.unpack(["s", { "k" => "v" }].to_msgpack, freeze: true)
    p frozen.frozen?, frozen[0].frozen?, frozen[1].frozen?
  RUBY

  same_as_ruby "a_factory_packs_and_unpacks_extension_types", <<~RUBY
    require "msgpack"
    Point = Struct.new(:x, :y)
    factory = MessagePack::Factory.new
    factory.register_type(1, Point, packer: ->(pt) { [pt.x, pt.y].pack("l>l>") },
                                    unpacker: ->(data) { Point.new(*data.unpack("l>l>")) })
    factory.register_type(2, Symbol)
    bytes = factory.dump([Point.new(3, -4), :tag, { p: Point.new(0, 1) }])
    p bytes.bytes
    p factory.load(bytes)
    p factory.registered_types.map { |t| [t[:type], t[:class]] }
    t = MessagePack::Timestamp.new(1_700_000_000, 123)
    p MessagePack::Timestamp.from_msgpack_ext(t.to_msgpack_ext) == t
    begin
      MessagePack.unpack("\\xd4\\x05\\x00".b)
    rescue => e
      p e.class
    end
    ext = MessagePack.unpack("\\xd4\\x05\\x00".b, allow_unknown_ext: true)
    p [ext.class, ext.type, ext.payload]
  RUBY

  same_as_ruby "malformed_input_raises_rubys_errors", <<~RUBY
    require "msgpack"
    ["\\xc1".b, "\\x91".b, "\\xdc\\x00".b, "\\x81\\xa1".b].each do |bytes|
      MessagePack.unpack(bytes)
    rescue => e
      p [e.class, e.class.ancestors.include?(MessagePack::UnpackError)]
    end
    u = MessagePack::Unpacker.new
    u.feed("\\x01".b)
    begin
      u.read_map_header
    rescue => e
      p e.class
    end
    class NoPack; end
    begin
      MessagePack.pack(NoPack.new)
    rescue NoMethodError => e
      p e.class
    end
  RUBY

  # A larger document, packed and unpacked many times: under stress, each
  # allocation collects while msgpack's buffers and C stack hold Values.
  same_as_ruby "a_larger_document_survives_the_collector", <<~RUBY, runs: VERIFIED
    require "msgpack"
    doc = Array.new(60) { |i| { "id" => i, "name" => "item \#{i}" * (i % 4), "tags" => [:a, "b\#{i}", i * 1.5], "big" => 2**(40 + (i % 24)) } }
    sums = 3.times.map do
      bytes = MessagePack.pack(doc)
      back = MessagePack.unpack(bytes)
      [bytes.bytesize, back.sum { |h| h["id"] }, back.last["name"], back[7]["big"]]
    end
    p sums.uniq
  RUBY
end
