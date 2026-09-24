# frozen_string_literal: true

# `rake affected` runs the specs a change can reach, and nothing else:
# what to run after an edit, before the whole tier. It reads the diff
# against `main` (or `BASE=`), names a spec for each changed file, and
# runs those through `rake test`. It is for the desk; CI runs everything.
#
# The map is honest about what it knows. A spec file names itself, and
# an edit under `rt/core` names the spec directory of that class, plus
# every spec whose program names the class -- an edit to String reaches
# a spec of Hash that keys on Strings, and the class's own name is the
# one thing every such program spells. A vendored library or an
# extension names its stdlib directory, and every spec that requires
# it by name. An edit to the compiler (its pinned gems too), the kernel
# or the checks' own support reaches everything, and that is what it
# runs.

module Affected
  ROOT = File.expand_path("..", __dir__)
  SPEC = File.join(ROOT, "test/spec")
  # Core files whose semantics reach the language specs as much as
  # their own: every program makes objects, calls methods and raises.
  LANGUAGE = %w[object kernel module class proc binding exception comparable].freeze

  module_function

  # The changed files, relative to the root, against `base`.
  def changed(base)
    tracked = `git -C #{ROOT} diff --name-only #{base}`.lines(chomp: true)
    untracked = `git -C #{ROOT} ls-files --others --exclude-standard`.lines(chomp: true)
    (tracked + untracked).uniq
  end

  # The spec paths `file` reaches, or :all where it reaches everything.
  def reached(file)
    case file
    when %r{\Atest/spec/.*_test\.rb\z} then [file]
    when %r{\Atest/spec/} then [File.dirname(file)]
    when %r{\Alib/ze0/}, %r{\Art/kernel/}, %r{\Atest/(support|test_helper|spec_helper)}, "Rakefile", %r{\Arakelib/} then :all
    when %r{\Art/core/([^/]+?)(?:/.*)?\.rb\z} then core($1)
    when %r{\Art/ext/([^/.]+)}, %r{\Avendor/lib/([^/.]+)} then library($1)
    when "Gemfile.lock", "ze0.gemspec" then :all
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

  # Every spec file whose programs spell `constant`.
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
