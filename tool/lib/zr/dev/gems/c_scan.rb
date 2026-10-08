# frozen_string_literal: true

require "json"
require "fileutils"
require "rbconfig"
require "tmpdir"
require_relative "../../../../../lib/zr/ext/c_api"
require_relative "../../../../../lib/zr/library/ports"
require_relative "../../../../../test/support/harness/child"

module Zr
  module Dev
    module Gems
      # What a gem's C extension takes from ruby's C API, found with no gem
      # code: each C or C++ file below the directory of each extension
      # compiles alone, with the host ruby's headers and flags, and the
      # objects that compile give their ruby imports (`Ext::CApi.imports`).
      #
      # extconf.rb does not run, so a file that needs what it finds (an
      # extconf.h with HAVE_ macros, a library's headers) can fail. An
      # empty extconf.h stands in for the real one. A scan with failed
      # files still counts what the others import, and says how many
      # compiled.
      #
      # The imports of each gem version are kept in `dir`, so a gem that
      # many others need compiles once. What the C API lacks is found from
      # them each time (`#missing`), as the C API grows.
      class CScan
        # One gem's scan. `sources` is the number of files it tried,
        # `compiled` the number that compiled, `imports` the ruby names that
        # those import, and `error` the first error of a file that failed.
        Scan = Data.define(:gem, :version, :sources, :compiled, :imports, :error) do
          def self.from_h(hash) = new(**hash.transform_keys(&:to_sym))

          def full_name = "#{gem}-#{version}"

          # Whether every file compiled, so `imports` is the whole set.
          def complete? = sources.positive? && compiled == sources

          # The imports that zr's C API lacks.
          def missing = Ext::CApi.missing(imports)

          # A row of the sweep's .capi.jsonl.
          def to_h = super.merge(missing: missing)
        end

        SOURCES = %w[c cc cpp cxx].freeze
        # The most seconds that one file's compile takes.
        COMPILE_SECONDS = 120
        # cc's memory limit for one file.
        COMPILE_MB = 2048
        # Errors that clang raises for C that older compilers took. The
        # scan wants the calls, not a clean build.
        LENIENT = %w[implicit-function-declaration incompatible-function-pointer-types int-conversion
                     incompatible-pointer-types implicit-int return-type].map { |name| "-Wno-error=#{name}" }.freeze

        attr_reader :dir

        def initialize(dir: File.join(TMP, "capi"))
          @dir = dir
        end

        # The Scan of `subject`'s C extensions, kept or made now.
        def call(subject)
          path = File.join(@dir, "#{subject.full_name}.json")
          return Scan.from_h(JSON.parse(File.read(path))) if File.file?(path)

          scan = scan(subject)
          FileUtils.mkdir_p(@dir)
          File.write("#{path}.tmp", JSON.generate(scan.to_h.except(:missing)))
          File.rename("#{path}.tmp", path)
          scan
        end

        # The scans of the C extensions among `gems` that zr has no port of.
        # A scan that the tool cannot make (a defect, a file it cannot
        # read) is left out, and `say` gets why.
        def natives(gems, say: nil)
          gems.select { |gem| gem.cext? && !Library::Ports::ALL.key?(gem.name) }.filter_map do |gem|
            call(gem)
          rescue StandardError => e
            say&.call("no C scan of #{gem}: #{e.class}: #{e.message.lines.first&.chomp}")
            nil
          end
        end

        # What the swept gems wait on, from `rows`: pairs of a swept gem's
        # name and its scans. `functions` gives each function that the C
        # API lacks with the swept gems that need it, most first;
        # `extensions` gives each extension gem with the swept gems that
        # need it and its scan, most first.
        Ranking = Data.define(:functions, :extensions)

        def self.rank(rows)
          needers = Hash.new { |hash, function| hash[function] = Set.new }
          extensions = {}
          rows.each do |name, scans|
            scans.each do |scan|
              scan.missing.each { |function| needers[function] << name }
              (extensions[scan.gem] ||= [scan, Set.new]).last << name
            end
          end
          functions = needers.map { |function, users| [function, users.sort] }
          gems = extensions.map { |gem, (scan, users)| [gem, users.sort, scan] }
          Ranking.new(functions.sort_by { |function, users| [-users.size, function] },
                      gems.sort_by { |gem, users, _| [-users.size, gem] })
        end

        # The C and C++ files below each extension's directory.
        def sources(subject)
          subject.extensions.flat_map do |extension|
            base = File.dirname(File.expand_path(extension, subject.root))
            next [] unless base.start_with?(File.join(subject.root, "")) && File.directory?(base)

            Dir.glob("**/*.{#{SOURCES.join(",")}}", base: base).sort.map { |file| File.join(base, file) }
          end.uniq
        end

        private

        def scan(subject)
          files = sources(subject)
          headers = header_dirs(subject)
          Dir.mktmpdir("zr-cscan-") do |work|
            File.write(File.join(work, "extconf.h"), "")
            objects = []
            error = nil
            files.each_with_index do |file, i|
              object = File.join(work, "#{i}.o")
              failure = compile(file, object, work, headers)
              failure ? (error ||= "#{File.basename(file)}: #{failure}") : objects << object
            end
            imports = objects.empty? ? [] : Ext::CApi.imports(*objects).uniq.sort
            Scan.new(gem: subject.name, version: subject.version, sources: files.size, compiled: objects.size,
                     imports: imports, error: error)
          end
        end

        # The directories below the gem's ext/ that hold headers: what an
        # extconf.rb would add with `$INCFLAGS` or `dir_config`, at most
        # MAX_HEADER_DIRS of them.
        def header_dirs(subject)
          ext = File.join(subject.root, "ext")
          return [] unless File.directory?(ext)

          Dir.glob("**/*.{h,hpp,hh}", base: ext).map { |file| File.join(ext, File.dirname(file)) }.uniq.sort.first(MAX_HEADER_DIRS)
        end

        MAX_HEADER_DIRS = 64

        # Compiles `file` into `object`; the first error line, or nil.
        def compile(file, object, work, headers)
          cxx = !file.end_with?(".c")
          argv = [cxx ? RbConfig::CONFIG["CXX"] : RbConfig::CONFIG["CC"], *flags(file, work, cxx),
                  *headers.map { |dir| "-I#{dir}" }, "-c", file, "-o", object]
          answer, = Harness::Child.run(argv, cwd: work, seconds: COMPILE_SECONDS, megabytes: COMPILE_MB)
          return nil if answer.code == 0 && File.file?(object)
          return "the compile ran past #{COMPILE_SECONDS} s" if answer.code == :timeout

          answer.stderr.to_s.scrub.lines.find { |line| line.include?("error") }&.strip&.[](0, 200) || "exit #{answer.code}"
        end

        # The host ruby's flags for an extension, its headers, the file's
        # own directory and the stand-in extconf.h.
        def flags(file, work, cxx)
          config = RbConfig::CONFIG
          [*config["CPPFLAGS"].split, "-I#{config["rubyarchhdrdir"]}", "-I#{config["rubyhdrdir"]}", "-I#{File.dirname(file)}",
           "-I#{work}", "-O3", "-fdeclspec", "-w", *(cxx ? [] : LENIENT)]
        end
      end
    end
  end
end
