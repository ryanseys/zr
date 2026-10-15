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

  def test_each_backend_list_is_every_file_that_its_passes_and_emitter_load
    { aarch64: "backend/aarch64.rb", wasm32: "backend/wasm.rb" }.each do |arch, entry|
      code = <<~RUBY
        before = $LOADED_FEATURES.dup
        require #{File.join(Code::LIB, "cache/code.rb").inspect}
        require #{File.join(Code::LIB, "ir/passes.rb").inspect}
        require #{File.join(Code::LIB, entry).inspect}
        puts ($LOADED_FEATURES - before).select { |f| f.start_with?(#{"#{Code::LIB}/".inspect}) }.map { |f| f.delete_prefix(#{"#{Code::LIB}/".inspect}) }.sort
      RUBY
      # A ruby outside this bundle: bundler's setup reads zr.gemspec, which
      # loads version.rb before the list starts.
      out, status = Open3.capture2(Zr::Harness::CleanEnv.env, RbConfig.ruby, "-e", code, unsetenv_others: true)
      assert_predicate status, :success?
      assert_equal Code::BACKENDS.fetch(arch).sort, out.split("\n"),
                   "Cache::Code::BACKENDS[#{arch.inspect}] must list each file that the passes and #{entry} load"
    end
  end

  def test_each_backend_keeps_its_code_in_its_own_directory
    refute_equal Code.dir(:aarch64), Code.dir(:wasm32)
  end

  # Part of the runtime, so that the test takes seconds: the object of its
  # first 600 functions, with the data.
  def test_an_object_is_the_same_with_the_cache_cold_warm_and_off
    skip "a native link on this host only" unless Zr::Target.default.link

    # Its own runtime: `Native::Build.lower` releases the IR of the
    # process's `Zr::Runtime.for`, so an earlier build would leave none here.
    runtime = Zr::Runtime.new(Zr::Target.default)
    functions = Marshal.dump(runtime.functions.first(600))
    Dir.mktmpdir("zr-code-cache-") do |dir|
      cache = File.join(dir, "cache")
      objects = %w[off cold warm].map do |mode|
        out = File.join(dir, "#{mode}.o")
        Zr::Config.with(ZR_CODE_CACHE: mode == "off" ? "0" : "1") do
          Zr::Session.current.set(:cache, cache)
          why = Zr::Native::Build.object(Marshal.load(functions), runtime.data, out, export: true,
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
