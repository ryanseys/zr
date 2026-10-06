# frozen_string_literal: true

require "fileutils"
require "json"
require "rbconfig"
require_relative "lib/zr/dev"
require_relative "lib/zr/dev/suite"

module Zr
  module Dev
    # Runs ruby/spec, the specs of ruby 4.0.7's own checkout, under ruby
    # and in zr binaries, and compares each example.
    #
    #   zr-dev rubyspec language                    one area
    #   zr-dev rubyspec core                        each directory of core/
    #   zr-dev rubyspec core/array -f pop_spec.rb   the files that match
    #   zr-dev rubyspec --all [--shard 2/4]         every area, or a share
    #   zr-dev rubyspec core/array --update-tags    write the tags again
    #
    # An area's spec files go into binaries of 20 files each, built one
    # at a time. A chunk that does not build is split in two until the
    # file that does not build is alone. Each file then runs in its own
    # process, under ruby and in its binary, with a time limit. ruby's
    # results are kept by the file's digest (`log/rubyspec/ruby/`), so
    # ruby runs each file once.
    #
    # The examples that zr fails on purpose are tags, in mspec's own form,
    # in `test/rubyspec/tags/<path>_tags.txt`:
    #
    #   fails:<describe> <it>     zr fails the example
    #   fails(why):<describe> <it>  zr differs on purpose, for the reason given
    #   hangs:<describe> <it>     zr stops or loops in it; its run skips it
    #   fails(build):             the file does not build
    #   fails(load):              the file raises as it loads
    #
    # A run writes `log/rubyspec/results/<area>.json` and the summary
    # `test/rubyspec/summary.tsv`. `--update-tags` writes the tags of each
    # file that ran from its results. The ratchet
    # (test/unit/rubyspec_ratchet_test.rb) reads the results and the tags.
    class RubySpec < Command
      summary "Run ruby/spec in ruby and in zr binaries, and compare each example"
      usage "<area>... | --all [-f PATTERN] [-j JOBS] [--shard I/N] [--update-tags] [--keep]"
      host_ruby!

      # Seconds for one spec file. A file that does not end in this time
      # is a gap: zr loops where ruby raises, or is much slower.
      LIMIT = 120

      # The areas that test what only CRuby has, and why.
      CRUBY_ONLY = {
        "optional/capi" => "ruby's C API, which a compiled program does not have",
        "security" => "CVE checks of CRuby's C code"
      }.freeze

      # The order of `--all`: the language first, then core, then the library.
      ORDER = %w[language core library].freeze

      OUT = Dev.path("log/rubyspec")
      TAGS = Dev.path("test/rubyspec/tags")
      SUMMARY = Dev.path("test/rubyspec/summary.tsv")

      # The form of the program and of ruby's kept results.
      VERSION = 1

      def defaults
        @filter = nil
        @jobs = 2
        @keep = false
        @all = false
        @shard = nil
        @update = false
      end

      def options(o)
        o.on("-f PATTERN", "only the spec files whose path matches") { |v| @filter = Regexp.new(v) }
        o.on("-j JOBS", Integer, "files to run at once (default 2)") { |v| @jobs = v }
        o.on("--all", "every area, in the order language, core, library") { @all = true }
        o.on("--shard I/N", "with --all: the I-th of N equal shares of the areas") { |v| @shard = v.split("/").map(&:to_i) }
        o.on("--update-tags", "write the tags of each file that ran") { @update = true }
        o.on("--keep", "keep the binaries") { @keep = true }
      end

      def run(argv)
        Dev.pinned!(name)
        fail!("give an area (language, core, core/array) or --all") if argv.empty? && !@all
        root = checkout!
        areas = @all ? ORDER.flat_map { |a| areas_of(root, a) } : argv.flat_map { |a| areas_of(root, a) }
        areas = shard(areas) if @shard
        Suite.lock! do
          Suite.pin!
          gaps = areas.sum do |area|
            Area.new(root, area, filter: @filter, jobs: @jobs, keep: @keep, update: @update).run
          end
          Suite.write_summary(OUT, SUMMARY)
          puts "#{gaps} gap(s) in #{areas.size} area(s); see #{Dev.rel(OUT)} and #{Dev.rel(SUMMARY)}"
        end
        true
      end

      # The spec directory of the CRuby checkout at RUBY_REVISION.
      def checkout!
        src = Dev.ruby_src
        head = Dev.git("rev-parse", "HEAD", dir: src, err: $stderr).to_s.strip
        fail!("#{src} is at #{head[0, 10]}, not ruby #{RUBY} (#{RUBY_REVISION[0, 10]})") unless head == RUBY_REVISION
        File.join(src, "spec")
      end

      # `core` and `library` are each of their directories; any other word
      # is one area.
      def areas_of(root, word)
        word = word.delete_suffix("/")
        fail!("#{word} is CRuby's alone: #{CRUBY_ONLY[word]}") if CRUBY_ONLY.key?(word)
        dir = File.join(root, "ruby", word)
        fail!("no area #{word} in #{root}/ruby") unless File.directory?(dir)
        return [word] if Dir.glob("#{dir}/*_spec.rb").any? || !%w[core library optional].include?(word)

        Dir.children(dir).sort.filter_map do |d|
          area = "#{word}/#{d}"
          area if File.directory?(File.join(dir, d)) && !CRUBY_ONLY.key?(area)
        end
      end

      def shard(areas)
        index, count = @shard
        fail!("--shard takes I/N with 1 <= I <= N") unless count.to_i.positive? && index.to_i.between?(1, count)
        areas.select.with_index { |_, i| i % count == index - 1 }
      end

      # The tags of one spec file, as { name => kind }: an example's name
      # is its describe and its sentence, and the file's own tag is under
      # "" (`build` or `load`).
      def self.tags(rel)
        path = tags_path(rel)
        return {} unless File.file?(path)

        File.readlines(path, chomp: true).each_with_object({}) do |line, tags|
          case line
          when /\Afails\((build|load)\):\z/ then tags[""] = ::Regexp.last_match(1)
          when /\A(fails|hangs)(?:\([^)]*\))?:(.+)\z/ then tags[::Regexp.last_match(2)] = ::Regexp.last_match(1)
          end
        end
      end

      # The reason of each tag that gives one (`fails(why):`), by name: a
      # rewrite of the tags keeps it. A file's own tag has no name.
      def self.reasons(rel)
        path = tags_path(rel)
        return {} unless File.file?(path)

        File.readlines(path, chomp: true).each_with_object({}) do |line, reasons|
          reasons[::Regexp.last_match(2)] = ::Regexp.last_match(1) if line =~ /\A(?:fails|hangs)\(([^)]+)\):(.+)\z/
        end
      end

      # `core/array/pop_spec.rb` has its tags in `core/array/pop_tags.txt`,
      # as mspec looks for them.
      def self.tags_path(rel) = File.join(TAGS, rel.sub(/_spec\.rb\z/, "_tags.txt"))

      # One area of ruby/spec (`Suite::Area` runs it).
      class Area < Suite::Area
        def initialize(spec, area, filter:, **)
          @spec = spec
          files = Dir.glob(File.join(spec, "ruby", area, "**", "*_spec.rb")).sort
          files.select! { |f| f.match?(filter) } if filter
          super(out: OUT, root: File.join(spec, "ruby"), area: area, files: files, filtered: !filter.nil?, **)
        end

        def version = VERSION
        def limit = LIMIT
        def program(files) = RubySpec.program(@spec, files)
        def arguments(file, zr:, skip: []) = [file]
        def read(out) = RubySpec.read(out)
        def tags(rel) = RubySpec.tags(rel)

        # zr's run skips the examples tagged `hangs`; ruby runs them all.
        # mspec's ruby_exe runs the interpreter of the run.
        def env(dir, zr:)
          super.merge("RUBY_EXE" => zr ? Suite.zr : RbConfig.ruby, "SPEC_TEMP_DIR" => File.join(dir, "tmp"),
                      "SPEC_SKIP_HANGS" => ("1" if zr))
        end

        def write_tags(rel, result)
          reasons = RubySpec.reasons(rel)
          lines = tags_from(result, tags(rel)).map do |name, kind|
            next "fails(#{kind}):" if name.empty?

            reasons[name] ? "#{kind}(#{reasons[name]}):#{name}" : "#{kind}:#{name}"
          end
          path = RubySpec.tags_path(rel)
          return FileUtils.rm_f(path) if lines.empty?

          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, lines.join("\n") << "\n")
        end
      end

      # The program of `files`: mspec, the spec helper, a report of each
      # example, then each file behind a test of the arguments, so one
      # binary runs any one of its files. A file that raises as it loads is
      # reported, and the run goes on.
      def self.program(root, files)
        mspec = File.join(root, "mspec/lib")
        tags = "#{TAGS}/"
        lines = [
          "# frozen_string_literal: false",
          'ENV["MSPEC_RUNNER"] = "1"',
          "$LOAD_PATH.unshift(#{mspec.inspect})",
          'require "mspec"',
          'require "mspec/utils/script"',
          "require #{File.join(root, "ruby/spec_helper.rb").inspect}",
          REPORT,
          "ZrSpecReport.new.register",
          'if ENV["SPEC_SKIP_HANGS"]',
          "  MSpec.register_tags_patterns([[%r{\\A#{Regexp.escape("#{root}/ruby/")}}, #{tags.inspect}], [/_spec\\.rb\\z/, \"_tags.txt\"]])",
          '  TagFilter.new(:exclude, "hangs").register',
          "end",
          "MSpec.register_files ARGV",
          "MSpec.actions :start",
          "MSpec.setup_env"
        ]
        files.each do |f|
          lines << "if ARGV.include?(#{f.inspect})"
          lines << "  MSpec.store :file, #{f.inspect}"
          lines << "  MSpec.actions :load"
          lines << "  begin"
          lines << "    require #{f.inspect}"
          lines << "  rescue Exception => e"
          lines << "    STDOUT.puts \"ZRSPEC\\tload\\t\#{e.class}: \#{e.message.lines.first.to_s.chomp}\""
          lines << "  end"
          lines << "  MSpec.actions :unload"
          lines << "end"
        end
        lines << "MSpec.actions :finish"
        lines << 'STDOUT.puts "ZRSPEC\tend"'
        lines << "exit MSpec.exit_code"
        lines.join("\n") << "\n"
      end

      # The mspec action that prints a line for each example: its status,
      # its name and the first line of its failure.
      REPORT = <<~'RUBY'
        class ZrSpecReport
          def register
            MSpec.register :exception, self
            MSpec.register :after, self
          end

          def exception(state)
            @failure ||= state
          end

          def after(state)
            failure = @failure
            @failure = nil
            status = failure.nil? ? "pass" : (failure.failure? ? "fail" : "error")
            message = failure ? failure.message.to_s.lines.first.to_s.chomp[0, 200] : ""
            STDOUT.puts ["ZRSPEC", status, state.description.tr("\t\n", "  "), message.tr("\t", " ")].join("\t")
            STDOUT.flush
          end
        end
      RUBY

      # The examples of a report, in the order they ran.
      def self.read(out)
        examples = {}
        load = nil
        ended = false
        out.each_line do |line|
          kind, status, name, message = line.chomp.force_encoding(Encoding::UTF_8).scrub.split("\t", 4)
          next unless kind == "ZRSPEC"

          case status
          when "end" then ended = true
          when "load" then load = name
          else examples[name] = [status, message.to_s.empty? ? nil : message].compact
          end
        end
        { examples: examples, load: load, ended: ended }
      end
    end
  end
end
