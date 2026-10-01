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
  Program = Data.define(:runtime, :functions, :data, :evals, :sources, :gems) do
    def initialize(runtime:, functions:, data:, evals:, sources: {}, gems: [])
      super
    end

    def raw = runtime.raw

    def to_ary = [runtime.functions + functions, runtime.data + data, raw]
  end

  class Program
    # The bytes of source above which a program's build tunes
    # (`Tune.heavy!`). hello and a probe are far below it; the stdlib rung
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
    # nothing has in the program's own files (`Hir::Build#gate!`).
    def self.build(source, file, target: Target.default, sources: false, gem_set: nil, gate: false, &finish)
      rt = Runtime.for(target)
      support = EvalSupport.for(target)
      hir = Timing.phase("hir built") { Hir.build(source, file, prebuilt: support, target: target, gem_set: gem_set, gate: gate) }
      gem_conflicts!(hir, support, gem_set, target) if hir.evals && gem_set && !gem_set.empty?
      # A large program is heavy work too (`Tune`): bundler's 1.2 MB of
      # source takes seconds to lower.
      Tune.heavy!(restart: false) if source.bytesize + hir.units.sum { |u| u.source.to_s.bytesize } > HEAVY_SOURCE
      # Before the lowering, which lets go of each unit's source.
      sources = sources ? built_from(source, file, hir) : {}
      gems = Manifest.of_program(hir, support, gem_set)
      symbols = hir.evals ? support.symbols : Machine::Symbols.new(rt.symbols.names, sites: rt.symbols.sites)
      # Only the kernel's names have fixed ids. The link numbers all other
      # names from `symbols`, so a unit's code does not depend on the
      # compile order or on the core. So an earlier build's code for a unit
      # is correct for this build while the kernel's ABI is the same.
      units = finish && Cache::Unit.for(hir, runtime: rt.abi_digest, entries: Lower.entries_of("zr_toplevel", hir.units))
      lower = Lower.new(hir, rt.description, symbols, target: target, fixed: rt.fixed_ids, units: units || nil)
      functions, data = Timing.phase(finish ? "program lowered and assembled" : "program lowered") do
        finish ? lower.run { |f| yield(f, lower.entry) } : lower.run
      end
      units = hir.entries.map { |path, i| [path, lower.unit_entry(i)] }
      SymbolNumbering.number(data, symbols, rt.description.const_for("SYMBOL_TAG"))
      tables = LoadTables.new(evals: hir.evals, spots: hir.spots || {}, coverable: hir.coverable || {},
                              branches: hir.branches || {}, defs: hir.defs || {}, sources: hir.evals ? support.digests : {},
                              target: target, gem_roots: gem_set ? gem_set.gems.reject(&:refusal).flat_map(&:roots) : [],
                              manifest: Manifest.bytes(gems, target))
      new(rt, functions, data + SymbolNumbering.names_table(symbols) + tables.data(units), hir.evals && support, sources, gems)
    end

    # A program with eval carries eval support, which has zr's own copy of
    # some libraries (fileutils, pp, irb, reline, rubygems and others). A
    # file of a gem in the GemSet with the same feature name would load a
    # second copy beside it, where ruby loads one. So such a build stops.
    def self.gem_conflicts!(hir, support, gem_set, target)
      stdlib = Hir::Build.stdlib(target)
      carried = support.units.keys.filter_map do |path|
        root = stdlib.find { |dir| path.start_with?("#{dir}/") }
        path.delete_prefix("#{root}/") if root
      end.to_h { |feature| [feature, true] }
      hir.units.each do |unit|
        next unless unit.file

        gem_set.gems.each do |gem|
          root = gem.roots.find { |dir| unit.file.start_with?("#{dir}/") } or next
          feature = unit.file.delete_prefix("#{root}/")
          next unless carried[feature]

          raise Refused, "#{feature} of #{gem.name} #{gem.version} (#{gem.source}): this program uses eval, so it carries " \
                         "zr's own #{feature}, and ruby loads only one copy. Use ruby #{RUBY}'s #{gem.name} " \
                         "(remove the override), or remove the eval"
        end
      end
    end

    # The path and digest of each file that `hir` was built from: `file`,
    # with `source`, and each unit that has its own file. Empty when a
    # require stays for the run time (a file that did not exist, or a name
    # built at run time): a file that appears later would change the
    # build, and no list of paths can say which.
    def self.built_from(source, file, hir)
      return {} if run_time_require?([hir.body, *hir.units.map(&:body)])

      [[file, source], *hir.units.filter_map { |u| [u.file, u.source] if u.source && File.file?(u.file) }]
        .to_h { |path, bytes| [File.expand_path(path), Digest::SHA256.hexdigest(bytes)] }
    end

    REQUIRES = %i[require require_relative load].freeze

    # A require, require_relative or load of Kernel, or any autoload, that
    # the HIR left as a call.
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

    private_class_method :gem_conflicts!, :built_from, :run_time_require?
  end
end
