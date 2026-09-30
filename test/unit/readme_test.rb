# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/version"

# The README ships in the gem, and rubygems.org and rubydoc show it with
# no repository around it. So each of its links is absolute, and names
# the files at this version's tag. A link inside docs/ is relative, and
# must name a file that is there.
class ReadmeTest < Minitest::Test
  TREE = "https://github.com/ryanseys/zr/blob/v#{Zr::VERSION}/".freeze
  LINK = /\]\(([^)\s]+)\)/

  def test_the_readme_has_only_absolute_links
    relative = File.read(File.join(ROOT, "README.md")).scan(LINK).flatten.grep_v(/\A(https?:|#)/)
    assert_empty relative, "README.md: make these links absolute (#{TREE}...)"
  end

  def test_each_link_into_the_tree_names_a_file_of_this_version
    links = File.read(File.join(ROOT, "README.md")).scan(LINK).flatten.select { |url| url.include?("github.com/ryanseys/zr/blob/") }
    refute_empty links
    links.each do |url|
      assert url.start_with?(TREE), "#{url}: link to #{TREE}"
      path = url.delete_prefix(TREE).sub(/#.*\z/, "")
      assert File.exist?(File.join(ROOT, path)), "#{url}: no #{path}"
    end
  end

  def test_each_relative_link_in_the_docs_names_a_file
    missing = Dir[File.join(ROOT, "docs/**/*.md")].flat_map do |doc|
      File.read(doc).scan(LINK).flatten.grep_v(/\A(https?:|mailto:|#|<)/).filter_map do |link|
        path = File.expand_path(link.sub(/#.*\z/, ""), File.dirname(doc))
        "#{doc.delete_prefix("#{ROOT}/")}: #{link}" unless File.exist?(path)
      end
    end
    assert_empty missing
  end
end
