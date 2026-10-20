# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/prebuilt"

# A target's built runtime as one file (lib/zr/prebuilt.rb): what export
# writes, import puts back, and every bundle that import refuses.
class PrebuiltTest < Minitest::Test
  Prebuilt = Zr::Prebuilt
  Store = Zr::Cache::Store
  Paths = Zr::Paths
  TARGET = Zr::Target::AARCH64_DARWIN

  # A real warm builds a runtime; these tests give the roots themselves.
  def setup
    @warm = Prebuilt.method(:warm)
    Prebuilt.define_singleton_method(:warm) { |_target| nil }
    @dirs = []
    @from = cache
    @bundle = File.join(Dir.mktmpdir("zr-bundle-").tap { |dir| @dirs << dir }, "runtime.zrr")
  end

  def teardown
    Prebuilt.define_singleton_method(:warm, @warm)
    Zr::Session.current.forget(:cache)
    @dirs.each { |dir| FileUtils.rm_rf(dir) }
  end

  # A new cache, which the store uses from now on.
  def cache
    dir = Dir.mktmpdir("zr-prebuilt-").tap { |made| @dirs << made }
    Zr::Session.current.set(:cache, dir)
    dir
  end

  # A runtime's roots: a link root with a file and a directory entry, a
  # built mark, and a lowering that a bundle leaves out.
  def built_runtime
    object = Store.path(:object, Store.key("runtime"))
    Paths.write_atomic(object, "object bytes")
    code = Store.path(:code, Store.key("code"))
    Paths.write_atomic(File.join(code, "runtime.pack"), "pack bytes")
    mark = Store.path(:built, Store.key("mark"))
    Paths.write_atomic(mark, "")
    lowering = Store.path(:lowering, Store.key("lowering"))
    Paths.write_atomic(lowering, "lowering bytes")
    Store.root("#{TARGET.triple}-link-plain", [object, code])
    Store.root("#{TARGET.triple}-built-plain", [mark])
    Store.root("#{TARGET.triple}-core", [lowering])
    { object:, code:, mark:, lowering: }
  end

  def store_files(dir) = Dir.glob("**/*", base: File.join(dir, "store")).select { |rel| File.file?(File.join(dir, "store", rel)) }.sort

  def test_an_import_puts_back_the_entries_and_roots_that_an_export_wrote
    built = built_runtime
    manifest = Prebuilt.export(TARGET, @bundle)

    assert_equal %W[#{TARGET.triple}-built-plain #{TARGET.triple}-link-plain], manifest.fetch("roots").keys
    to = cache
    Prebuilt.import(@bundle)

    assert_equal "object bytes", File.binread(built[:object].sub(@from, to))
    assert_equal "pack bytes", File.binread(File.join(built[:code].sub(@from, to), "runtime.pack"))
    assert_path_exists built[:mark].sub(@from, to)
    refute_path_exists built[:lowering].sub(@from, to), "a bundle leaves out the lowerings"
    assert_equal File.read(File.join(@from, "store/roots/#{TARGET.triple}-link-plain")),
                 File.read(File.join(to, "store/roots/#{TARGET.triple}-link-plain"))
    assert_empty Dir.glob(File.join(to, "store/.import-*")), "the import leaves no staging directory"
  end

  def test_two_exports_of_one_cache_are_the_same_bytes
    built_runtime
    Prebuilt.export(TARGET, @bundle)
    again = "#{@bundle}.again"
    Prebuilt.export(TARGET, again)

    assert_equal File.binread(@bundle), File.binread(again)
  end

  def test_an_export_refuses_an_entry_that_names_the_install_s_path
    built = built_runtime
    File.write(built[:object], "loads #{Paths::ROOT}/lib/zr/runtime/core/array.rb")

    error = assert_raises(Prebuilt::Invalid) { Prebuilt.export(TARGET, @bundle) }
    assert_match "names this install's path", error.message
    refute_path_exists @bundle
  end

  def test_an_export_of_a_target_with_no_runtime_says_so
    assert_raises(Prebuilt::Invalid) { Prebuilt.export(TARGET, @bundle) }
  end

  def test_an_import_checks_the_digest_that_the_caller_gives
    built_runtime
    Prebuilt.export(TARGET, @bundle)
    cache

    assert_raises(Prebuilt::Invalid) { Prebuilt.import(@bundle, sha256: "0" * 64) }
    Prebuilt.import(@bundle, sha256: Digest::SHA256.file(@bundle).hexdigest.upcase)
  end

  def test_an_import_refuses_a_changed_file_and_puts_nothing_in_place
    built_runtime
    Prebuilt.export(TARGET, @bundle)
    rewrite { |_, files| files.transform_values { |bytes| bytes.sub("object", "OBJECT") } }
    to = cache

    assert_raises(Prebuilt::Invalid) { Prebuilt.import(@bundle) }
    assert_empty store_files(to)
  end

  def test_an_import_refuses_a_path_that_is_no_entry_of_the_store
    built_runtime
    ["../outside", "/etc/passwd", "object/ab/../../../x", "roots/#{TARGET.triple}-link-plain"].each do |bad|
      Zr::Session.current.set(:cache, @from)
      Prebuilt.export(TARGET, @bundle)
      rewrite do |manifest, files|
        row = manifest["files"].first
        files[bad] = files.delete(row["path"])
        row["path"] = bad
        files
      end
      to = cache

      error = assert_raises(Prebuilt::Invalid, bad) { Prebuilt.import(@bundle) }
      assert_match "no entry of the store", error.message
      assert_empty store_files(to), bad
    end
  end

  def test_an_import_refuses_a_bundle_of_another_zr
    built_runtime
    Prebuilt.export(TARGET, @bundle)
    rewrite { |manifest, files| (manifest["zr"] = "0.0.1") && files }
    cache

    error = assert_raises(Prebuilt::Invalid) { Prebuilt.import(@bundle) }
    assert_match "zr 0.0.1", error.message
  end

  def test_an_import_refuses_a_file_that_is_no_bundle
    File.write(@bundle, "not gzip")
    assert_raises(Prebuilt::Invalid) { Prebuilt.import(@bundle) }
  end

  private

  # Writes the bundle again, with the manifest and the files (path to
  # bytes) that the block returns.
  def rewrite
    manifest = nil
    files = {}
    Zlib::GzipReader.open(@bundle) do |gz|
      gz.gets
      manifest = JSON.parse(gz.gets)
      manifest["files"].each { |row| files[row["path"]] = gz.read(row["size"]).to_s }
    end
    files = yield(manifest, files)
    Zlib::GzipWriter.open(@bundle) do |gz|
      gz.write("#{Prebuilt::FORMAT}\n#{JSON.generate(manifest)}\n")
      manifest["files"].each { |row| gz.write(files.fetch(row["path"])) }
    end
  end
end
