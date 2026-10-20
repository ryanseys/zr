# frozen_string_literal: true

require_relative "binary"
require_relative "embedded_files"
require_relative "ext"
require_relative "obj/model"
require_relative "paths"
require_relative "library/roots"
require_relative "target"

module Zr
  # The tables that `zr_load_tables` points to. A require with a computed
  # name reads them at run time. They are, in order:
  # - the count of compiled-in files, and one record (path bytes, length,
  #   toplevel, the toplevel's meta) for each. The meta is there only in a
  #   traced build (`metas`), which reads the code of a file as an
  #   instruction sequence; else it is 0;
  # - as (bytes, length), one name per line: the library directories to
  #   search after $LOAD_PATH, the ruby features that this runtime has no
  #   file for, the features ruby loads before the program, and the
  #   extensions directory. Only a program that can require a computed
  #   name (`computed`: it evals, or its C requires) gets these lines;
  # - error_highlight's spots for each file (every program has them), and
  #   Coverage's tables;
  # - for a program with eval, the digest of each eval support file
  #   (`sources`, path to SHA-256). It keys its parse cache on these;
  # - the gem manifest;
  # - for a program with a GemSet, the redirects.
  # Nothing here comes from the build machine: a binary contains no path
  # or flag of the ruby that compiled it.
  #
  # `gem_roots` are the roots of the build's GemSet. A program with eval
  # searches them right after ruby's own library, as its build did, so a
  # computed require finds the same gem.
  #
  # `manifest` is the gem manifest (lib/zr/manifest.rb), or nil. `zr
  # inspect` finds it in the binary, and rubygems in the program reads its
  # gems (lib/zr/runtime/lib/zr/gem_manifest.rb).
  #
  # `redirects` maps a file of eval support to the file of a gem that the
  # program loads for the same feature. Eval support carries its own copy
  # of some libraries (json, irb, reline, fileutils, pp...), and every
  # program shares its prebuilt files (a port's `require "json/common"`).
  # A require of such a copy runs the gem's file instead (`zr_require_redirect`), so
  # one copy loads, as in ruby.
  # @rbs skip -- typed in sig/zr/load_tables.rbs
  LoadTables = Data.define(:computed, :spots, :coverable, :branches, :defs, :sources, :target, :gem_roots, :manifest, :redirects, :gems,
                           :metas)

  # The fields are typed in sig/zr/load_tables.rbs, the methods here.
  class LoadTables
    # The bytes of a file's record.
    ROW = 32

    # @rbs computed: bool
    # @rbs spots: Hash[String, String]
    # @rbs coverable: Hash[String, [Integer, Array[Integer]]]
    # @rbs branches: Hash[String, Array[Array[untyped]]]
    # @rbs defs: Hash[String, Array[Array[untyped]]]
    # @rbs sources: Hash[String, String]
    # @rbs target: Target
    # @rbs gem_roots: Array[String]
    # @rbs manifest: String?
    # @rbs redirects: Hash[String, String]
    # @rbs gems: bool
    # @rbs metas: bool
    # @rbs return: void
    def initialize(computed: false, spots: {}, coverable: {}, branches: {}, defs: {}, sources: {}, target: Target.default, gem_roots: [],
                   manifest: nil, redirects: {}, gems: true, metas: false)
      super
    end

    # The data objects of the tables, with the files `units`: `[path,
    # entry]` pairs. A unit that only stops has no path.
    #: (?Array[[String, String]] units) -> Array[Obj::Datum]
    def data(units = [])
      embedded = embedded_text(units.map(&:first))
      units = units.filter_map do |path, entry|
        next unless path.start_with?("/")

        [Paths.shown(path), entry] #: [String, String]
      end.sort
      out = [] #: Array[Obj::Datum]
      text = ->(name, bytes) { out << Obj::Datum.new(name, :text_const, "#{bytes}\0".b, align: 1) }
      rows = +"".b
      row_relocs = [] #: Array[Obj::Reloc]
      units.each_with_index do |(path, entry), i|
        text.call("zr_unit_path_#{i}", path)
        row_relocs << Obj::Reloc.new(i * ROW, :abs64, "zr_unit_path_#{i}") << Obj::Reloc.new((i * ROW) + 16, :abs64, entry)
        row_relocs << Obj::Reloc.new((i * ROW) + 24, :abs64, "zr_meta_#{entry}") if metas
        rows << [0, path.bytesize, 0, 0].pack("Q<4")
      end
      out << Obj::Datum.new("zr_unit_rows", :data_const, rows.empty? ? "\0".b * 8 : rows, relocs: row_relocs, align: 8)
      words = [units.size, 0]
      relocs = [Obj::Reloc.new(8, :abs64, "zr_unit_rows")]
      [*texts, [embedded]].each_with_index do |lines, i|
        joined = lines.join("\n")
        text.call("zr_load_names_#{i}", joined)
        relocs << Obj::Reloc.new(words.size * 8, :abs64, "zr_load_names_#{i}")
        words << 0 << joined.bytesize
      end
      out << Obj::Datum.new("zr_load_table_words", :data_const, words.pack("Q<*"), relocs: relocs, align: 8)
      out << Obj::Datum.new("zr_load_tables", :data_const, "\0".b * 8, relocs: [Obj::Reloc.new(0, :abs64, "zr_load_table_words")], align: 8,
                                                                          linkage: :export)
    end

    # The files that the library files among `paths` read as data
    # (`EmbeddedFiles`), as one text: for each, its path as the build
    # writes it, its byte count, and its bytes, each part after a newline.
    # Only a build reads them: a compile in a running program reads no
    # library of the build machine.
    #: (Array[String] paths) -> String
    def embedded_text(paths)
      return "" if Binary.running?

      files = EmbeddedFiles.for(paths.select { |path| path.start_with?("/") }, [Library::Layout::PREFIX, *gem_roots])
      files.sort.map { |path, bytes| "#{Paths.shown(path)}\n#{bytes.bytesize}\n#{bytes.b}" }.join.b
    end

    # The texts after the files, in the order of the kernel's LoadTable:
    # each a list of lines. The host gives them to the kernel as a link
    # does (`Machine::Host::Walk`).
    #: () -> Array[Array[String]]
    def texts
      shown = ->(path) { Paths.shown(path) }
      # A ruby feature that no root here contains, then a tab and the
      # reason if there is one. So a computed require stops for the same
      # reason as a literal one.
      uncarried = Hir::Build.missing_features(target).map { |name| [name, *Hir::Build::UNSUPPORTED_LIBRARIES[name]].join("\t") }
      # Only a build reads the roots. An eval in a program (computed false)
      # builds its tables here too, and must not read them: they are the
      # build machine's directories.
      # The roots a run-time require searches before $LOAD_PATH, an empty
      # line, then the ones it searches after it (`Kernel.search`).
      names = if computed
                native = Library::Roots.native(target)
                # A gem whose C the build links (`--native-ext`) comes before
                # the ports, as in the build: a require that its C makes
                # (json's of json/common) finds the gem's file, not the port's.
                linked = gem_roots.select { |root| Ext.linked_under?([root], target: target) }
                later = (gem_roots - linked) + (Library::Roots.stdlib(target) - native)
                # A default gem's C that the build links is in ruby's arch
                # directory, where only the files compiled in count (`=`): a
                # bundle there that the build did not link is no file here.
                # A root of zr's ports of C (`*`) gives way to such C, as in
                # the build (`Loader#resolve`).
                archdir = RbConfig::CONFIG["archdir"]
                arch = [] #: Array[String]
                arch = ["=#{shown[archdir]}"] if Ext.bundles(target: target).each_key.any? { |path| path.start_with?("#{archdir}/") }
                [[*arch, *linked.map(&shown), *native.map { |root| "*#{shown[root]}" }, "", *later.map(&shown)], uncarried, Hir::Build::PRELOADED,
                 [shown[Library::Layout::EXT]]]
              else
                none = [] #: Array[String]
                [none] * 4
              end
      # error_highlight's spots, one file at a time: its name, a newline,
      # then its records, and a form feed before the next file.
      names << [spots.map { |file, rows| "#{shown[file]}\n#{rows}" }.join("\f")]
      # The lines that Coverage counts, one record per file: its path, its
      # line count, and the lines, tab-separated.
      names << coverable.map { |file, (count, lines)| "#{shown[file]}\t#{count}\t#{lines.uniq.join(",")}" }
      # The branches that Coverage reports, one record per file: its path,
      # then one `kind,id,root,start line,start column,end line,end
      # column` for each branch, in Coverage's order. `id` is the counter
      # that this branch increments. `root` is the index in the file of the
      # branch's root, or empty for a root.
      names << branches.map { |file, rows| "#{shown[file]}\t#{rows.map { |row| row.join(",") }.join("\t")}" }
      # The location of each def and block in a measured file, one record
      # per file: its path, then one `id,start line,start column,end
      # line,end column` for each scope. A definition finds its record by
      # its id, and so gets its span.
      names << defs.map { |file, rows| "#{shown[file]}\t#{rows.map { |row| row.join(",") }.join("\t")}" }
      names << sources.map { |path, digest| [shown[path], digest] }.sort.map { |path, digest| "#{path}\t#{digest}" }
      names << [manifest.to_s.chomp]
      names << redirects.map { |copy, gem_file| "#{shown[copy]}\t#{shown[gem_file]}" }.sort
      # `--disable-gems`: boot skips the gem prelude, as ruby skips its
      # gem_prelude.rb, so error_highlight, did_you_mean and
      # syntax_suggest do not load.
      names << (gems ? [] : ["off"])
      # The home that the build compiled ruby's library and the bundled
      # gems from, as the table writes its paths (below /zr for an install,
      # `Paths.portable`), then the home on the build machine, which a
      # build with a path root leaves out. A program that no zr runs takes
      # the second as its install prefix while it exists, else the first
      # (core/env.rb), so its $LOAD_PATH names the files that it has
      # compiled in, and a file that it loads from disk is there.
      names << [shown[Library::Layout::PREFIX], *(Library::Layout::PREFIX unless Paths.root)]
    end
  end
end
