# frozen_string_literal: true

module Zr
  # Eval support: the compiler that a program with eval links in. zr
  # lowers it once and assembles it into its own object, so a program with
  # eval lowers and assembles only itself. Next to the object, the cache
  # keeps the metadata that a program needs: the entry of each file, its
  # dependencies, and the symbol table after it. The key is the eval
  # digest (`RuntimeSources#eval_digest`) and the bytes of each file in
  # eval support.
  #
  # Its code has only the kernel's ids, so the code of each file depends on
  # the compiler, the kernel's description and the file
  # (`Cache::Lowering::EvalSupport` keeps it). Only its data, whose pool
  # words the runtime's table numbers, depends on the core: a core edit
  # writes the object again from the kept code.
  class EvalSupport
    # @rbs @runtime: Runtime
    # @rbs @meta: Hash[String, untyped]?
    # @rbs @lowered: Hash[Symbol, untyped]?
    # @rbs @cache: Cache::Lowering::EvalSupport?

    # The eval support of this process for each target, by triple.
    #: () -> Hash[String, EvalSupport]
    def self.loaded
      Session.current.memo(:eval_supports) do
        {} #: Hash[String, EvalSupport]
      end
    end

    # The eval support for `target`, made once per process.
    #: (?Target target) -> EvalSupport
    def self.for(target = Target.default) = loaded[target.triple] ||= new(Runtime.for(target))

    #: (Runtime runtime) -> void
    def initialize(runtime)
      @runtime = runtime
    end

    #: () -> Target
    def target = @runtime.target

    #: () -> Hash[String, String]
    def units = meta.fetch("units")
    #: () -> bool
    def configures? = meta.fetch("configures")
    #: () -> bool
    def normalizes? = meta.fetch("normalizes")
    #: () -> bool
    def pretty_prints? = meta.fetch("pretty_prints")
    #: () -> bool
    def irbs? = meta.fetch("irbs")
    #: () -> bool
    def gems? = meta.fetch("gems")

    # A new symbol table for a program's lowering. It continues from the
    # eval support table: the runtime's names now, then eval support's own,
    # which start after the runtime's table.
    #: () -> Machine::Symbols
    def symbols
      runtime = @runtime.symbols.names
      Machine::Symbols.new(runtime + meta.fetch("names").drop(runtime.size), sites: meta.fetch("sites"))
    end

    # The number of `using` entries that eval support itself uses. Its
    # files activate refinements when they load (the prism port gets its
    # node setters through one), and they load at the first eval. So a
    # program's entries must start after these.
    #: () -> Integer
    def activations = meta.fetch("activations")

    # The SHA-256 of each file in eval support (as lowered) and of each
    # file that the gem prelude loads, by path. A binary with eval support
    # (and the compiled compiler of `zr-dev stage`) keys its parse cache on
    # these (`Cache::Parse.parser_digests`,
    # `Cache::Parse.maker`).
    #: () -> Hash[String, String]
    def digests = meta.fetch("digests")

    # The key of eval support's object (`Digests.eval_key`): the key of its
    # files (the eval digest and the bytes of each file), and the symbol
    # table that numbers its data. The object has this name.
    #: () -> String
    def key = meta.fetch("key")

    #: () -> String
    def object_path = self.class.object_path(key)

    # The metadata file of this eval support. The run cache checks it.
    #: () -> String
    def meta_path = self.class.meta_path(@runtime, kind)

    # The cache files of eval support: the object, by the key in its
    # metadata, and the metadata, by the runtime's digest and the kind
    # of eval (`jit` or `walk`). `zr cache clean` reads these too.
    #: (String key) -> String
    def self.object_path(key) = Cache::Store.path(:object, key)
    #: (Runtime runtime, String kind) -> String
    def self.meta_path(runtime, kind) = meta_file(runtime.eval_digest, kind)
    #: (String eval_digest, String kind) -> String
    def self.meta_file(eval_digest, kind) = Cache::Store.path(:meta, "#{eval_digest}-eval-#{kind}")

    #: () -> Array[Obj::Code | IR::Function]
    def functions = lowered.fetch(:functions)
    #: () -> Array[Obj::Datum]
    def data = lowered.fetch(:data)

    # Lets go of the IR once the object is written. Only the metadata stays.
    # The IR of 18,000 functions made each collection of the link that
    # follows mark it again: 11 s of a link after eval support was built.
    #: () -> void
    def release
      meta
      @lowered = @cache = nil
    end

    # The `Cache::Lowering::EvalSupport` of this build's lowering, or nil.
    #: () -> Cache::Lowering::EvalSupport?
    def cache
      lowered
      @cache
    end

    # The eval kind of the target is part of the cache name. The eval
    # compiler (JIT) and the tree-walking interpreter contain different
    # files, so the metadata of one must never be used for the other.
    #: () -> String
    def kind = Library::Roots.eval_file(target) == Library::Roots::EVAL_COMPILER ? "jit" : "walk"

    private

    # The cached metadata, while its files have the same bytes; else the
    # metadata of a new lowering. Its path has the runtime's eval digest,
    # so another runtime table has other metadata.
    #: () -> Hash[String, untyped]
    def meta
      @meta ||= begin
        meta = moved(JSON.parse(File.read(meta_path)), Paths.method(:local)) if File.exist?(meta_path)
        current = meta && meta["files_key"] == files_key(meta.fetch("files"), {}, meta.fetch(
          "absent",
          [] #: Array[String]
        ))
        current && meta ? meta : lowered.fetch(:meta)
      end
    end

    # `meta` with each path in its lists of files through `to`: the cache
    # keeps them portable (`Paths.portable`), so that eval support built
    # at one install serves another (`zr cache export`).
    #: (Hash[String, untyped] meta, Method to) -> Hash[String, untyped]
    def moved(meta, to)
      meta.merge("files" => meta.fetch("files").map { |path| to.call(path) },
                 "absent" => meta.fetch("absent", []).map { |path| to.call(path) },
                 "digests" => meta.fetch("digests").transform_keys { |path| to.call(path) },
                 "units" => meta.fetch("units").transform_keys { |path| to.call(path) })
    end

    # The key of eval support: the runtime's eval digest and the bytes of
    # each file. A build gives the bytes that it lowered (`sources`), so an edit
    # during the build cannot put old output under the new bytes' key. A
    # check of the cache reads the files as they are now.
    #: (Array[String] files, ?Hash[String, String] sources, ?Array[String] absent) -> String
    def files_key(files, sources = {}, absent = []) = Digests.eval_files_key(@runtime.eval_digest, files, sources, absent)

    #: () -> Hash[Symbol, untyped]
    def lowered
      @lowered ||= Timing.phase("lowering eval support", "eval support lowered") do
        GcTuning.heavy!
        Runtime.announce("eval support (the compiler in a program that calls eval)", target)
        loader = Hir::Build.eval_support(target)
        program = Hir::Program.new(Library::Roots.eval_file(target), [], Hir::Seq.new([], 0), loader.units, [], true, loader.entries)
        lower = Lower.new(program, @runtime.description, nil, entry: "zr_eval_support", target: target, fixed: @runtime.fixed_ids)
        cached = @cache = Cache::Lowering::EvalSupport.for(target, kind)
        functions, data = cached ? cached.lower(lower, @runtime.description) : lower.run
        # Eval support's names come after the runtime's.
        symbols = Machine::Symbols.new(@runtime.symbols.names, sites: @runtime.symbols.sites)
        data = SymbolNumbering.numbered_copies(data, symbols,
                                               @runtime.description.const_for("SYMBOL_TAG") #: Integer
                                              )
        files = loader.units.filter_map { |u| u.file if u.file.start_with?("/") }.uniq.sort
        sources = loader.units.each_with_object(
          {} #: Hash[String, String]
        ) { |u, h| h[u.file] ||= u.source if u.source }
        digests = (files + @runtime.gem_prelude_files).uniq.sort.to_h do |path|
          [path, Digest::SHA256.hexdigest(sources[path] || File.binread(path))]
        end
        # A file that appears where a stopped feature would be makes this
        # lowering stale, though no file that it read changed.
        absent = loader.stopped.uniq.sort.flat_map { |feature| Library::Roots.stdlib(target).map { |root| File.join(root, "#{feature}.rb") } }
        read = files_key(files, sources, absent)
        meta = { "key" => Digests.eval_key(read, symbols.names, symbols.sites), "files_key" => read, "files" => files, "absent" => absent,
                 "digests" => digests,
                 "units" => loader.entries.to_h { |path, i| [path, lower.unit_entry(i)] },
                 "configures" => loader.configures?, "normalizes" => loader.normalizes?, "pretty_prints" => loader.pretty_prints?,
                 "irbs" => loader.irbs?, "gems" => loader.gems?,
                 "names" => symbols.names, "sites" => symbols.sites, "activations" => loader.activations }
        Cache::Store.write_file(meta_path, JSON.generate(moved(meta, Paths.method(:portable))))
        { functions: functions, data: data, meta: meta }
      end
    end
  end
end
