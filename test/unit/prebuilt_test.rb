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
    @bundle = File.join(Dir.mktmpdir("zr-bundle-").tap { |dir| @dirs << dir }, "runtime.tar.gz")
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
    refute_path_exists built[:code].sub(@from, to), "a bundle leaves out the packs of machine code"
    assert_path_exists built[:mark].sub(@from, to)
    refute_path_exists built[:lowering].sub(@from, to), "a bundle leaves out the lowerings"
    assert_equal File.read(File.join(@from, "store/roots/#{TARGET.triple}-link-plain")),
                 File.read(File.join(to, "store/roots/#{TARGET.triple}-link-plain"))
    assert_empty Dir.glob(File.join(to, ".import-*")), "the import leaves no staging directory"
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

  # A later export reads what a root names, so a root must name entries.
  def test_an_import_refuses_a_root_that_names_a_path_outside_the_store
    built_runtime
    Prebuilt.export(TARGET, @bundle)
    rewrite { |manifest, files| (manifest["roots"]["#{TARGET.triple}-link-plain"] = "../../../etc/passwd\n") && files }
    to = cache

    error = assert_raises(Prebuilt::Invalid) { Prebuilt.import(@bundle) }
    assert_match "no entry of the store", error.message
    refute_path_exists File.join(to, "store/roots/#{TARGET.triple}-link-plain")
  end

  def test_an_import_refuses_a_manifest_of_another_shape
    built_runtime
    Prebuilt.export(TARGET, @bundle)
    rewrite { |manifest, files| (manifest["roots"] = ["x"]) && files }
    cache

    assert_raises(Prebuilt::Invalid) { Prebuilt.import(@bundle) }
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

  # The bundle format before the tar archive: a line, then the JSON.
  def test_an_import_names_a_bundle_of_the_old_format
    Zlib::GzipWriter.open(@bundle) { |gz| gz.write("zr-runtime 1\n{}\n") }

    error = assert_raises(Prebuilt::Invalid) { Prebuilt.import(@bundle) }
    assert_match "older zr's format", error.message
  end

  # A bundle is a plain tar archive in gzip: `tar` lists it, the manifest
  # first, and the unpacked tree imports as the archive does. A platform
  # gem holds the tree (`Prebuilt.bundled`).
  def test_tar_unpacks_a_bundle_and_the_tree_imports_as_the_archive_does
    built = built_runtime
    Prebuilt.export(TARGET, @bundle)
    names = IO.popen(["tar", "-tzf", @bundle], &:read).lines(chomp: true)

    assert_equal Prebuilt::MANIFEST, names.first
    assert_includes names, "#{Prebuilt::STORE}#{built[:object].delete_prefix("#{Store.dir}/")}"
    tree = Dir.mktmpdir("zr-tree-").tap { |dir| @dirs << dir }
    assert system("tar", "-xzf", @bundle, "-C", tree)
    to = cache
    Prebuilt.import(tree)

    assert_equal "object bytes", File.binread(built[:object].sub(@from, to))
  end

  # A wasm32-wasi bundle carries the runtime module of each of its
  # preludes, a standard module that `wasmtime run --preload` links a
  # program module against, with its link section; an import puts it
  # where a split build looks (Prebuilt.modules_dir).
  def test_a_wasm_bundle_carries_the_runtime_module_of_each_prelude
    require_relative "../../lib/zr/backend/wasm"
    wasm = Zr::Target::WASM32_WASI
    key = Store.key("prelude of a test")
    prelude = Store.path(:wasm, key)
    Paths.write_atomic(prelude, Marshal.dump(Zr::Backend::Wasm.prelude([], [], pending: { functions: [], data: [] })))
    Store.root("#{wasm.triple}-prelude-plain", [prelude])
    manifest = Prebuilt.export(wasm, @bundle)
    name = Zr::Native::Build.wasm_runtime_name(key)

    assert_equal [name], manifest.fetch("modules").map { |row| row["path"] }
    assert_includes IO.popen(["tar", "-tzf", @bundle], &:read).lines(chomp: true), "#{Prebuilt::MODULES}#{name}"
    cache
    Prebuilt.import(@bundle)
    bytes = File.binread(File.join(Prebuilt.modules_dir, name))
    assert_equal "\0asm".b, bytes[0, 4]
    assert_includes bytes, JSON.generate({ "zr" => Zr::VERSION, "target" => wasm.triple, "prelude" => key })
  end

  # A platform gem leaves out the roots that Prebuilt::GEM_LEFT_OUT names,
  # and each file that only they name; what is left still imports.
  def test_an_unpack_leaves_out_a_root_and_the_files_that_only_it_names
    built = built_runtime
    walk = Store.path(:object, Store.key("walk"))
    Paths.write_atomic(walk, "walk bytes")
    Store.root("#{TARGET.triple}-link-eval-walk", [walk, built[:object]])
    Prebuilt.export(TARGET, @bundle)
    tree = Dir.mktmpdir("zr-unpacked-").tap { |dir| @dirs << dir }
    manifest = Prebuilt.unpack(@bundle, tree, without: Prebuilt::GEM_LEFT_OUT)

    assert_equal %W[#{TARGET.triple}-built-plain #{TARGET.triple}-link-plain], manifest.fetch("roots").keys
    refute_includes store_files(tree), walk.delete_prefix("#{Store.dir}/")
    assert_includes store_files(tree), built[:object].delete_prefix("#{Store.dir}/")
    cache
    assert_equal manifest.fetch("files").size, Prebuilt.import(tree).fetch("files").size
  end

  # A platform gem carries its host's bundle unpacked (zr.gemspec); the
  # first runtime of a cache takes it in, and later ones read the mark.
  def test_a_carried_bundle_imports_once_for_each_cache
    built = built_runtime
    Prebuilt.export(TARGET, @bundle)
    tree = Dir.mktmpdir("zr-carried-").tap { |dir| @dirs << dir }
    assert system("tar", "-xzf", @bundle, "-C", tree)
    bundled = Prebuilt.method(:bundled)
    Prebuilt.define_singleton_method(:bundled) { |target| target == TARGET ? tree : nil }
    to = cache

    assert Prebuilt.take_bundled(TARGET)
    assert_equal "object bytes", File.binread(built[:object].sub(@from, to))
    import = Prebuilt.method(:import)
    Prebuilt.define_singleton_method(:import) { |*| raise "imported again" }
    assert Prebuilt.take_bundled(TARGET)
    refute Prebuilt.take_bundled(Zr::Target::X86_64_LINUX_GNU), "no bundle of that target"
  ensure
    Prebuilt.define_singleton_method(:bundled, bundled) if bundled
    Prebuilt.define_singleton_method(:import, import) if import
  end

  private

  # Writes the bundle again, with the manifest and the files (path to
  # bytes) that the block returns.
  def rewrite
    manifest = nil
    files = {}
    Zlib::GzipReader.open(@bundle) do |gz|
      Zr::Tar.each(gz) do |name, size|
        bytes = gz.read(size).to_s
        name == Prebuilt::MANIFEST ? (manifest = JSON.parse(bytes)) : (files[name.delete_prefix(Prebuilt::STORE)] = bytes)
      end
    end
    files = yield(manifest, files)
    Zlib::GzipWriter.open(@bundle) do |gz|
      json = JSON.generate(manifest)
      Zr::Tar.add(gz, Prebuilt::MANIFEST, json.bytesize) { |io| io.write(json) }
      manifest["files"].each do |row|
        bytes = files.fetch(row["path"])
        Zr::Tar.add(gz, Prebuilt::STORE + row["path"], bytes.bytesize) { |io| io.write(bytes) }
      end
      Zr::Tar.finish(gz)
    end
  end
end
