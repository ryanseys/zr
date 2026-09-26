# frozen_string_literal: true

require "test_helper"
require "open3"
require_relative "../../lib/zr/compiled_compiler"

# exe/zr gives a build to the compiled compiler only when no source file
# of the compiled compiler has changed. Here a shell script is in place
# of the compiled compiler. Thus the test builds nothing and changes no
# file under lib, runtime or vendor.
class CompiledCompilerTest < Minitest::Test
  EXE = File.join(ROOT, "exe/zr")

  # Yields a directory with a stand-in compiled compiler, and the path of
  # its manifest.
  def with_binary
    Dir.mktmpdir("zr-self-host-") do |dir|
      binary = File.join(dir, "zr")
      File.write(binary, "#!/bin/sh\necho compiled \"$@\"\n")
      File.chmod(0o755, binary)
      yield dir, "#{binary}.manifest"
    end
  end

  def zr(dir, *args, self_env: nil)
    env = { "ZR_CACHE" => File.join(dir, "cache"), "ZR_BINARY" => File.join(dir, "zr"), "ZR_COMPILED" => self_env,
            "RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil }
    out, status = Open3.capture2e(env, RbConfig.ruby, EXE, *args, chdir: ROOT)
    [out, status]
  end

  def test_a_current_compiled_compiler_takes_the_build
    with_binary do |dir, manifest|
      File.binwrite(manifest, Marshal.dump(Zr::CompiledCompiler.stamps))
      out, status = zr(dir, "build", "missing.rb", "-o", "out")
      assert status.success?, out
      assert_equal "compiled build missing.rb -o out\n", out
    end
  end

  def test_changed_source_file_builds_with_ruby
    with_binary do |dir, manifest|
      stamps = Zr::CompiledCompiler.stamps
      file = stamps.keys.first
      stamps[file] = stamps[file].dup.tap { |s| s[0] += 1 }
      File.binwrite(manifest, Marshal.dump(stamps))
      out, = zr(dir, "build", "missing.rb", "-o", "out")
      refute_includes out, "compiled"
    end
  end

  def test_a_file_the_build_did_not_read_leaves_the_build_to_ruby
    with_binary do |dir, manifest|
      stamps = Zr::CompiledCompiler.stamps
      stamps.delete(stamps.keys.last)
      File.binwrite(manifest, Marshal.dump(stamps))
      out, = zr(dir, "build", "missing.rb", "-o", "out")
      refute_includes out, "compiled"
    end
  end

  def test_zr_self_0_and_other_commands_stay_with_ruby
    with_binary do |dir, manifest|
      File.binwrite(manifest, Marshal.dump(Zr::CompiledCompiler.stamps))
      out, = zr(dir, "build", "missing.rb", "-o", "out", self_env: "0")
      refute_includes out, "compiled"
      out, status = zr(dir, "version")
      assert status.success?, out
      refute_includes out, "compiled"
    end
  end

  # In a checkout, a build does not make a compiled compiler when there
  # is none. `ZR_COMPILED=1` or `rake build:self` makes one.
  def test_a_checkout_with_no_compiled_compiler_stays_with_ruby
    skip "not a checkout" unless Zr::Paths.checkout?
    Dir.mktmpdir("zr-self-host-") do |dir|
      out, = zr(dir, "build", "missing.rb", "-o", "out")
      refute_includes out, "building the compiler with itself"
      refute File.exist?(File.join(dir, "zr"))
    end
  end

  def test_the_compiled_compiler_of_a_checkout_is_bin_zr
    skip "not a checkout" unless Zr::Paths.checkout?
    binary = ENV.delete("ZR_BINARY")

    assert_equal File.join(ROOT, "bin/zr"), Zr::CompiledCompiler.binary
    assert_equal File.join(ROOT, "bin/zr.manifest"), Zr::CompiledCompiler.manifest
  ensure
    ENV["ZR_BINARY"] = binary if binary
  end

  # Replaces a class method for the block, then puts it back.
  def swap(owner, name, value)
    was = owner.method(name)
    owner.define_singleton_method(name) { |*| value }
    yield
  ensure
    owner.define_singleton_method(name, was)
  end

  def test_only_a_host_that_runs_its_own_binaries_runs_the_compiled_compiler
    { "aarch64-apple-darwin" => true, "x86_64-apple-darwin" => false, "x86_64-linux" => false,
      "aarch64-linux" => false }.each do |triple, runnable|
      swap(Zr::Target, :host_triple, triple) do
        assert_equal runnable, Zr::CompiledCompiler.runnable?, triple
      end
    end
  end

  def test_a_host_that_cannot_run_it_never_builds_it
    swap(Zr::Target, :host_triple, "x86_64-linux") do
      Dir.mktmpdir("zr-self-host-") do |dir|
        env = { "ZR_COMPILED" => "1" }
        assert_nil Zr::CompiledCompiler.hand_over(["build", EXE, "-o", File.join(dir, "out")], env)
      end
    end
  end

  # With ZR_BINARY unset, only the host gate stands between a command and
  # a build, so the tests set a stand-in path under a temporary directory.
  def with_stand_in
    Dir.mktmpdir("zr-self-host-") do |dir|
      was = ENV.fetch("ZR_BINARY", nil)
      ENV["ZR_BINARY"] = File.join(dir, "zr")
      yield dir
    ensure
      ENV["ZR_BINARY"] = was
    end
  end

  def test_a_help_request_or_a_missing_file_does_not_start_a_build
    with_stand_in do |dir|
      program = File.join(dir, "app.rb")
      File.write(program, "p 1\n")
      env = { "ZR_COMPILED" => "1" }

      assert Zr::CompiledCompiler.builds?(["run", program], env)
      refute Zr::CompiledCompiler.builds?(["run", "--help"], env)
      refute Zr::CompiledCompiler.builds?(["build", program, "-h"], env)
      refute Zr::CompiledCompiler.builds?(["build", File.join(dir, "missing.rb")], env)
    end
  end

  def test_a_failed_build_is_not_tried_again_until_a_source_changes
    Dir.mktmpdir("zr-self-host-") do |dir|
      source = File.join(dir, "source.rb")
      File.write(source, "p 1\n")
      program = Zr::SelfBuilt.new(entry: "exe/zr", binary: File.join(dir, "zr"), dirs: []) { [source] }

      refute program.failed?
      program.fail!
      assert program.failed?

      File.write(source, "p 22\n")
      refute program.failed?
    end
  end

  # An installed gem builds with no ZR_COMPILED; a checkout does not. So
  # the test asks as an installed gem.
  def test_zr_compiled_1_builds_again_after_a_failure
    with_stand_in do |dir|
      program = File.join(dir, "app.rb")
      File.write(program, "p 1\n")
      swap(Zr::Paths, :checkout?, false) do
        assert Zr::CompiledCompiler.builds?(["run", program], {})
        Zr::CompiledCompiler.program.fail!

        refute Zr::CompiledCompiler.builds?(["run", program], {})
        assert Zr::CompiledCompiler.builds?(["run", program], { "ZR_COMPILED" => "1" })
      end
    end
  end

  def test_a_binary_that_the_host_cannot_start_answers_wrongly
    program = Zr::SelfBuilt.new(entry: "exe/zr", binary: "/nonexistent/zr", dirs: [])

    refute(program.send(:answers?) { raise Errno::ENOEXEC })
    assert(program.send(:answers?) { true })
  end
end
