# frozen_string_literal: true

# `rake affected` runs only the specs that a change can affect. Use it
# after an edit, before you run the full tier. It reads the diff against
# `main` (or `BASE=`), finds the specs for each changed file, and runs
# them through `rake test`. It is for local work; CI runs all tests.
#
# How a changed file maps to specs:
# - A spec file maps to itself.
# - A file under `runtime/core` maps to the spec directory of its class,
#   and to each spec whose program contains the class name. (A change to
#   String can affect a Hash spec that uses String keys.)
# - A vendored library or an extension maps to its stdlib directory, and
#   to each spec that requires it by name.
# - A change to the compiler (and its pinned gems), the kernel or the
#   test support maps to all specs.

module Affected
  ROOT = File.expand_path("..", __dir__)
  SPEC = File.join(ROOT, "test/spec")
  # Core files that also affect the language specs: every program makes
  # objects, calls methods and raises exceptions.
  LANGUAGE = %w[object kernel module class proc binding exception comparable].freeze

  module_function

  # The changed files, relative to the root, against `base`.
  def changed(base)
    tracked = `git -C #{ROOT} diff --name-only #{base}`.lines(chomp: true)
    untracked = `git -C #{ROOT} ls-files --others --exclude-standard`.lines(chomp: true)
    (tracked + untracked).uniq
  end

  # Returns the spec paths that `file` affects, or :all.
  def reached(file)
    case file
    when %r{\Atest/spec/.*_test\.rb\z} then [file]
    when %r{\Atest/spec/} then [File.dirname(file)]
    when %r{\Alib/zr/}, %r{\Art/kernel/}, %r{\Atest/(support|test_helper|spec_helper)}, "Rakefile", %r{\Arakelib/} then :all
    when %r{\Art/core/([^/]+?)(?:/.*)?\.rb\z} then core($1)
    when %r{\Art/ext/([^/.]+)}, %r{\Avendor/lib/([^/.]+)} then library($1)
    when "Gemfile.lock", "zr.gemspec" then :all
    else []
    end
  end

  def core(name)
    own = Dir[File.join(SPEC, "core", name)]
    named = specs_naming(name.split("_").map(&:capitalize).join)
    language = LANGUAGE.include?(name) ? [File.join(SPEC, "lang")] : []
    (own + named + language).uniq
  end

  def library(name)
    own = Dir[File.join(SPEC, "stdlib", name)]
    (own + specs_matching(/require ["']#{Regexp.escape(name)}["']/)).uniq
  end

  # Every spec file whose programs contain the word `constant`.
  def specs_naming(constant) = specs_matching(/\b#{Regexp.escape(constant)}\b/)

  def specs_matching(pattern)
    Dir[File.join(SPEC, "**/*_test.rb")].select { |path| File.read(path).match?(pattern) }
  end

  # The spec paths to run for `files`, or :all.
  def plan(files)
    reached = files.map { |file| reached(file) }
    return :all if reached.include?(:all)

    reached.flatten.uniq.sort
  end
end

desc "Run the specs a change can reach: rake affected (BASE=main)"
task :affected do
  base = ENV.fetch("BASE", "main")
  files = Affected.changed(base)
  plan = Affected.plan(files)
  if plan == :all
    puts "the change reaches everything (#{files.size} file(s) against #{base}); run rake test"
  elsif plan.empty?
    puts "no spec reaches the #{files.size} changed file(s) against #{base}"
  else
    rel = plan.map { |path| path.delete_prefix("#{Affected::ROOT}/") }
    puts "#{files.size} file(s) changed against #{base}; running #{rel.size} spec path(s)"
    sh(RbConfig.ruby, "-S", "rake", "test", *rel)
  end
end
