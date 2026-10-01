# frozen_string_literal: true

require "test_helper"
require "digest"
require "zr/library/roots"

# vendor/ is upstream code, byte for byte (lib/zr/library/vendor.rb). These
# checks need no network: vendor/vendor.lock has the SHA-256 of each
# file that `zr-dev vendor` wrote.
#
# zr's own code under lib/zr/runtime/ comes first on the load path, so a file
# there with the name of a vendored file replaces it: an overlay. Each
# overlay names the file that it replaces and that file's digest, so an
# update of the vendored file stops here until someone reads the new
# upstream file and checks the overlay against it.
class VendorTest < Minitest::Test
  LOCK = Zr::Library::Layout::LOCK
  OVERLAY = /^# zr overlay: replaces (\S+) of (\S+) (\S+) \(sha256 (\h{12})\)$/

  def locked
    @locked ||= File.foreach(LOCK, chomp: true).drop_while { |line| line != "files" }.drop(1).to_h do |line|
      sha, rel = line.split(" ", 2)
      [rel, sha]
    end
  end

  def test_every_vendored_file_is_the_one_the_lock_names
    have = Dir.glob("{ruby,LICENSES,src}/**/*", File::FNM_DOTMATCH, base: Zr::Paths::VENDOR)
              .select { |rel| File.file?(File.join(Zr::Paths::VENDOR, rel)) }

    differ = (have & locked.keys).reject { |rel| Digest::SHA256.file(File.join(Zr::Paths::VENDOR, rel)).hexdigest == locked[rel] }

    assert_equal [], differ, "vendor/ is upstream code: never edit it; replace a file with an overlay under lib/zr/runtime/"
    assert_equal [], have - locked.keys
    assert_equal [], locked.keys - have
  end

  def test_each_overlay_names_the_file_it_replaces
    stale = overlays.filter_map do |ours, theirs|
      header = File.foreach(ours).first(5).join[OVERLAY]
      digest = Digest::SHA256.file(theirs).hexdigest[0, 12]
      next "#{rel(ours)}: no `# zr overlay: replaces ...` line for #{rel(theirs)} (sha256 #{digest})" unless header

      feature = header[OVERLAY, 1]
      next "#{rel(ours)}: replaces #{feature}, not #{File.basename(theirs)}" unless theirs.end_with?("/#{feature}")
      next "#{rel(ours)}: #{rel(theirs)} changed (sha256 #{digest}); check the overlay, then update its line" if header[OVERLAY, 4] != digest
    end

    assert_equal [], stale
  end

  # Each file under a lib/zr/runtime/ root with the path of a file under a
  # vendor/ root, as `[ours, theirs]`.
  def overlays
    roots = Zr::Library::Roots.stdlib(Zr::Target.default)
    ours = roots.select { |root| root.start_with?("#{Zr::Paths::RUNTIME}/") } + Dir[File.join(Zr::Library::Layout::EXT, "os", "*")]
    theirs = roots - ours
    ours.uniq.flat_map do |root|
      Dir.glob("**/*.rb", base: root).filter_map do |path|
        next if root == Zr::Library::Layout::EXT && path.start_with?("os/")

        found = theirs.find { |dir| File.file?(File.join(dir, path)) }
        [File.join(root, path), File.join(found, path)] if found
      end
    end
  end

  def rel(path) = path.delete_prefix("#{ROOT}/")
end
