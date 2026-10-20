# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"
require_relative "../../lib/zr/runtime"
require_relative "../../lib/zr/ir/fingerprint"

# The kernel's lowering is kept between builds (`Zr::Cache::Kernel`). Its
# key covers each file that the lowering loads, and a kept lowering is the
# same as a new one.
class KernelCacheTest < Minitest::Test
  Kernel = Zr::Cache::Kernel

  def test_the_list_is_every_file_that_the_kernel_lowering_loads
    lib = "#{Kernel::LIB}/"
    code = <<~RUBY
      before = $LOADED_FEATURES.dup
      #{Kernel::ENTRIES.map { |name| "require #{File.join(lib, name).inspect}" }.join("\n")}
      puts ($LOADED_FEATURES - before).select { |f| f.start_with?(#{lib.inspect}) }.map { |f| f.delete_prefix(#{lib.inspect}) }.sort
    RUBY
    out, status = Open3.capture2(Zr::Harness::CleanEnv.env, RbConfig.ruby, "-e", code, unsetenv_others: true)
    assert_predicate status, :success?
    assert_equal Kernel.loads, out.split("\n"),
                 "Cache::Kernel.loads misses a file that the kernel lowering loads; load a file at the top with require_relative"
  end

  def test_a_kept_kernel_is_the_same_as_a_new_one
    runtime = Zr::Runtime.new(Zr::Target.default)
    files = Zr::RuntimeSources.for(runtime.target).kernel_files.map { |path| [runtime.sources.fetch(path), path] }
    fresh = Zr::Machine::Lower.new(files).tap(&:run)
    kept = Marshal.load(Marshal.dump(fresh))

    names = Set.new
    assert_equal fresh.functions.map { |f| Zr::IR::Fingerprint.of(f, names) }, kept.functions.map { |f| Zr::IR::Fingerprint.of(f, names) }
    assert_equal Zr::Machine::Description.of(fresh).to_text, Zr::Machine::Description.of(kept).to_text
    assert_equal fresh.symbols.names, kept.symbols.names
    assert_equal fresh.data.map(&:name), kept.data.map(&:name)
  end

  def test_the_key_changes_with_a_kernel_file
    files = [["def zr_a = 1\n", "/k/a.rb"]]
    target = Zr::Target.default
    refute_equal Kernel.key(target, files), Kernel.key(target, [["def zr_a = 2\n", "/k/a.rb"]])
    refute_equal Kernel.key(target, files), Kernel.key(target, [["def zr_a = 1\n", "/k/b.rb"]])
  end
end
