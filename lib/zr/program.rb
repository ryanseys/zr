# frozen_string_literal: true

module Zr
  # A program's own functions and data, and its runtime. It destructures
  # as `[functions, data, raw]` with the runtime included, for a build
  # that uses one unit for everything. `evals` is the EvalSupport that
  # the program links next to the runtime, or nil. Its JIT finds kernel
  # functions by name. `sources` maps the path of each file the program was
  # built from to the digest of the bytes that were compiled (the run
  # cache checks them); it is empty when the build does not know them.
  # `gems` are the manifest's rows (lib/zr/manifest.rb): the gems that the
  # program's files come from.
  #
  # The record's fields are typed in sig/zr/program.rbs.
  # @rbs skip
  Program = Data.define(:runtime, :functions, :data, :evals, :sources, :gems)

  # The methods are in a reopened class, not in the block of
  # `Data.define`, so that the type check sees them in their class.
  class Program
    # @rbs runtime: Runtime
    # @rbs functions: Array[Obj::Code | IR::Function]
    # @rbs data: Array[Obj::Datum]
    # @rbs evals: EvalSupport?
    # @rbs sources: Hash[String, String]
    # @rbs gems: Array[Manifest::Row]
    # @rbs return: void
    def initialize(runtime:, functions:, data:, evals:, sources: {}, gems: [])
      super
    end

    #: () -> Array[String]
    def raw = runtime.raw

    #: () -> Target
    def target = runtime.target

    #: () -> [Array[Obj::Code | IR::Function], Array[Obj::Datum], Array[String]]
    def to_ary = [runtime.functions + functions, runtime.data + data, raw]

    # The outputs of a build (`Native::Build`, which the caller loads).
    # Each writes the output to `out` and returns nil, or the message of
    # the step that refused.
    #
    # The runtime's object comes from the cache, so the object file at
    # `out` is the only file that zr writes.
    #: (String out) -> String?
    def write_object(out)
      Native::Build.runtime_object(runtime)
      Native::Build.object(functions, data, out, export: true, target: target)
    end

    #: (String out) -> String?
    def write_wasm(out) = Native::Build.wasm_program(self, out)

    #: (String out, work: String, link: Array[String]) -> String?
    def write_binary(out, work:, link:) =Native::Build.program(self, out, work: work, link: link)

    # The bytes of source above which a program's build tunes
    # (`GcTuning.heavy!`). hello and a probe are far below it; the stdlib rung
    # of the compile benchmark is above.
    HEAVY_SOURCE = 256 * 1024

    # The program of `source` (the file `file`) for `target`.
    #
    # With a block, each function goes to the block when its file is
    # lowered (`Lower#run`), with the lowering's entry name. The program
    # contains the block's results.
    #
    # With `sources`, the program lists the files it was built from
    # (`Program#sources`), for the run cache.
    #
    # `gem_set` is the GemSet whose gems come before zr's standard library
    # (lib/zr/gem_set.rb), or nil. `gate` stops the build at a require that
    # nothing has in the program's own files (`Hir::Build#gate!`). `trace`
    # arms the program's trace events whatever its files name.
    # @rbs source: String
    # @rbs file: String
    # @rbs target: Target
    # @rbs sources: bool
    # @rbs gem_set: GemSet?
    # @rbs gate: bool | Symbol
    # @rbs trace: bool
    # @rbs &finish: ? (IR::Function, String) -> Obj::Code
    # @rbs return: Program
    def self.build(source, file, target: Target.default, sources: false, gem_set: nil, gate: false, trace: false, &finish)
      rt = Runtime.for(target)
      support = EvalSupport.for(target)
      hir = Timing.phase("building the HIR", "hir built") do
        Hir.build(source, file, prebuilt: support, target: target, gem_set: gem_set, gate: gate, trace: trace)
      end
      redirects = gem_set && !gem_set.empty? ? gem_redirects(hir, support, gem_set, target) : {} #: Hash[String, String]
      redirects.merge!(LoadTables.own_copies(hir.entries, support.units)) if hir.evals
      # A large program is heavy work too (`GcTuning`): bundler's 1.2 MB of
      # source takes seconds to lower.
      GcTuning.heavy!(restart: false) if source.bytesize + hir.units.sum { |u| u.source.to_s.bytesize } > HEAVY_SOURCE
      # Before the lowering, which lets go of each unit's source.
      sources = sources ? built_from(source, file, hir) : {} #: Hash[String, String]
      gems = Manifest.of_program(hir, support, gem_set)
      symbols = hir.evals ? support.symbols : Machine::Symbols.new(rt.symbols.names, sites: rt.symbols.sites)
      # Only the kernel's names have fixed ids. The link numbers all other
      # names from `symbols`, so a unit's code does not depend on the
      # compile order or on the core. So an earlier build's code for a unit
      # is correct for this build while the kernel's ABI is the same.
      units = finish && Cache::Unit.for(hir, runtime: rt.abi_digest, entries: Lower.entries_of("zr_toplevel", hir.units))
      lower = Lower.new(hir, rt.description, symbols, target: target, fixed: rt.fixed_ids, units: units || nil)
      doing, done = finish ? ["lowering and assembling the program", "program lowered and assembled"] : ["lowering the program", "program lowered"]
      functions, data = Timing.phase(doing, done) do
        finish ? lower.run { |f| yield(f, lower.entry) } : lower.run
      end
      units = hir.entries.map do |path, i|
        [path, lower.unit_entry(i)] #: [String, String]
      end
      tag = rt.description.const_for("SYMBOL_TAG") #: Integer
      SymbolNumbering.number(data, symbols, tag)
      tables = LoadTables.new(evals: hir.evals, spots: hir.spots || {}, coverable: hir.coverable || {},
                              branches: hir.branches || {}, defs: hir.defs || {}, sources: hir.evals ? support.digests : {},
                              target: target, gem_roots: gem_set ? gem_set.gems.reject(&:refusal).flat_map(&:roots) : [],
                              manifest: Manifest.bytes(gems, target), redirects: redirects)
      new(rt, functions, data + SymbolNumbering.names_table(symbols) + tables.data(units), (support if hir.evals), sources, gems)
    end

    # Eval support has zr's own copy of some libraries (fileutils, pp, irb,
    # reline, json and others). A program with eval carries it, and every
    # program shares its prebuilt files, such as the json port's C half,
    # whose `require "json/common"` names the copy. When the program loads
    # one of these libraries from a gem in the GemSet, a require of the copy
    # runs the gem's file instead
    # (`zr_require_redirect`), so one copy loads, as in ruby. The result
    # maps the path of each such copy to the gem's file.
    #: (Hir::Program hir, EvalSupport support, GemSet gem_set, Target target) -> Hash[String, String]
    def self.gem_redirects(hir, support, gem_set, target)
      stdlib = Library::Roots.stdlib(target)
      carried = support.units.keys.filter_map do |path|
        root = stdlib.find { |dir| path.start_with?("#{dir}/") }
        [path.delete_prefix("#{root}/"), path] if root
      end.to_h
      redirects = {} #: Hash[String, String]
      hir.units.each do |unit|
        next unless unit.file

        gem_set.gems.each do |gem|
          root = gem.roots.find { |dir| unit.file.start_with?("#{dir}/") } or next
          copy = carried[unit.file.delete_prefix("#{root}/")]
          redirects[copy] = unit.file if copy && copy != unit.file
        end
      end
      redirects
    end

    # The path and digest of each file that `hir` was built from: `file`,
    # with `source`, and each unit that has its own file. Empty when a
    # require stays for the run time (a file that did not exist, or a name
    # built at run time): a file that appears later would change the
    # build, and no list of paths can say which.
    #: (String source, String file, Hir::Program hir) -> Hash[String, String]
    def self.built_from(source, file, hir)
      return {} if run_time_require?([hir.body, *hir.units.map(&:body)])

      # The filter keeps only the units that have a source.
      files = [[file, source], *hir.units.filter_map { |u| [u.file, u.source] if u.source && File.file?(u.file) }] #: Array[[String, String]]
      files.to_h { |path, bytes| [File.expand_path(path), Digest::SHA256.hexdigest(bytes)] }
    end

    REQUIRES = %i[require require_relative load].freeze

    # A require, require_relative or load of Kernel, or any autoload, that
    # the HIR left as a call.
    #: (untyped node) -> bool
    def self.run_time_require?(node)
      case node
      when Hir::Send
        kernel = node.recv.nil? || (node.recv.is_a?(Hir::ConstRead) && node.recv.name == :Kernel && node.recv.scope.nil?)
        return true if node.name == :autoload || (kernel && REQUIRES.include?(node.name))
      when Array then return node.any? { |child| run_time_require?(child) }
      when Hir::Node then nil
      else return false
      end
      Hir.each_child(node) { |child| return true if run_time_require?(child) }
      false
    end

    private_class_method :gem_redirects, :built_from, :run_time_require?
  end
end
