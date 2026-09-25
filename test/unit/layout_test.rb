# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/version"

# The layout rules of the repository. The tools live in tool/, and the
# Rakefile keeps only the standard entry points. Each version fact has
# one source, lib/zr/version.rb, and every other copy must agree with it.
class LayoutTest < Minitest::Test
  # Enough for the standard tasks and their comments. A tool with its own
  # logic belongs in tool/.
  RAKEFILE_LINES = 100

  def read(rel) = File.read(File.join(ROOT, rel))

  def test_no_rakelib_directory
    refute File.exist?(File.join(ROOT, "rakelib")), "a tool is a zr-dev command in tool/, not a rake task in rakelib/"
  end

  def test_the_rakefile_stays_short
    lines = read("Rakefile").lines.size

    assert_operator lines, :<=, RAKEFILE_LINES, "the Rakefile has #{lines} lines; move the logic to tool/"
  end

  def test_ruby_version_agrees_with_version_rb
    assert_equal Zr::RUBY, read(".ruby-version").strip
  end

  def test_env_rb_agrees_with_version_rb
    env = read("runtime/core/env.rb")

    assert_includes env, %(RUBY_VERSION = "#{Zr::RUBY}")
    assert_includes env, %(RUBY_RELEASE_DATE = "#{Zr::RUBY_RELEASE_DATE}")
    assert_includes env, %(RUBY_REVISION = "#{Zr::RUBY_REVISION}")
  end

  def test_ci_names_the_same_ruby
    ci = Dir[File.join(ROOT, ".github/workflows/*.yml")].sum("") { |path| File.read(path) }

    # A job without a checkout names the version itself.
    assert_empty ci.scan(/ruby-version: (\S+)/).flatten - [".ruby-version", %("#{Zr::RUBY}")], "the ruby setup-ruby installs"
    assert_equal [Zr::RUBY], ci.scan(/\bruby:(\d+\.\d+\.\d+)/).flatten.uniq, "the container's ruby"
    assert_equal [Zr::RUBY_REVISION], ci.scan(%r{ruby/ruby/(\h{40})/}).flatten.uniq, "the CRuby revision CI reads"
  end

  def test_the_tools_doc_names_every_command
    require_relative "../../tool/commands"
    doc = read("docs/reference/tools.md")

    Zr::Dev::COMMANDS.each_key { |word| assert_includes doc, "zr-dev #{word}", "docs/reference/tools.md" }
  end
end
