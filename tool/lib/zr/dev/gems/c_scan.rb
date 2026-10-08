# frozen_string_literal: true

require "fiddle"
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
        # those import, `error` the first error of a file that failed, and
        # `scanner` the SCANNER that made it.
        Scan = Data.define(:gem, :version, :sources, :compiled, :imports, :error, :scanner) do
          # A scan kept before scans had a version is of the first scanner.
          def initialize(scanner: 1, **) = super

          def self.from_h(hash) = new(**hash.transform_keys(&:to_sym))

          def full_name = "#{gem}-#{version}"

          # Whether every file compiled, so `imports` is the whole set.
          def complete? = sources.positive? && compiled == sources

          # The imports that zr's C API lacks and `ruby` has: zr's gaps.
          def missing(ruby = RUBY) = Ext::CApi.missing(imports).select { |name| ruby.include?(name) }

          # The imports that `ruby` lacks too, as hiredis 0.x calls
          # rb_thread_select, which ruby 4.0 removed: no ruby loads them.
          def ruby_lacks(ruby = RUBY) = Ext::CApi.missing(imports).reject { |name| ruby.include?(name) }

          # A row of the sweep's .capi.jsonl.
          def to_h = super.merge(missing: missing, ruby_lacks: ruby_lacks)
        end

        # The functions of the ruby that runs this tool, which the gems are
        # compiled for (ruby 4.0.7): a name that this process exports.
        class HostRuby
          def initialize
            @exports = {}
          end

          #: (String name) -> bool
          def include?(name) = @exports.fetch(name) { @exports[name] = exported?(name) }

          private

          #: (String name) -> bool
          def exported?(name)
            Fiddle::Handle::DEFAULT[name]
            true
          rescue Fiddle::DLError
            false
          end
        end

        RUBY = HostRuby.new

        # The version of the scan. A kept scan that did not compile every
        # file is made again by a newer scanner, which may compile more.
        # 2: the headers of the gem's include/ and src/, and src/'s files
        # when an extconf.rb names it. 3: a header that cc does not find is
        # looked for anywhere in the gem. 4: then in the system's libraries.
        # 5: mkmf's HAVE_ macros for this ruby, an empty stand-in for a
        # header that an extconf.rb writes, and C++17.
        SCANNER = 5

        SOURCES = %w[c cc cpp cxx].freeze
        # The most seconds that one file's compile takes.
        COMPILE_SECONDS = 120
        # cc's memory limit for one file.
        COMPILE_MB = 2048
        # Errors that clang raises for C that older compilers took. The
        # scan wants the calls, not a clean build.
        LENIENT = %w[implicit-function-declaration incompatible-function-pointer-types int-conversion
                     incompatible-pointer-types implicit-int return-type].map { |name| "-Wno-error=#{name}" }.freeze

        # Where Homebrew keeps the headers of the libraries that it installs:
        # libpq's pg_config.h for pg, and the others that gems wrap.
        HOMEBREW = ENV.fetch("HOMEBREW_PREFIX", "/opt/homebrew")

        # The include directories of the system's libraries, Homebrew's own
        # first.
        def self.system_includes
          [File.join(HOMEBREW, "include"), *Dir[File.join(HOMEBREW, "opt", "*", "include")].sort].select { |dir| File.directory?(dir) }
        end

        attr_reader :dir

        # `system_includes` are where a header that the gem lacks is looked
        # for after the gem.
        def initialize(dir: File.join(TMP, "capi"), system_includes: CScan.system_includes)
          @dir = dir
          @system_includes = system_includes
        end

        # The Scan of `subject`'s C extensions, kept or made now.
        def call(subject)
          path = File.join(@dir, "#{subject.full_name}.json")
          kept = Scan.from_h(JSON.parse(File.read(path))) if File.file?(path)
          return kept if kept && (kept.complete? || kept.scanner >= SCANNER)

          scan = scan(subject)
          FileUtils.mkdir_p(@dir)
          File.write("#{path}.tmp", JSON.generate(scan.to_h.except(:missing, :ruby_lacks)))
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
        # API lacks and `ruby` has with the swept gems that need it, most
        # first; `extensions` gives each extension gem with the swept gems
        # that need it and its scan, most first.
        Ranking = Data.define(:functions, :extensions)

        def self.rank(rows, ruby: RUBY)
          needers = Hash.new { |hash, function| hash[function] = Set.new }
          extensions = {}
          rows.each do |name, scans|
            scans.each do |scan|
              scan.missing(ruby).each { |function| needers[function] << name }
              (extensions[scan.gem] ||= [scan, Set.new]).last << name
            end
          end
          functions = needers.map { |function, users| [function, users.sort] }
          gems = extensions.map { |gem, (scan, users)| [gem, users.sort, scan] }
          Ranking.new(functions.sort_by { |function, users| [-users.size, function] },
                      gems.sort_by { |gem, users, _| [-users.size, gem] })
        end

        # The C and C++ files below each extension's directory, and those of
        # the gem's src/ when an extension's extconf.rb names src (as rbs's
        # adds ../../src to its sources). The extconf.rb is read as text;
        # it does not run.
        def sources(subject)
          dirs = extension_dirs(subject)
          src = File.join(subject.root, "src")
          dirs << src if File.directory?(src) && dirs.any? { |dir| extconf_names_src?(dir) }
          dirs.flat_map { |dir| files_below(dir, SOURCES) }.uniq
        end

        private

        def scan(subject)
          files = sources(subject)
          headers = header_dirs(subject)
          Dir.mktmpdir("zr-cscan-") do |work|
            File.write(File.join(work, "extconf.h"), "")
            File.write(File.join(work, HAVE), ruby_defines)
            objects = []
            error = nil
            files.each_with_index do |file, i|
              object = File.join(work, "#{i}.o")
              failure = compile_finding_headers(subject, file, object, work, headers)
              failure ? (error ||= "#{File.basename(file)}: #{failure}") : objects << object
            end
            imports = objects.empty? ? [] : Ext::CApi.imports(*objects).uniq.sort
            Scan.new(gem: subject.name, version: subject.version, sources: files.size, compiled: objects.size,
                     imports: imports, error: error, scanner: SCANNER)
          end
        end

        # The directory of each extension, inside the gem.
        def extension_dirs(subject)
          subject.extensions.filter_map do |extension|
            dir = File.dirname(File.expand_path(extension, subject.root))
            dir if dir.start_with?(File.join(subject.root, "")) && File.directory?(dir)
          end.uniq
        end

        # Whether the extconf.rb in `dir` names a src directory.
        def extconf_names_src?(dir)
          extconf = File.join(dir, "extconf.rb")
          File.file?(extconf) && File.read(extconf, encoding: Encoding::BINARY).match?(%r{\bsrc\b})
        end

        # The files below `dir` with one of `extensions`, sorted.
        def files_below(dir, extensions) = Dir.glob("**/*.{#{extensions.join(",")}}", base: dir).sort.map { |file| File.join(dir, file) }

        HEADERS = %w[h hpp hh].freeze
        # The directories of a gem whose headers an extconf.rb adds with
        # `$INCFLAGS` or `dir_config`.
        HEADER_ROOTS = %w[ext include src].freeze
        MAX_HEADER_DIRS = 64

        # The directories below the gem's ext/, include/ and src/ that hold
        # headers, at most MAX_HEADER_DIRS of them. Each root itself comes
        # first, so `#include "rbs/ast.h"` finds include/rbs/ast.h.
        def header_dirs(subject)
          roots = HEADER_ROOTS.map { |name| File.join(subject.root, name) }.select { |dir| File.directory?(dir) }
          below = roots.flat_map { |root| files_below(root, HEADERS).map { |file| File.dirname(file) } }
          (roots + below).uniq.first(MAX_HEADER_DIRS)
        end

        # The most headers that one file's compile looks for in the gem.
        MAX_FOUND_HEADERS = 8

        # Compiles `file` as `compile` does. When cc does not find a header
        # (`'nokogiri_gumbo.h' file not found`), it looks for that header
        # anywhere in the gem or the system's libraries (`header_dir`), as
        # an extconf.rb would add its directory, and compiles again with it.
        # `headers` keeps what it found, for the gem's other files. A header
        # that is nowhere is one that an extconf.rb writes (curb_config.h,
        # libev's config.h): an empty one stands in for it.
        def compile_finding_headers(subject, file, object, work, headers)
          MAX_FOUND_HEADERS.times do
            failure = compile(file, object, work, headers)
            wanted = failure&.[](/'([^']+)' file not found/, 1)
            dir = wanted && header_dir(subject, wanted)
            next if wanted && dir.nil? && stand_in(work, wanted)
            return failure unless dir && !headers.include?(dir)

            headers << dir
          end
          compile(file, object, work, headers)
        end

        # Writes an empty `name` in `work`, which the compile searches, and
        # returns its path; nil when it is there already or names a place
        # outside it.
        def stand_in(work, name)
          path = File.join(work, name)
          return nil if name.start_with?("/") || name.split("/").include?("..") || File.exist?(path)

          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, "")
          path
        end

        # The file of the macros that mkmf's checks would define.
        HAVE = "zr_scan_have.h"

        # The macros that an extconf.rb's mkmf checks define for this ruby,
        # which an extension's C tests: HAVE_RUBY_IO_H for each of ruby's
        # headers (have_header), and HAVE_RB_STR_SET_LEN for each function
        # of them that this ruby has (have_func). Each file gets them, as
        # mkmf gives its $defs to each.
        def ruby_defines
          @ruby_defines ||= begin
            root = RbConfig::CONFIG["rubyhdrdir"]
            files = Dir.glob("**/*.h", base: root)
            headers = files.map { |file| "HAVE_#{file.upcase.gsub(/[^A-Z0-9]/, "_")}" }
            names = files.flat_map { |file| File.read(File.join(root, file)).scan(/\b((?:rb|ruby)_\w+)\s*\(/).flatten }.uniq
            functions = names.select { |name| RUBY.include?(name) }.map { |name| "HAVE_#{name.upcase}" }
            (headers + functions).uniq.sort.map { |macro| "#ifndef #{macro}\n#define #{macro} 1\n#endif\n" }.join
          end
        end

        # The directory from which `#include "name"` finds a file, or nil:
        # for `rbs/ast.h`, the parent of the rbs/ directory. It looks in the
        # gem, then in the system's libraries (SYSTEM_INCLUDES), as an
        # extconf.rb finds a library's headers with pkg-config.
        def header_dir(subject, name)
          return nil if name.start_with?("/") || name.split("/").include?("..")

          found = Dir.glob("**/#{name}", base: subject.root).min_by(&:size)
          return File.join(subject.root, found.delete_suffix(name)).chomp("/") if found

          @system_includes.find { |dir| File.file?(File.join(dir, name)) }
        end

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
        # own directory, the stand-in extconf.h and mkmf's macros. C++ is
        # C++17, which the C++ of today's gems (re2, grpc) needs.
        def flags(file, work, cxx)
          config = RbConfig::CONFIG
          [*config["CPPFLAGS"].split, "-I#{config["rubyarchhdrdir"]}", "-I#{config["rubyhdrdir"]}", "-I#{File.dirname(file)}",
           "-I#{work}", "-include", File.join(work, HAVE), "-O3", "-fdeclspec", "-w", *(cxx ? ["-std=gnu++17"] : LENIENT)]
        end
      end
    end
  end
end
