# frozen_string_literal: true

require_relative "obj/model"
require_relative "paths"
require_relative "library/roots"
require_relative "target"

module Zr
  # The tables that `zr_load_tables` points to. A require with a computed
  # name reads them at run time. They are, in order:
  # - the count of compiled-in files, and one record (path bytes, length,
  #   toplevel) for each;
  # - as (bytes, length), one name per line: the library directories to
  #   search after $LOAD_PATH, the ruby features that this runtime has no
  #   file for, the features ruby loads before the program, and the
  #   extensions directory. Only a program with eval can require a
  #   computed name, so only such a program gets these lines;
  # - error_highlight's spots for each file (every program has them), and
  #   Coverage's tables;
  # - for a program with eval, the digest of each eval support file
  #   (`sources`, path to SHA-256). It keys its parse cache on these;
  # - the gem manifest.
  # Nothing here comes from the build machine: a binary contains no path
  # or flag of the ruby that compiled it.
  #
  # `gem_roots` are the roots of the build's GemSet. A program with eval
  # searches them right after ruby's own library, as its build did, so a
  # computed require finds the same gem.
  #
  # `manifest` is the gem manifest (lib/zr/manifest.rb), or nil. It is the
  # last text. `zr inspect` finds it in the binary, and rubygems in the
  # program reads its gems (lib/zr/runtime/lib/zr/gem_manifest.rb).
  LoadTables = Data.define(:evals, :spots, :coverable, :branches, :defs, :sources, :target, :gem_roots, :manifest)

  # The methods are in a reopened class, not in the block of
  # `Data.define`, so that the type check (sig/pilot/records.rbs) sees
  # them in the class that they belong to.
  class LoadTables
    def initialize(evals: false, spots: {}, coverable: {}, branches: {}, defs: {}, sources: {}, target: Target.default, gem_roots: [],
                   manifest: nil)
      super
    end

    # The data objects of the tables, with the files `units`: `[path,
    # entry]` pairs. A unit that only stops has no path.
    def data(units = [])
      units = units.select { |path, _| path.start_with?("/") }.map do |path, entry|
        [Paths.shown(path), entry] #: [String, String]
      end.sort
      out = [] #: Array[Obj::Datum]
      text = ->(name, bytes) { out << Obj::Datum.new(name, :text_const, "#{bytes}\0".b, align: 1) }
      rows = +"".b
      row_relocs = [] #: Array[Obj::Reloc]
      units.each_with_index do |(path, entry), i|
        text.call("zr_unit_path_#{i}", path)
        row_relocs << Obj::Reloc.new(i * 24, :abs64, "zr_unit_path_#{i}") << Obj::Reloc.new((i * 24) + 16, :abs64, entry)
        rows << [0, path.bytesize, 0].pack("Q<3")
      end
      out << Obj::Datum.new("zr_unit_rows", :data_const, rows.empty? ? "\0".b * 8 : rows, relocs: row_relocs, align: 8)
      words = [units.size, 0]
      relocs = [Obj::Reloc.new(8, :abs64, "zr_unit_rows")]
      texts.each_with_index do |lines, i|
        joined = lines.join("\n")
        text.call("zr_load_names_#{i}", joined)
        relocs << Obj::Reloc.new(words.size * 8, :abs64, "zr_load_names_#{i}")
        words << 0 << joined.bytesize
      end
      out << Obj::Datum.new("zr_load_table_words", :data_const, words.pack("Q<*"), relocs: relocs, align: 8)
      out << Obj::Datum.new("zr_load_tables", :data_const, "\0".b * 8, relocs: [Obj::Reloc.new(0, :abs64, "zr_load_table_words")], align: 8,
                                                                          linkage: :export)
    end

    # The texts after the files, in the order of the kernel's LoadTable:
    # each a list of lines. The host gives them to the kernel as a link
    # does (`Machine::Host::Walk`).
    def texts
      shown = ->(path) { Paths.shown(path) }
      # A ruby feature that no root here contains, then a tab and the
      # reason if there is one. So a computed require stops for the same
      # reason as a literal one.
      uncarried = Hir::Build.missing_features(target).map { |name| [name, *Hir::Build::UNSUPPORTED_LIBRARIES[name]].join("\t") }
      # Only a build reads the roots. An eval in a program (evals false)
      # builds its tables here too, and must not read them: they are the
      # build machine's directories.
      names = if evals
                pure = Library::Roots.pure
                roots = Library::Roots.stdlib(target) - [pure]
                [[pure, *gem_roots, *roots].map(&shown), uncarried, Hir::Build::PRELOADED, [shown[Library::Layout::EXT]]]
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
    end
  end
end
