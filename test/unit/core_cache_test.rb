# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require "tmpdir"
require "zr/native/build"

# The core cache takes each core file that did not change from an entry of
# an earlier build, and lowers the others. The runtime object must be the
# same, byte for byte, as a build that lowers every file.
class CoreCacheTest < Minitest::Test
  EDITED = "lib/zr/runtime/core/comparable.rb"

  def setup
    skip "a native link on this host only" unless Zr::Target.default.link
    @work = Dir.mktmpdir("zr-core-cache-")
  end

  def teardown
    Zr::Session.current.forget(:cache)
    FileUtils.rm_rf(@work) if @work
  end

  # Builds the runtime object in the cache `dir`, with the file EDITED
  # given `extra` at its end, and returns the object's bytes.
  def object(dir, extra, code_cache:)
    Zr::Config.with(ZR_CODE_CACHE: code_cache ? "1" : "0") do
      Zr::Session.current.set(:cache, dir)
      runtime = Zr::Runtime.new(Zr::Target.default)
      path = File.join(Zr::Paths::ROOT, EDITED)
      runtime.sources[path] = File.read(path) + extra
      File.binread(Zr::Native::Build.runtime_object(runtime))
    ensure
      Zr::Session.current.forget(:cache)
    end
  end

  # It builds the runtime three times, which takes minutes, so only a run
  # that asks has it: `ZR_TEST_ALL=1 bin/zr-dev test test/unit/core_cache_test.rb`.
  if Zr::Test.flag?("ZR_TEST_ALL")
    def test_an_edit_takes_the_other_files_from_entries_and_gives_the_same_object
      kept = File.join(@work, "kept")
      object(kept, "", code_cache: true) # writes the entries
      edited = "\nmodule Comparable\n  def __core_cache_probe = 1\nend\n"
      cached = object(kept, edited, code_cache: true)
      full = object(File.join(@work, "full"), edited, code_cache: false)

      assert_equal full.bytesize, cached.bytesize
      assert_equal full, cached, "the object from the core cache differs from a full build"
    end
  end
end
