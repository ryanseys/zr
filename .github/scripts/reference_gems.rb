# frozen_string_literal: true

# Installs the gems that the reference ruby needs for test/ext
# (`Zr::Test::CExt::REFERENCE_GEMS`, test/support/c_ext.rb) into the ruby
# that runs this script, so that the C extension tests run in place of
# skipping. The full CI run calls it.
#
#   ruby .github/scripts/reference_gems.rb

require "rubygems"
source = File.read(File.expand_path("../../test/support/c_ext.rb", __dir__))
# A literal Hash of this repository's own file.
gems = eval(source[/REFERENCE_GEMS = (\{[^}]*\})/, 1] || abort("reference_gems: no REFERENCE_GEMS in test/support/c_ext.rb"))
gems.each do |name, version|
  next puts("#{name} #{version}: installed") if Gem::Specification.find_all_by_name(name, version).any?

  system(Gem.ruby, "-S", "gem", "install", "--no-document", name, "-v", version, exception: true)
end
