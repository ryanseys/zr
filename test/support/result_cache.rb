# frozen_string_literal: true

require "digest"
require_relative "../../lib/zr/cache/store"

module Zr
  module Test
    # The program tests that passed, so that a later run with the same
    # inputs does not build and run them again (or walk them, with
    # `ZR_TEST_HOST=1`). An entry is a key in the store (kind `result`)
    # that holds no value: its key is a digest of everything a run of the
    # test reads, so any change to them misses.
    #
    # The key holds the test's program and the files beside it, its
    # baseline line, the ruby, each `ZR_*` and `RUBY*` variable but the
    # ones that only pick or report tests (`SELECTION`), and the state of
    # the checkout but the paths that no program test reads (`unread?`):
    # the blob of each file that git tracks, and the bytes of each file
    # that differs from it or that git does not track yet. So a change
    # anywhere that a run reads (the compiler, the kernel, the core, the
    # walker in tool/, the test support, the baselines, Gemfile.lock)
    # misses, and a change to the docs or to a unit test does not. The
    # variables keep compiled, host, other-target and stressed runs apart.
    # A copy that is no git checkout stamps lib, vendor, gems, tool and
    # test by size and mtime. `ZR_TEST_FRESH=1` (`zr-dev test --no-cache`)
    # runs every test.
    class ResultCache
      ROOT = File.expand_path("../..", __dir__)
      TREES = %w[lib vendor gems tool test].freeze
      # The variables that pick or report tests, and so leave a result as
      # it is.
      SELECTION = %w[ZR_PROGRAMS ZR_TEST_FRESH ZR_TEST_FAIL_FAST ZR_TEST_TMP ZR_TEST_BY_HAND ZR_TOP_GEMS].freeze
      # The paths that no program test reads: the programs themselves (each
      # test's own files are in its key), the docs, the other test tiers,
      # the benchmarks, the type signatures and the repository's own files.
      UNREAD = %w[test/programs test/unit test/ext docs benchmark sig licenses .github
                  Steepfile .rubocop.yml .rubocop_todo.yml .git-blame-ignore-revs].freeze

      # Whether a change to `rel` (a path below the root) leaves each pass:
      # a path of UNREAD, or a Markdown file at the top (README.md,
      # CHANGELOG.md).
      def self.unread?(rel)
        UNREAD.any? { |path| rel == path || rel.start_with?("#{path}/") } || (!rel.include?("/") && rel.end_with?(".md"))
      end

      def self.enabled? = ENV["ZR_TEST_FRESH"] != "1"

      # `root` is the checkout whose state the key holds.
      def initialize(root: ROOT)
        @root = root
        @tree = tree_digest
      end

      # The digest of the checkout but the paths that no program test reads.
      attr_reader :tree

      # `[[name, value]]` of each variable that can change a run.
      def self.variables
        ENV.select { |name, _| name.start_with?("ZR_", "RUBY") && !SELECTION.include?(name) }.sort
      end

      def passed?(test, baseline) = !Cache::Store.read(:result, key(test, baseline)).nil?

      # Records the pass, unless a source of zr changed while the run went
      # on: then the pass may be of the old code.
      def pass!(test, baseline)
        Cache::Store.write(:result, key(test, baseline), "")
      rescue SourceChanged
        nil
      end

      private

      def key(test, baseline)
        beside = Dir.glob("#{test.path}.*").sort.reject { |path| File.directory?(path) }
        files = test.files ? Dir.glob("**/*", File::FNM_DOTMATCH, base: test.files).sort : []
        Cache::Store.key(
          @tree, RUBY_DESCRIPTION, self.class.variables.inspect,
          test.rel, test.source, baseline.to_s,
          *beside.flat_map { |path| [File.basename(path), File.binread(path)] },
          *files.flat_map { |name| [name, file_bytes(File.join(test.files, name))] }
        )
      end

      def file_bytes(path) = File.file?(path) ? File.binread(path) : ""

      def tree_digest
        index = git("ls-files", "-s")
        return stamp_digest if index.nil?

        digest = Digest::SHA256.new
        index.each_line { |line| digest << line unless self.class.unread?(line.chomp.split("\t", 2).last) }
        changed = git("ls-files", "-m", "-o", "--exclude-standard").to_s
        changed.lines(chomp: true).uniq.sort.each do |rel|
          next if self.class.unread?(rel)

          digest << rel << "\0" << file_bytes(File.join(@root, rel)) << "\0"
        end
        digest.hexdigest
      end

      def stamp_digest
        digest = Digest::SHA256.new
        TREES.flat_map { |dir| Dir.glob("#{@root}/#{dir}/**/*") }.sort.each do |path|
          next if !File.file?(path) || self.class.unread?(path.delete_prefix("#{@root}/"))

          stat = File.stat(path)
          digest << path << "\0" << stat.size.to_s << "\0" << stat.mtime.to_r.to_s << "\0"
        end
        digest.hexdigest
      end

      # The output of git in the root, or nil when it fails.
      def git(*args)
        out = IO.popen(["git", "-C", @root, *args], err: File::NULL, &:read)
        out if $?.success?
      rescue SystemCallError
        nil
      end
    end
  end
end
