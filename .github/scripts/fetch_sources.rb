# frozen_string_literal: true

# Fetches the C sources that the generators and `zr-dev vendor` read:
# CRuby at RUBY_REVISION into tmp/ruby, and prism at the commit that
# vendor/vendor.lock names into tmp/prism. Each is one shallow commit,
# and a checkout that already holds its commit is left as it is. The
# readers take files with `git show`, so no work tree is checked out.
#
#   ruby .github/scripts/fetch_sources.rb [RUBY_DIR [PRISM_DIR]]
#
# RUBY_SRC and PRISM_SRC name the same directories for zr-dev.

require_relative "../../lib/zr/ruby_version"

root = File.expand_path("../..", __dir__)
ruby_dir = File.expand_path(ARGV.fetch(0, "tmp/ruby"), root)
prism_dir = File.expand_path(ARGV.fetch(1, "tmp/prism"), root)

# The prism commit of the lock's `source prism` row:
#   source prism 1.9.0 - https://github.com/ruby/prism@<commit>
prism_commit = File.foreach(File.join(root, "vendor/vendor.lock")).find { it.start_with?("source prism ") }&.then { it[/@(\h{40})$/, 1] }
abort "fetch_sources: vendor/vendor.lock has no `source prism` row with a commit" unless prism_commit

{ ruby_dir => ["https://github.com/ruby/ruby.git", Zr::RUBY_REVISION],
  prism_dir => ["https://github.com/ruby/prism.git", prism_commit] }.each do |dir, (url, commit)|
  if system("git", "-C", dir, "cat-file", "-e", "#{commit}^{commit}", err: File::NULL)
    puts "fetch_sources: #{dir} has #{commit[0, 12]}"
    next
  end

  puts "fetch_sources: fetching #{url} at #{commit[0, 12]} into #{dir}"
  system("git", "init", "-q", dir, exception: true)
  system("git", "-C", dir, "fetch", "-q", "--depth", "1", url, commit, exception: true)
end
