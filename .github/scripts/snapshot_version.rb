# frozen_string_literal: true

# Sets the version in lib/zr/version.rb to the one of a snapshot of a
# commit: the version, then `.g` and the first 7 characters of the SHA,
# as `git describe` names a commit. RubyGems takes it as a prerelease, so
# it sorts before the release itself. The snapshot workflow runs it before
# it builds the gem, and reads `version=` on GITHUB_OUTPUT.
#
#   ruby .github/scripts/snapshot_version.rb SHA

require_relative "../../lib/zr/version"
require_relative "../../tool/bump"

sha = ARGV.fetch(0) { abort "usage: ruby .github/scripts/snapshot_version.rb SHA" }
abort "snapshot_version: #{sha} is not a commit SHA" unless sha.match?(/\A\h{40}\z/)

version = "#{Zr::VERSION}.g#{sha[0, 7]}"
path = File.expand_path("../../lib/zr/version.rb", __dir__)
File.write(path, Zr::Dev::Commands::Bump.version_rb(File.read(path), version))
File.write(ENV.fetch("GITHUB_OUTPUT"), "version=#{version}\n", mode: "a") if ENV["GITHUB_OUTPUT"]
puts version
