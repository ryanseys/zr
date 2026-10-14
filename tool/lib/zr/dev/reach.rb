# frozen_string_literal: true

require_relative "../dev"
require_relative "../../../../lib/zr/runtime_sources"

module Zr
  module Dev
    # The tests that a change can reach, which `zr-dev test --changed` runs.
    # It reads the diff against a base revision and maps each changed file
    # to test paths: unit test files, and program tests or their
    # directories below test/programs.
    #
    # How a changed file maps to tests:
    # - A unit test file maps to itself, and a program test's program or
    #   one of the files beside it maps to the program. A file below a
    #   shared tree of test/fixtures/programs maps to each program that
    #   links the tree.
    # - A file under `lib/zr/runtime/core` maps to the program tests of its
    #   class, and to each program test that contains the class name. (A
    #   change to String can affect a Hash test that uses String keys.)
    # - A vendored library or an extension maps to its stdlib directory,
    #   and to each program test that requires it by name.
    # - A file of an OS layer of the core maps as its own name does
    #   (lib/zr/runtime/core/os/darwin/errno.rb as errno).
    # - A change to a compiler file that a program's code can depend on
    #   (`RuntimeSources#compiler_files`), the kernel or the test support
    #   maps to all tests. A change to another file under lib/zr (the CLI,
    #   the caches, the linkers) maps to the unit tests that load it
    #   (`LoadGraph`), and to test/programs/cli when exe/zr loads it. A
    #   change to a tool maps to the unit tests, which test the tools.
    module Reach
      PROGRAMS = Dev.path("test/programs")
      # Core files that also affect the language tests: every program
      # makes objects, calls methods and raises exceptions.
      LANGUAGE = %w[kernel module proc binding exception comparable].freeze

      module_function

      # The changed files, relative to the root, against `base`, with the
      # files that git does not track yet.
      def files(base)
        tracked = Dev.git("diff", "--name-only", base, err: $stderr) or Dev.fail!("git diff against #{base} failed")
        untracked = Dev.git("ls-files", "--others", "--exclude-standard", err: $stderr).to_s
        (tracked.lines(chomp: true) + untracked.lines(chomp: true)).uniq
      end

      # The test paths that `files` reach, below the root, or :all.
      def tests(files)
        reached = files.map { |file| reached(file) }
        return :all if reached.include?(:all)

        reached.flatten.uniq.sort
      end

      # The test paths that `file` reaches, or :all.
      def reached(file)
        case file
        when %r{\Atest/unit/.*_test\.rb\z} then File.exist?(File.join(ROOT, file)) ? [file] : []
        when %r{\A(test/programs/.+?\.rb)(?:\.|\z)} then File.exist?(File.join(ROOT, $1)) ? [$1] : []
        when %r{\Atest/fixtures/programs/([^/]+)/} then linking($1)
        when %r{\Alib/zr/runtime/kernel/}, %r{\Alib/zr/runtime/(ext/os|lib)/}, %r{\Atest/(support|test_helper)}, "Rakefile" then :all
        when %r{\Alib/zr/runtime/core/os/[^/]+/([^/]+)\.rb\z} then core($1)
        when %r{\Alib/zr/runtime/core/([^/]+?)(?:/.*)?\.rb\z} then core($1)
        when %r{\Alib/zr/runtime/ext/([^/.]+)}, %r{\Avendor/ruby/lib/ruby/[\d.]+/([^/.]+)} then library($1)
        when %r{\Alib/zr/.*\.rb\z} then lib(file)
        when %r{\Atool/} then ["test/unit"]
        when %r{\Avendor/ruby/lib/ruby/gems/[\d.]+/gems/(.+)-[\d.]+/} then library($1.tr("-", "/"))
        when "Gemfile.lock", "zr.gemspec" then :all
        else []
        end
      end

      # The programs whose files are a link to the shared tree `name` below
      # test/fixtures/programs.
      def linking(name)
        shared = File.join(ROOT, "test/fixtures/programs", name)
        Dir[File.join(PROGRAMS, "**/*.rb.files")].filter_map do |dir|
          Dev.rel(dir.delete_suffix(".files")) if File.symlink?(dir) && File.expand_path(File.readlink(dir), File.dirname(dir)) == shared
        end.sort
      end

      # The test paths that a change to `file` under lib/zr reaches.
      def lib(file)
        path = File.join(ROOT, file)
        return :all if !File.exist?(path) || builds?(path)

        graph = LoadGraph.new
        units = Dir[File.join(ROOT, "test/unit/**/*_test.rb")].select { |test| graph.reaches?(test, path) }
        exe = graph.closure(File.join(ROOT, "exe/zr")).include?(path)
        units |= Dir[File.join(ROOT, "test/unit/**/*_test.rb")].select { |test| File.read(test).include?("exe/zr") } if exe
        (units.map { |test| Dev.rel(test) } + (exe ? ["test/programs/cli"] : [])).sort
      end

      # Whether `path` can change what a build writes: a compiler file that
      # a program's code depends on, or a linker. The command line only
      # reads options, so a change to it reaches the tests that run it.
      def builds?(path)
        RuntimeSources.for(Target.default).compiler_files.include?(path) ||
          (RuntimeSources::LINK_ONLY.include?(path) && !command_line?(path))
      end

      # Whether `path` is a file of the command line: lib/zr/cli.rb, or a
      # file under lib/zr/cli/.
      def command_line?(path) = path == File.join(ROOT, "lib/zr/cli.rb") || path.start_with?(File.join(ROOT, "lib/zr/cli/"))

      def core(name)
        own = Dir[File.join(PROGRAMS, "core", name)]
        named = programs_naming(name.split("_").map(&:capitalize).join)
        language = LANGUAGE.include?(name) ? [File.join(PROGRAMS, "lang")] : []
        (own + named + language).uniq.map { |path| Dev.rel(path) }
      end

      def library(name)
        own = Dir[File.join(PROGRAMS, "stdlib", name)]
        (own + programs_matching(/require ["']#{Regexp.escape(name)}["']/)).uniq.map { |path| Dev.rel(path) }
      end

      # Every program test that contains the word `constant`.
      def programs_naming(constant) = programs_matching(/\b#{Regexp.escape(constant)}\b/)

      # A program can be in another encoding than UTF-8 (a magic comment says
      # so), and the patterns are ASCII, so each file is read as bytes.
      def programs_matching(pattern)
        Dir[File.join(PROGRAMS, "**/*.rb")].select { |path| !path.include?(".rb.files/") && File.binread(path).match?(pattern) }
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
    end
  end
end
