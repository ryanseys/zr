# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require "open3"
require "tmpdir"
require "zr/native/build"

# The code cache keeps each function's machine code by a fingerprint of
# its IR. The fingerprint must cover every field that assembly reads, and
# the cache's key every file that the passes and the backend load.
class CodeCacheTest < Minitest::Test
  Fingerprint = Zr::IR::Fingerprint
  Code = Zr::Cache::Code

  # A function with a call, a load and a branch, built as the lowering
  # builds one.
  def function(name = "f", offset: 8)
    f = Zr::IR::Function.new(name, %w[i64], "i64")
    callee = f.callee("zr_other", %w[i64], "i64")
    v = f.fetch("i64", f.args.first, offset)
    yes = f.label
    no = f.label
    f.brif(v, yes, no)
    f.switch(yes)
    f.ret(f.call_val(callee, [v]))
    f.switch(no)
    f.ret(v)
    f
  end

  def test_the_fingerprint_names_each_field_of_the_ir
    f = function
    assert_equal (Fingerprint::FIELDS.fetch(Zr::IR::Function) + Fingerprint::BUILDER).sort, f.instance_variables.sort
    assert_equal Fingerprint::FIELDS.fetch(Zr::IR::Block).sort, f.blocks.first.instance_variables.sort
    f.blocks.flat_map(&:insts).each { |i| assert_equal Fingerprint::FIELDS.fetch(Zr::IR::Inst).sort, i.instance_variables.sort }
  end

  def test_equal_functions_have_one_fingerprint_and_a_change_has_another
    none = Set.new
    assert_equal Fingerprint.of(function, none), Fingerprint.of(function, none)
    refute_equal Fingerprint.of(function, none), Fingerprint.of(function(offset: 16), none)
    refute_equal Fingerprint.of(function, none), Fingerprint.of(function("g"), none)
    refute_equal Fingerprint.of(function, none), Fingerprint.of(function, Set["zr_other"])
  end

  def test_each_backend_digest_covers_every_file_that_its_entries_load
    Code::ENTRIES.each do |arch, entries|
      code = <<~RUBY
        before = $LOADED_FEATURES.dup
        #{entries.map { |name| "require #{File.join(Code::LIB, name).inspect}" }.join("\n")}
        puts ($LOADED_FEATURES - before).select { |f| f.start_with?(#{"#{Code::LIB}/".inspect}) }.map { |f| f.delete_prefix(#{"#{Code::LIB}/".inspect}) }.sort
      RUBY
      # A ruby outside this bundle: bundler's setup reads zr.gemspec, which
      # loads version.rb before the list starts.
      out, status = Open3.capture2(Zr::Harness::CleanEnv.env, RbConfig.ruby, "-e", code, unsetenv_others: true)
      assert_predicate status, :success?
      assert_equal Code.files(arch), out.split("\n"),
                   "Cache::Code.files(#{arch.inspect}) misses a file that #{entries.join(", ")} load; " \
                   "load a file at the top with require_relative"
    end
  end

  def test_each_backend_keeps_its_code_in_its_own_directory
    assert_equal 3, Code::ENTRIES.keys.map { |arch| Code.dir(arch) }.uniq.size
  end

  # x86_64 keeps its pieces and code too (Lowering::Core and EvalSupport
  # take their code from it); wasm keeps its bodies apart (`Code.wasm`).
  def test_each_native_target_has_a_code_cache_and_wasm_has_none
    assert_kind_of Code, Code.for("runtime", Zr::Target.fetch("x86_64-linux-gnu"))
    assert_kind_of Code, Code.for("runtime", Zr::Target::AARCH64_DARWIN)
    assert_nil Code.for("runtime", Zr::Target.fetch("wasm32-wasi"))
  end

  # A lowering that made a piece keeps the code of its pieces itself: a
  # build that writes no object (one that reads only eval support's
  # metadata) would leave the next process entries with no code.
  def test_a_lowering_that_made_a_piece_keeps_the_code_of_its_pieces
    Dir.mktmpdir("zr-code-cache-") do |dir|
      Zr::Session.current.set(:cache, dir)
      kept = %w[made taken].to_h do |kind|
        lowering = Zr::Cache::Lowering.new("test-#{kind}", Zr::Target::AARCH64_DARWIN, Code.new("test-#{kind}", :aarch64))
        lowering.known["zr_f"] = %w[key blob]
        lowering.send(:keep, [], [], kind == "made")
        [kind, Code.new("test-#{kind}", :aarch64)]
      end

      assert_equal "blob", kept.fetch("made").blob("key")
      refute kept.fetch("taken").has?("key")
    ensure
      Zr::Session.current.forget(:cache)
    end
  end

  # Part of the kernel, so that the test takes seconds: the object of its
  # first 600 functions, with its data. The kernel comes from its cache;
  # the whole runtime lowered the core too (60-79 s on a runner).
  def test_an_object_is_the_same_with_the_cache_cold_warm_and_off
    skip "a native link on this host only" unless Zr::Target.default.link

    # Its own runtime: `Native::Build.lower` releases the IR of the
    # process's `Zr::Runtime.for`, so an earlier build would leave none here.
    kernel = Zr::Runtime.new(Zr::Target.default).unit
    functions = Marshal.dump(kernel.functions.first(600))
    Dir.mktmpdir("zr-code-cache-") do |dir|
      cache = File.join(dir, "cache")
      objects = %w[off cold warm].map do |mode|
        out = File.join(dir, "#{mode}.o")
        Zr::Config.with(ZR_CODE_CACHE: mode == "off" ? "0" : "1") do
          Zr::Session.current.set(:cache, cache)
          why = Zr::Native::Build.object(Marshal.load(functions), kernel.data, out, export: true,
                                         cache: Zr::Cache::Code.for("test", Zr::Target.default))
          assert_nil why
        ensure
          Zr::Session.current.forget(:cache)
        end
        File.binread(out)
      end
      assert_equal objects[0], objects[1], "cold"
      assert_equal objects[0], objects[2], "warm"
    end
  end
end
