# frozen_string_literal: true

require "json"
require_relative "paths"
require_relative "ports"
require_relative "stdlib"
require_relative "libraries"
require_relative "version"

module Zr
  # Which gem each file of a build comes from. `zr gems` prints it, and
  # each binary carries it (`MAGIC`, then JSON), so `zr inspect` can tell
  # which gems a binary was built with.
  #
  # A row names the gem, its version and its source: `stdlib` (ruby's
  # own library in zr, a default or bundled gem), `port` (a gem with a C
  # part that zr ports, lib/zr/ports.rb), `Gemfile.lock` or `--gem`
  # (lib/zr/gem_set.rb). A file of ruby itself that no gem ships
  # (`pathname.rb`) is the row `ruby`. The program's own files have no row.
  module Manifest
    Row = Struct.new(:name, :version, :source) do
      def to_h = { "name" => name, "version" => version, "source" => source }
    end

    # The bytes before the manifest in a binary. A search for them finds
    # it in a Mach-O, an ELF file and a wasm module alike.
    MAGIC = "ZRGEMS1\n"

    module_function

    # The rows of every gem that a build can read: zr's standard library
    # and ports, with the gems of `gem_set` in place of theirs.
    def all(gem_set = nil)
      rows = {}
      Stdlib::DEFAULT.each { |name, version| rows[name] = Row.new(name, version, "stdlib") }
      Stdlib::BUNDLED.each { |name, version| rows[name] = Row.new(name, version, "stdlib") }
      Ports::ALL.each { |name, port| rows[name] = Row.new(name, port.version, "port") }
      gem_set&.gems&.each { |gem| rows[gem.name] = Row.new(gem.name, gem.version, source_of(gem)) }
      rows.values.sort_by(&:name)
    end

    # The rows of the gems that `files` (a build's files) come from.
    def of(files, gem_set = nil)
      files.filter_map { |file| row_for(File.expand_path(file), gem_set) }.uniq.sort_by(&:name)
    end

    # The bytes that a binary carries: MAGIC, then one line of JSON.
    def bytes(rows, target)
      "#{MAGIC}#{JSON.generate({ "zr" => VERSION, "ruby" => RUBY, "target" => target.triple, "gems" => rows.map(&:to_h) })}\n".b
    end

    # The manifest in the bytes of a binary, as a Hash, or nil. The text
    # ends at its newline or at the NUL after it. A binary that contains
    # zr itself also has MAGIC as a string of this file, which no JSON
    # follows, so each place is tried.
    def find(bytes)
      bytes = bytes.b
      at = 0
      while (at = bytes.index(MAGIC.b, at))
        line = bytes.byteslice(at + MAGIC.bytesize, 1 << 20)[/\A[^\n\0]*/]
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

    # A GemSet gem's source, without the path of a `--gem` directory, so
    # that the same build on two machines carries the same bytes.
    def source_of(gem) = gem.source.start_with?("--gem") ? "--gem" : gem.source

    def row_for(file, gem_set)
      gem = gem_set&.gems&.find { |g| g.roots.any? { |root| file.start_with?("#{root}/") } }
      return Row.new(gem.name, gem.version, source_of(gem)) if gem

      Ports::ALL.each do |name, port|
        return Row.new(name, port.version, "port") if port.gem && file.start_with?("#{Ports.lib(name)}/")
      end
      Stdlib::BUNDLED.each do |name, version|
        return Row.new(name, version, "stdlib") if file.start_with?("#{Layout.gem_root(name, version)}/")
      end
      return nil unless file.start_with?("#{Libraries::LIB}/")

      feature = file.delete_prefix("#{Libraries::LIB}/")
      # A port whose Ruby half is ruby's own (psych, openssl): its files
      # are named for it, as psych.rb and psych/.
      Ports::ALL.each do |name, port|
        base = name.tr("-", "/")
        return Row.new(name, port.version, "port") if !port.gem && (feature == "#{base}.rb" || feature.start_with?("#{base}/"))
      end
      name = default_gems[feature] || (feature.split("/").first.delete_suffix(".rb") == "rubygems" ? "rubygems" : "ruby")
      version = { "ruby" => RUBY, "rubygems" => Stdlib::RUBYGEMS }.fetch(name) { Stdlib::DEFAULT.fetch(name) }
      Row.new(name, version, "stdlib")
    end

    # Each file of a default gem in ruby's library, by its path there,
    # from the gem's specification (`s.files`).
    def default_gems
      @default_gems ||= Stdlib::DEFAULT.each_with_object({}) do |(name, version), out|
        spec = File.join(Layout::SPECIFICATIONS, "default", "#{name}-#{version}.gemspec")
        next unless File.file?(spec)

        File.read(spec)[/^\s*s\.files = \[(.*)\]/, 1].to_s.scan(/"([^"]+)"/).flatten.each do |path|
          out[path.delete_prefix("lib/")] = name if path.start_with?("lib/")
        end
      end
    end
  end
end
