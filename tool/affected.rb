# frozen_string_literal: true

require_relative "lib/zr/dev"
require_relative "../lib/zr/runtime_sources"

module Zr
  module Dev
    # `zr-dev affected` runs only the specs that a change can affect. Use
    # it after an edit, before you run the full tier. It reads the diff
    # against `main` (or `--base`), finds the specs for each changed file,
    # and runs them with bin/test. It is for local work; CI runs all
    # tests.
    #
    # How a changed file maps to specs:
    # - A spec or unit test file maps to itself.
    # - A file under `runtime/core` maps to the spec directory of its
    #   class, and to each spec whose program contains the class name. (A
    #   change to String can affect a Hash spec that uses String keys.)
    # - A vendored library or an extension maps to its stdlib directory,
    #   and to each spec that requires it by name.
    # - A file of an OS layer of the core maps as its own name does
    #   (runtime/core/os/darwin/errno.rb as errno).
    # - A change to a compiler file that a program's code can depend on
    #   (`RuntimeSources#compiler_files`), the kernel or the test support
    #   maps to all specs. A change to another file under lib/zr (the CLI,
    #   the caches, the linkers) maps to the unit tests that load it
    #   (`LoadGraph`), and to test/e2e when exe/zr loads it. A change to a
    #   tool maps to the unit tests, which test the tools; no spec runs one.
    class Affected < Command
      summary "Run the specs that a change can reach"
      usage "[--base REVISION] [--dry-run]"

      SPEC = Dev.path("test/spec")
      # Core files that also affect the language specs: every program
      # makes objects, calls methods and raises exceptions.
      LANGUAGE = %w[kernel module proc binding exception comparable].freeze

      def options(o)
        o.on("--base REVISION", "the revision to diff against (default: main)") { |v| @base = v }
        o.on("--dry-run", "print the spec paths; run nothing") { @dry = true }
      end

      # The files changed against `base`, and the test paths that they
      # reach (`:all` for everything). `bin/test --changed` reads this.
      def self.test_paths(base = "main")
        tool = new("affected")
        files = tool.changed(base)
        [files, tool.plan(files)]
      end

      def run(_argv)
        base = @base || "main"
        files, plan = Affected.test_paths(base)
        if plan == :all
          puts "the change reaches everything (#{files.size} file(s) against #{base}); run bin/test"
        elsif plan.empty?
          puts "no spec reaches the #{files.size} changed file(s) against #{base}"
        else
          rel = plan.map { |path| Dev.rel(path) }
          puts "#{files.size} file(s) changed against #{base}; running #{rel.size} spec path(s)"
          return rel.each { |path| puts "  #{path}" } if @dry

          system(Dev.ruby, Dev.path("bin/test"), *rel)
        end
      end

      # The changed files, relative to the root, against `base`.
      def changed(base)
        tracked = IO.popen(["git", "-C", ROOT, "diff", "--name-only", base], &:read).lines(chomp: true)
        fail!("git diff against #{base} failed") unless $?.success?
        untracked = IO.popen(["git", "-C", ROOT, "ls-files", "--others", "--exclude-standard"], &:read).lines(chomp: true)
        (tracked + untracked).uniq
      end

      # Returns the spec paths that `file` affects, or :all.
      def reached(file)
        case file
        when %r{\Atest/(spec|unit)/.*_test\.rb\z} then File.exist?(File.join(ROOT, file)) ? [file] : []
        when %r{\Atest/spec/} then [File.dirname(file)]
        when %r{\Alib/zr/.*\.rb\z} then lib(file)
        when %r{\Aruntime/kernel/}, %r{\Aruntime/(ext/os|lib)/}, %r{\Atest/(support|test_helper|spec_helper)}, "Rakefile" then :all
        when %r{\Atool/} then [File.join(ROOT, "test/unit")]
        when %r{\Aruntime/core/os/[^/]+/([^/]+)\.rb\z} then core($1)
        when %r{\Aruntime/core/([^/]+?)(?:/.*)?\.rb\z} then core($1)
        when %r{\Aruntime/ext/([^/.]+)}, %r{\Avendor/ruby/lib/ruby/[\d.]+/([^/.]+)} then library($1)
        when %r{\Avendor/ruby/lib/ruby/gems/[\d.]+/gems/(.+)-[\d.]+/} then library($1.tr("-", "/"))
        when "Gemfile.lock", "zr.gemspec" then :all
        else []
        end
      end

      # The test paths that a change to `file` under lib/zr reaches.
      def lib(file)
        path = File.join(ROOT, file)
        return :all if !File.exist?(path) || builds?(path)

        graph = LoadGraph.new
        units = Dir[File.join(ROOT, "test/unit/**/*_test.rb")].select { |test| graph.reaches?(test, path) }
        exe = graph.closure(File.join(ROOT, "exe/zr")).include?(path)
        units |= Dir[File.join(ROOT, "test/unit/**/*_test.rb")].select { |test| File.read(test).include?("exe/zr") } if exe
        (units.map { |test| Dev.rel(test) } + (exe ? ["test/e2e"] : [])).sort
      end

      # Whether `path` can change what a build writes: a compiler file that
      # a program's code depends on, or a linker. The command line only
      # reads options, so a change to it reaches the tests that run it.
      def builds?(path)
        RuntimeSources.for(Target.default).compiler_files.include?(path) ||
          (RuntimeSources::LINK_ONLY - [File.join(ROOT, "lib/zr/cli.rb")]).include?(path)
      end

      # The files that each file loads, read from its literal `require`
      # and `require_relative` calls, wherever they are (a require in a
      # method body counts). A require that names a computed path is not
      # seen, so the graph can miss an edge, never add one.
      class LoadGraph
        REQUIRE = /^\s*(require_relative|require)\(?\s*["']([^"'#]+)["']/
        ROOTS = %w[lib test tool].map { |dir| Dev.path(dir) }.freeze

        def initialize
          @edges = {}
          @closures = {}
        end

        def reaches?(from, path) = closure(from).include?(path)

        def closure(from)
          @closures[from] ||= begin
            seen = { from => true }
            todo = [from]
            until todo.empty?
              edges(todo.pop).each do |to|
                next if seen[to]

                seen[to] = true
                todo << to
              end
            end
            seen.keys
          end
        end

        def edges(file)
          @edges[file] ||= File.read(file).scan(REQUIRE).filter_map do |kind, feature|
            kind == "require_relative" ? existing(File.expand_path(feature, File.dirname(file))) : found(feature)
          end
        rescue SystemCallError
          @edges[file] = []
        end

        private

        def found(feature) = ROOTS.lazy.filter_map { |root| existing(File.join(root, feature)) }.first

        def existing(path)
          [path, "#{path}.rb"].find { |candidate| File.file?(candidate) }
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
  end
end
