# frozen_string_literal: true

require "json"
require_relative "paths"
require_relative "library/layout"
require_relative "library/ports"
require_relative "library/stdlib"
require_relative "library/roots"
require_relative "version"

module Zr
  # Which gem each file of a build comes from. `zr gems` prints it, and
  # each binary carries it (`MAGIC`, then JSON), so `zr inspect` can tell
  # which gems a binary was built with.
  #
  # A row names the gem, its version and its source: `stdlib` (ruby's
  # own library in zr, a default or bundled gem), `port` (a gem with a C
  # part that zr ports, lib/zr/library/ports.rb), `Gemfile.lock` or
  # `installed` (a gem from rubygems' path, lib/zr/gem_set.rb). A file
  # of ruby itself that no gem ships (`pathname.rb`) is the row `ruby`.
  # The program's own files have no row.
  #
  # A gem of the GemSet also names its directory (`dir`), which the
  # program's Gem::Specification gives as `full_gem_path`, as an
  # installed gem's does: a library such as anonymous_loader reads a
  # gem's files from there. The directory is where the build found the
  # gem, as the paths of its files in a backtrace are.
  module Manifest
    # @rbs skip
    Row = Data.define(:name, :version, :source, :dir)

    # The fields are typed in sig/zr/manifest.rbs, the methods here.
    class Row
      # A row that names no directory leaves `dir` nil.
      #: (name: String, version: String, source: String, ?dir: String?) -> void
      def initialize(name:, version:, source:, dir: nil) = super

      #: () -> Hash[String, String]
      def to_h = { "name" => name, "version" => version, "source" => source, "dir" => dir }.compact
    end

    # The bytes before the manifest in a binary. A search for them finds
    # it in a Mach-O, an ELF file and a wasm module alike.
    MAGIC = "ZRGEMS1\n"

    module_function

    # The rows of every gem that a build can read: zr's standard library
    # and ports, with the gems of `gem_set` in place of theirs.
    #: (?GemSet? gem_set) -> Array[Row]
    def all(gem_set = nil)
      rows = {} #: Hash[String, Row]
      Library::Stdlib::DEFAULT.each { |name, version| rows[name] = Row.new(name, version, "stdlib") }
      Library::Stdlib::BUNDLED.each { |name, version| rows[name] = Row.new(name, version, "stdlib") }
      Library::Ports::ALL.each { |name, port| rows[name] = Row.new(name, port.version, "port") }
      gem_set&.gems&.each { |gem| rows[gem.name] = Row.new(gem.name, gem.version, gem.source) }
      rows.values.sort_by(&:name)
    end

    # The rows of the gems that the program `hir` carries: its own files,
    # and for a program with eval, every file of eval support (`support`),
    # which holds the libraries that the program and its evals load.
    #: (Hir::Program hir, EvalSupport support, ?GemSet? gem_set) -> Array[Row]
    def of_program(hir, support, gem_set = nil) = of(files_of(hir, support), gem_set, evals: hir.evals)

    # The files of the program `hir`, and for a program with eval, of eval
    # support (`support`).
    #: (Hir::Program hir, EvalSupport support) -> Array[String]
    def files_of(hir, support)
      files = hir.units.filter_map { |unit| unit.file if unit.file&.start_with?("/") }
      files += support.units.keys.select { |file| file.start_with?("/") } if hir.evals
      files
    end

    # The rows of the gems that `files` (a build's files) come from. A
    # program with eval (`evals`) can also require each gem of `gem_set`
    # at run time, from the gem's roots, so each of those has a row too.
    #: (Array[String] files, ?GemSet? gem_set, ?evals: bool) -> Array[Row]
    def of(files, gem_set = nil, evals: false)
      rows = files.filter_map { |file| row_for(File.expand_path(file), gem_set) }
      rows += gem_set.gems.reject(&:refusal).map { |gem| gem_row(gem) } if evals && gem_set
      # A gem of `gem_set` stands in place of zr's copy of that gem: a
      # file that every program shares (a port's prebuilt part) does not
      # list zr's version beside the program's.
      given = gem_set&.gems&.to_h { |gem| [gem.name, true] } || {}
      rows.uniq.reject { |row| given.key?(row.name) && %w[stdlib port].include?(row.source) }.sort_by(&:name)
    end

    # The bytes that a binary carries: MAGIC, then one line of JSON. Beside
    # the rows of the gems it carries, it names the default (`default`)
    # and bundled (`bundled`) gems of ruby's install, which rubygems lists
    # whether or not a program carries them, and the gem of each of
    # `files` (the build's files) that is a gem of ruby's library, a port
    # or a gem of `gem_set`, by the path that the program sees (`owners`),
    # and the gems whose C zr ports (`ports`).
    #: (Array[Row] rows, Target target, ?Array[String] files, ?GemSet? gem_set) -> String
    def bytes(rows, target, files = [], gem_set = nil)
      install = Library::Stdlib::DEFAULT.map { |name, version| Row.new(name, version, "default").to_h } +
                Library::Stdlib::BUNDLED.merge(Library::Stdlib::OTHER_BUNDLED).map { |name, version| Row.new(name, version, "bundled").to_h }
      manifest = { "zr" => VERSION, "ruby" => RUBY, "target" => target.triple, "install" => install, "gems" => rows.map(&:to_h),
                   "owners" => owners(files, gem_set), "ports" => Library::Ports::ALL.keys.sort }
      "#{MAGIC}#{JSON.generate(manifest)}\n".b
    end

    # The files of each gem of ruby's library, of each port and of each gem
    # of `gem_set` in `files`, by the gem's name, so that a require of one
    # activates its gem, as rubygems' require does. ruby's files that no
    # gem has (`ruby`) and rubygems' own are no gem's.
    #: (Array[String] files, ?GemSet? gem_set) -> Array[Hash[String, untyped]]
    def owners(files, gem_set = nil)
      by_gem = files.group_by { |file| row_for(File.expand_path(file), gem_set)&.name }
      by_gem.filter_map do |name, paths|
        { "name" => name, "files" => paths.map { |path| Paths.shown(path) }.uniq.sort } unless name.nil? || %w[ruby rubygems].include?(name)
      end.sort_by { |owner| owner["name"] }
    end

    # The manifest in the bytes of a binary, as a Hash, or nil. The text
    # ends at its newline or at the NUL after it. A binary that contains
    # zr itself also has MAGIC as a string of this file, which no JSON
    # follows, so each place is tried.
    #: (String bytes) -> Hash[String, untyped]?
    def find(bytes)
      bytes = bytes.b
      at = 0
      while (at = bytes.index(MAGIC.b, at))
        # `at` is in `bytes`, and the pattern matches empty text too, so
        # both are Strings.
        tail = bytes.byteslice(at + MAGIC.bytesize, 1 << 20) #: String
        line = tail[/\A[^\n\0]*/] #: String
        manifest = begin
          JSON.parse(line)
        rescue JSON::ParserError
          nil
        end
        return manifest if manifest.is_a?(Hash) && manifest.key?("gems")

        at += MAGIC.bytesize
      end
      nil
    end

    # The row of a GemSet gem: its directory is the parent of its `lib`
    # root, or its root.
    #: (GemSet::Entry gem) -> Row
    def gem_row(gem)
      root = gem.roots.first
      dir = root && (File.basename(root) == "lib" ? File.dirname(root) : root)
      Row.new(gem.name, gem.version, gem.source, dir)
    end

    #: (String file, GemSet? gem_set) -> Row?
    def row_for(file, gem_set)
      gem = gem_set&.gems&.find { |g| g.holds?(file) }
      return gem_row(gem) if gem

      Library::Ports::ALL.each do |name, port|
        return Row.new(name, port.version, "port") if port.vendored && file.start_with?("#{Library::Ports.lib(name)}/")
      end
      Library::Stdlib::BUNDLED.each do |name, version|
        return Row.new(name, version, "stdlib") if file.start_with?("#{Library::Layout.gem_root(name, version)}/")
      end
      return nil unless file.start_with?("#{Library::Layout::RUBYLIBDIR}/")

      feature = file.delete_prefix("#{Library::Layout::RUBYLIBDIR}/")
      # A port whose Ruby half is ruby's own (psych, openssl): its files
      # are named for it, as psych.rb and psych/.
      Library::Ports::ALL.each do |name, port|
        base = name.tr("-", "/")
        return Row.new(name, port.version, "port") if !port.vendored && (feature == "#{base}.rb" || feature.start_with?("#{base}/"))
      end
      name = default_gems[feature] || (feature.split("/").first.delete_suffix(".rb") == "rubygems" ? "rubygems" : "ruby")
      version = { "ruby" => RUBY, "rubygems" => Library::Stdlib::RUBYGEMS }.fetch(name) { Library::Stdlib::DEFAULT.fetch(name) }
      Row.new(name, version, "stdlib")
    end

    # Each file of a default gem in ruby's library, by its path there,
    # from the gem's specification (`s.files`).
    #: () -> Hash[String, String]
    def default_gems
      Session.current.memo(:default_gems) do
        Library::Stdlib::DEFAULT.each_with_object(
          {} #: Hash[String, String]
        ) do |(name, version), out|
          spec = File.join(Library::Layout::SPECIFICATIONS, "default", "#{name}-#{version}.gemspec")
          next unless File.file?(spec)

          File.read(spec)[/^\s*s\.files = \[(.*)\]/, 1].to_s.scan(/"([^"]+)"/).flatten.each do |path|
            out[path.delete_prefix("lib/")] = name if path.start_with?("lib/")
          end
        end
      end
    end
  end
end
