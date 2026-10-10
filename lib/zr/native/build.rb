# frozen_string_literal: true

require "digest/sha2"
require "json"
require_relative "../ir"
require_relative "../ir/passes"
require_relative "../target"
require_relative "link"
require_relative "link/darwin"
require_relative "link/static"
require_relative "../backend/aarch64"
require_relative "../backend/wasm"
require_relative "../obj/macho/object_file"
require_relative "../obj/elf/object_file"
require_relative "../obj/elf/localize"
require_relative "../obj/macho/prelink"
require_relative "../obj/macho/relink"
require_relative "../machine/lower"
require_relative "../runtime"
require_relative "../timing"
require_relative "../config"
require_relative "../ext"
require_relative "../ext/c_api"
require_relative "parallel"
require_relative "code_cache"

module Zr
  module Native
    # Turns IR functions and data into the output that a target runs. The
    # target selects the parts: its backend writes the machine code, its
    # object writer writes the object, and its linker writes the binary
    # (`Link::Darwin`, `Link::Static`). A wasm32 target has one module and
    # no link step.
    module Build
      # The runtime or the eval support did not assemble: a defect in zr.
      class Failed < StandardError; end

      module_function

      # A unit with fewer IR instructions than this assembles in this
      # process. For a program's own functions, a worker costs more than
      # it saves.
      PARALLEL_THRESHOLD = 200_000

      # The number of workers for a large unit: `ZR_JOBS`, else one per
      # core, at most six. More than six workers compete for memory. Time
      # to build the runtime object on a twelve-core M2 Pro with 16 GB:
      #
      #     jobs      2      4      6      8     12
      #     seconds  17.4   11.4    9.5   11.8   26.9
      #
      # This is the maximum. At fork time, `Parallel.afforded` lowers it
      # from the parent's memory, which is about 100 times larger for the
      # compiled compiler than for the compiler under ruby. `ZR_JOBS`
      # overrides both limits; the table above was measured with it.
      #: () -> Integer
      def jobs = Config.current.jobs

      # The native backend for `target`.
      #: (Target target) -> singleton(Backend::Aarch64)
      def backend(target)
        { aarch64: Backend::Aarch64 }.fetch(target.arch) { raise ArgumentError, "no native backend for #{target}" }
      end

      # The object writer for `target`.
      #: (Target target) -> (singleton(Obj::MachO::ObjectFile) | singleton(Obj::Elf::ObjectFile))
      def writer(target)
        writers = { macho: Obj::MachO::ObjectFile, elf: Obj::Elf::ObjectFile }
        writers.fetch(target.object_format) { raise ArgumentError, "no object writer for #{target}" }
      end

      # The linker for `target`.
      #: (Target target) -> (singleton(Link::Darwin) | singleton(Link::Static))
      def linker(target)
        { darwin: Link::Darwin, static: Link::Static }.fetch(target.link) { raise ArgumentError, "no linker for #{target}" }
      end

      # Returns nil, or the message of the step that refused. `objects` are
      # prebuilt objects to link with this one. `strip` removes code that
      # nothing calls. `linker` (`ZR_LINKER`) selects the linker when the
      # target has more than one. `link` goes to the system linker as it
      # is (`--link`, `ZR_LINK_ARGS`), so it needs `cc`.
      # @rbs functions: Array[IR::Function | Obj::Code]
      # @rbs data: Array[Obj::Datum]
      # @rbs out: String
      # @rbs work: String
      # @rbs raw: Array[String]
      # @rbs assembled: Array[Obj::Code]
      # @rbs objects: Array[String]
      # @rbs strip: bool
      # @rbs linker: String
      # @rbs target: Target
      # @rbs jobs: Integer
      # @rbs link: Array[String]
      # @rbs return: String?
      def binary(functions, data, out, work:, raw: [], assembled: [], objects: [], strip: false, linker: Config.current.linker, target: Target.default, jobs: Build.jobs, link: [],
                 embeds: [])
        image = unit(functions, data, raw: raw, assembled: assembled, export: !objects.empty?, target: target, jobs: jobs)
        linker(target).link(image, out, work: work, objects: objects, strip: strip, linker: linker, target: target, link: link, embeds: embeds)
      rescue Backend::Refused => e
        e.message
      end

      # Links a `Zr::Program` into a binary. The runtime object comes from
      # the cache; this emits only the program's own functions and data.
      # A program that uses eval keeps all symbols, because its JIT finds
      # kernel functions by name. Functions that `assemble` already
      # assembled go in unchanged.
      #: (Program program, String out, work: String, ?jobs: Integer, ?link: Array[String]) -> String?
      def program(program, out, work:, jobs: Build.jobs, link: [])
        objects = [runtime_object(program.runtime, jobs: jobs)]
        objects << eval_support_object(program.evals, jobs: jobs) if program.evals
        root(program.runtime, objects, program.evals)
        functions, assembled = program.functions.partition { |f| f.is_a?(IR::Function) } #: [Array[IR::Function], Array[Obj::Code]]
        Timing.phase("writing and linking the program object", "program object written and linked") do
          # Once the C API has all that the C extensions import: zr's
          # linker relinks each bundle into a Mach-O binary
          # (`Obj::MachO::Relink`), a static extension's as `ext_bundle`
          # links it, and a binary that loads one with dlopen exports the
          # C API. An ELF binary links each static extension's object, with
          # its names its own (`ext_object`).
          target = program.runtime.target
          sources = Ext.bundles(target: target).values
          Ext::CApi.check!(sources)
          embeds = [] #: Array[Obj::MachO::Relink]
          if target.object_format == :elf
            objects += sources.map { |s| ext_object(s, target) }
            # The user's words (`--link`) come after the extensions'
            # libraries. A static archive takes only the names that are
            # missing when the linker reaches it, so the libraries that a
            # static libxml2.a needs (-llzma) go after -lxml2.
            link = sources.flat_map(&:libraries) + link
          else
            loaded, inside = sources.partition { |s| s.mode == :dynamic }
            embeds = inside.map { |s| Obj::MachO::Relink.new(File.binread(ext_bundle(s, target)), init: s.init) }
            link += exports(work) unless loaded.empty?
          end
          binary(functions, program.data, out, work: work, assembled: assembled, objects: objects, strip: !program.evals,
                                                           target: target, jobs: jobs, link: link, embeds: embeds)
        end
      end

      # The bundle of a C extension that zr's linker relinks into the
      # binary: a precompiled one as it is, or one that `cc` links from a
      # static extension's objects and libraries, as mkmf would, and the
      # store keeps. The bundle keeps the extension's names apart from the
      # program's and from another extension's: only its Init function
      # is read from outside.
      #: (Ext::Source source, Target target) -> String
      def ext_bundle(source, target)
        return source.library.to_s if source.library

        inputs = source.objects.map { |object| Digest::SHA256.file(object).hexdigest }
        key = Cache::Store.key("ext-bundle", Ext::ABI, target.triple, *inputs, *source.libraries)
        Cache::Store.once(:image, "#{key}-bundle") do |file|
          linked = "#{file}.#{Process.pid}"
          begin
            log, ok = Toolchain.run([Toolchain.command(target, "cc"), "-bundle", "-undefined", "dynamic_lookup",
                                     *Link::Darwin::MIN_OS_FLAGS, "-o", linked, *source.objects, *source.libraries])
            raise Refused, "cc cannot link #{File.basename(source.bundle)} from its objects:\n#{log.strip}" unless ok

            Cache::Store.write_file(file, File.binread(linked))
          ensure
            File.unlink(linked) if File.exist?(linked)
          end
        end
      end

      # The object of a static C extension in an ELF binary: its objects,
      # joined by the target's `cc -r`, with each name that they define
      # local but its Init function (`Obj::Elf::Localize`), as the store
      # keeps it. A static binary loads no library, so an extension that
      # is a compiled library (embed, dynamic) cannot be in one.
      #: (Ext::Source source, Target target) -> String
      def ext_object(source, target)
        unless source.mode == :static
          raise Refused, "#{File.basename(source.bundle)}: a #{target.triple} binary links a C extension from its objects, " \
                         "and this one is a compiled library (ZR_EXT=#{source.mode}); build it from its source (`--native-ext`)"
        end

        inputs = source.objects.map { |object| Digest::SHA256.file(object).hexdigest }
        localize = Digest::SHA256.file(File.expand_path("../obj/elf/localize.rb", __dir__)).hexdigest
        key = Cache::Store.key("ext-object", Ext::ABI, target.triple, source.init, localize, *inputs)
        Cache::Store.once(:object, key) do |file|
          joined = "#{file}.#{Process.pid}.o"
          begin
            log, ok = Toolchain.run([Toolchain.command(target, "cc"), "-r", "-nostdlib", "-o", joined, *source.objects])
            raise Refused, "cc cannot join the objects of #{File.basename(source.bundle)}:\n#{log.strip}" unless ok

            Cache::Store.write_file(file, Obj::Elf::Localize.call(File.binread(joined), source.init))
          ensure
            File.unlink(joined) if File.exist?(joined)
          end
        end
      end

      # The linker words that export the C API from the binary, for a bundle
      # that it loads with dlopen: its imports bind to the binary's names.
      # The list goes in `work`.
      #: (String work) -> Array[String]
      def exports(work)
        list = File.join(work, "capi.exports")
        File.write(list, Ext::CApi.names.sort.map { |name| "_#{name}\n" }.join)
        ["-Wl,-exported_symbols_list,#{list}"]
      end

      # Names the store entries that a link of `objects` reads (lib/zr/cache/store.rb),
      # so no eviction removes them: the objects, their prelinked image and
      # skeleton, the runtime's symbol table and gem prelude list, eval
      # support's metadata, and the code packs of this backend. A link with
      # eval support and one without each have a root.
      #: (Runtime runtime, Array[String] objects, EvalSupport? evals) -> void
      def root(runtime, objects, evals)
        target = runtime.target
        Cache::Store.root("#{target.triple}-link-#{evals ? "eval-#{evals.kind}" : "plain"}",
                   [*objects, prelink_path(objects), skeleton_path(objects), RuntimeSources.symbols_path(runtime.digest),
                    runtime.gem_prelude_path, (evals.meta_path if evals), CodeCache.dir])
      rescue SystemCallError, SourceChanged
        nil # a root that is not written protects less; the link goes on
      end

      # Lowers a program for a binary. It assembles the functions of each
      # file after it lowers that file, so the full IR is never in memory
      # at one time. It builds the runtime object first and then releases
      # the runtime's IR, so on a cold cache the two are not in memory
      # together.
      # @rbs source: String
      # @rbs file: String
      # @rbs target: Target
      # @rbs jobs: Integer
      # @rbs sources: bool
      # @rbs gem_set: GemSet?
      # @rbs gate: bool | Symbol
      # @rbs trace: bool
      # @rbs switches: Hir::Switches
      # @rbs return: Program
      def lower(source, file, target: Target.default, jobs: Build.jobs, sources: false, gem_set: nil, gate: false, trace: false,
                switches: Hir::Switches::NONE)
        runtime = Runtime.for(target)
        runtime.description
        runtime_object(runtime, jobs: jobs)
        runtime.release
        Program.build(source, file, target: target, sources: sources, gem_set: gem_set, gate: gate, trace: trace,
                                     switches: switches) do |f, entry|
          assemble(f, entry, target: target)
        end
      end

      # Prepares and assembles one function immediately after `Program.build`
      # lowers it. `entry` gives the spelling of its symbols.
      #: (IR::Function function, String entry, ?target: Target) -> Obj::Code
      def assemble(function, entry, target: Target.default)
        IR::Passes.prepare(function)
        backend(target).assemble(function, backend(target)::Spelled.new(entry))
      end

      # The prelinked bases that this process loaded, by path.
      #: () -> Hash[String, Obj::MachO::Prelink | bool | nil]
      def prelinks = Session.current.memo(:prelinks) { {} }

      # Links `objects` once, at the fixed addresses that every program
      # links against (`Obj::MachO::Prelink`). The name of a cached object
      # is the digest of its inputs, so the cache keeps its prelinked base
      # under those names. Objects that are not in the cache are linked
      # each time.
      #: (Array[String] objects) -> Obj::MachO::Prelink
      def prelink(objects)
        path = prelink_path(objects)
        return Obj::MachO::Prelink.build(objects.map { |o| File.binread(o) }) unless path

        # Kept in memory for the life of the process, and on disk. Reading
        # and parsing the 25 MB image took 21% of a link, and a test tier
        # links thousands of times. A link never writes to it.
        kept = prelinks[path] ||= File.exist?(path) &&
                                  Timing.phase("loading the prelink", "prelink loaded") { Obj::MachO::Prelink.load(File.binread(path)) } #: Obj::MachO::Prelink | false | nil
        return kept if kept

        Timing.phase("prelinking the objects", "objects prelinked") do
          Obj::MachO::Prelink.build(objects.map { |o| File.binread(o) }).tap { |base| Cache::Store.write_file(path, base.dump) }
        end
      end

      # Returns the cache path of the prelink of `objects`, or nil when the
      # objects are not in the cache. The object names are the digests of
      # their inputs. `Digests.link` adds the other input of the image:
      # the linker's own files, which the object digests do not include
      # on purpose.
      #: (Array[String] objects) -> String?
      def prelink_path(objects)
        top = File.dirname(Cache::Store.path(:object, "00"), 2)
        return nil if objects.empty? || objects.any? { |o| File.dirname(File.expand_path(o), 2) != top }

        Cache::Store.path(:image, "#{image_key(objects)}-prelink")
      end

      # The cache path of the skeleton of `objects`, next to their prelink.
      #: (Array[String] objects) -> String?
      def skeleton_path(objects) = prelink_path(objects) && Cache::Store.path(:image, "#{image_key(objects)}-skeleton")

      #: (Array[String] objects) -> String
      def image_key(objects) = Digest::SHA256.hexdigest([*objects.map { |o| File.basename(o) }, Digests.link].join("\n"))

      # Returns the path of the skeleton file for `objects`: the bytes that
      # every binary linked against them starts with (`Obj::MachO::Skeleton`).
      # It is in the cache, next to its prelink, and is written once per
      # prelink. Returns nil when the prelink is not in the cache.
      #: (Array[String] objects) -> String?
      def skeleton(objects)
        path = skeleton_path(objects) or return nil
        skeletons = Session.current.memo(:skeletons) { {} } #: Hash[String, String]
        skeletons[path] ||= File.exist?(path) ? path : Timing.phase("writing the skeleton", "skeleton written") { Cache::Store.write_file(path, Obj::MachO::Skeleton.bytes(prelink(objects))) }
      end

      # The eval support object, built once for each key.
      #: (EvalSupport support, ?jobs: Integer) -> String
      def eval_support_object(support, jobs: Build.jobs)
        Paths.once(support.object_path, waiting: -> { waiting("eval support", support.target) }) do
          eval_support_built(support, support.object_path, jobs)
        end
      end

      #: (EvalSupport support, String obj, Integer jobs) -> String
      def eval_support_built(support, obj, jobs)
        Paths.tmpdir("zr-eval-") do |work|
          fresh = File.join(work, "eval.o")
          # A Cache::Lowering::EvalSupport made the code of each unit, and
          # inlined the unit already; its code cache has that code.
          units = support.cache
          code = units&.code || CodeCache.for("eval", support.target)
          done = lambda do
            units = nil # the lambda would keep the IR alive
            support.release
          end
          why = Timing.phase("assembling and writing the eval support object", "eval support object assembled and written") do
            object(support.functions, support.data, fresh, export: true, target: support.target, jobs: jobs, cache: code,
                                                           inlined: !units.nil?, known: units&.known || {}, release: done)
          end
          raise Failed, "the eval support for #{support.target} did not build: #{why}" if why

          Cache::Store.write_file(obj, File.binread(fresh))
        end
      end

      # The runtime's object, built once per digest (the digest includes
      # the target). Two zr processes do not build the same object.
      #: (Runtime runtime, ?jobs: Integer) -> String
      def runtime_object(runtime, jobs: Build.jobs)
        Paths.once(runtime.object_path, waiting: -> { waiting("the zr runtime", runtime.target) }) do
          Runtime.announce("the zr runtime", runtime.target)
          runtime_built(runtime, runtime.object_path, jobs)
        end
      end

      #: (String what, Target target) -> void
      def waiting(what, target)
        warn "zr: waiting for another zr to build #{what} for #{target.triple}" unless Paths.checkout? && !$stderr.tty?
      end

      #: (Runtime runtime, String obj, Integer jobs) -> String
      def runtime_built(runtime, obj, jobs)
        Paths.tmpdir("zr-runtime-") do |work|
          fresh = File.join(work, "runtime.o")
          # A Cache::Lowering::Core made the core's code, and inlined the
          # unit already; its code cache has that code.
          core = runtime.core_cache
          cache = core&.code || CodeCache.for("runtime", runtime.target)
          why = Timing.phase("assembling and writing the runtime object", "runtime object assembled and written") do
            object(runtime.functions, runtime.data, fresh, raw: runtime.raw, export: true, target: runtime.target, jobs: jobs,
                                                                         cache: cache, inlined: !core.nil?, known: core&.known || {})
          end
          raise Failed, "the zr runtime for #{runtime.target} did not build: #{why}" if why

          Cache::Store.write_file(obj, File.binread(fresh))
        end
        obj
      end

      # Writes functions and data to one object file. `export` makes all
      # data visible to the linker, for an object that other objects refer to.
      # `cache` is the code cache of the object's kind, or nil. `inlined`
      # and `known` are `unit`'s. `release` lets the caller drop the IR once
      # it is machine code, before the writer allocates: then a collection
      # does not mark the IR again (4 s of eval support's write).
      # @rbs functions: Array[IR::Function | Obj::Code]
      # @rbs data: Array[Obj::Datum]
      # @rbs obj: String
      # @rbs raw: Array[String]
      # @rbs export: bool
      # @rbs target: Target
      # @rbs jobs: Integer
      # @rbs cache: CodeCache?
      # @rbs inlined: bool
      # @rbs known: Hash[String, [String, String]]
      # @rbs release: (^() -> void)?
      # @rbs return: String?
      def object(functions, data, obj, raw: [], export: false, target: Target.default, jobs: Build.jobs, cache: nil, inlined: false,
                 known: {}, release: nil)
        built = unit(functions, data, raw: raw, export: export, target: target, jobs: jobs, cache: cache, inlined: inlined,
                                      known: known)
        if release
          functions = nil # rubocop:disable Lint/UselessAssignment -- the frame would keep the IR alive
          release.call
        end
        File.binwrite(obj, Timing.phase("writing the object file", "object file written") { writer(target).write(built) })
        nil
      rescue Backend::Refused => e
        e.message
      end

      # Returns the same as an `Obj::Unit`, the input of an object writer
      # and of the JIT loader. Inlining needs the whole unit, so it runs
      # here. The passes and assembly of a function need only the function
      # and the unit's symbol names, so a large unit runs them in `jobs`
      # workers. `raw` names the raw functions (`Machine::RAW`), whose code
      # comes from the backend. `assembled` are functions that are already
      # machine code. With a `cache` (`CodeCache`), a function whose
      # fingerprint the cache has takes its code from there. `inlined` says
      # that the functions are inlined already (`Cache::Lowering::Core`). `functions` can
      # then have machine code in place of IR, whose fingerprint and bytes
      # `known` gives by name.
      # @rbs functions: Array[IR::Function | Obj::Code]
      # @rbs data: Array[Obj::Datum]
      # @rbs raw: Array[String]
      # @rbs assembled: Array[Obj::Code]
      # @rbs export: bool
      # @rbs target: Target
      # @rbs jobs: Integer
      # @rbs floor: Integer
      # @rbs cache: CodeCache?
      # @rbs inlined: bool
      # @rbs known: Hash[String, [String, String]]
      # @rbs return: Obj::Unit
      def unit(functions, data, raw: [], assembled: [], export: false, target: Target.default, jobs: Build.jobs,
               floor: PARALLEL_THRESHOLD, cache: nil, inlined: false, known: {})
        # Only an `inlined` unit has machine code among `functions`, and
        # only `cached` gets it: the backend gives `functions` to the
        # block as they are.
        ir = functions #: Array[IR::Function]
        Timing.phase("inlining the unit", "unit inlined") { IR::Passes.inline(ir) } unless inlined
        emitter = backend(target)
        code = assembled + raw.map { |name| emitter::Stub.function(name) }
        emitter.unit(ir, data, raw: code, export: export) do |all, defined|
          next cached(all, defined, emitter, cache, jobs, floor, known) if cache

          Timing.phase("assembling the unit (#{all.size} functions)", "unit assembled (#{all.size} functions)") do
            Parallel.map(all, jobs: jobs, weight: ->(f) { f.blocks.sum { |b| b.insts.size } }, floor: floor) do |f| #$ IR::Function, Obj::Code
              IR::Passes.prepare(f)
              emitter.assemble(f, defined)
            end
          end
        end
      end

      # The code of `all` through the code cache. Each worker takes the
      # fingerprints of its functions and assembles only those whose code
      # the cache does not have. (A first map that only took fingerprints,
      # without the warmup of the heap, spent its time in the workers'
      # collections instead.) Returns the code in the order of `all`, and
      # keeps all of it as the cache's newest pack. A function that is
      # machine code already stays as it is; `known` has its key and bytes
      # for the pack.
      # @rbs all: Array[IR::Function | Obj::Code]
      # @rbs defined: Set[String]
      # @rbs emitter: singleton(Backend::Aarch64)
      # @rbs cache: CodeCache
      # @rbs jobs: Integer
      # @rbs floor: Integer
      # @rbs known: Hash[String, [String, String]]
      # @rbs return: Array[Obj::Code]
      def cached(all, defined, emitter, cache, jobs, floor, known = {})
        verify = cache.verify?
        ir = all.each_index.select { |i| all[i].is_a?(IR::Function) }
        # The functions at `ir` are IR.
        functions = all.values_at(*ir) #: Array[IR::Function]
        weight = ->(f) { f.blocks.sum { |b| b.insts.size } } #: ^(IR::Function) -> Integer
        answers = Parallel.map(functions, jobs: jobs, weight: weight, floor: floor) do |f| #$ IR::Function, [String, untyped, bool]
          key = IR::Fingerprint.of(f, defined)
          # The code and its bytes with `verify`, else only the bytes.
          found = verify ? cache.take(key) : cache.blob(key) #: untyped
          next [key, found, false] if found && !verify

          IR::Passes.prepare(f)
          made = emitter.assemble(f, defined)
          raise "the code cache has other code for #{f.name}" if found && made != found.first

          [key, Marshal.dump(made), true]
        end
        made = ir.zip(answers).to_h
        Timing.phase("keeping the code cache", "code cache kept") { cache.keep(all.each_with_index.map { |f, i| made[i]&.first(2) || known.fetch(f.name) }) }
        warn format("zr: code cache: %d of %d functions assembled", answers.count(&:last), all.size) if Config.current.timing?
        loaded = Timing.phase("loading the code cache", "code cache loaded") { all.each_with_index.map { |f, i| made[i] ? Marshal.load(made[i][1]) : f } }
        # Each IR function is machine code now.
        loaded #: Array[Obj::Code]
      end

      # Writes the same functions and data as one WASI module. A raw
      # function, or a libc call that neither the OS layer nor
      # `Backend::Wasm.libc_shims` supplies, has no wasm form. A stop
      # function is put in its place; it stops with the function's name
      # when called. Data from another library also has no wasm form: a
      # zero word is put in its place, because every call that reads it
      # is a stop.
      #: (Array[IR::Function] functions, Array[Obj::Datum] data, String out, ?raw: Array[String]) -> String?
      def wasm(functions, data, out, raw: [])
        data = data.dup
        zero_words(functions, data, [])
        functions += stops(functions, raw, data, [])
        IR::Passes.inline(functions).each { |f| IR::Passes.prepare(f) }
        File.binwrite(out, Backend::Wasm.emit(functions, data))
        nil
      rescue Backend::Refused => e
        e.message
      end

      # Writes a `Zr::Program` as one WASI module. The runtime comes from
      # the cached prelude; this emits only the program's own functions.
      #
      # On wasm, eval support is the tree-walking interpreter
      # (lib/zr/eval/walk.rb): the front end and no backend. Wasm has no
      # second object to link, so a program that uses eval gets a prelude
      # that also contains eval support. Its 16,000 functions then compile
      # once for each cache, not once for each program (about 280 s).
      #: (Program program, String out) -> String?
      def wasm_program(program, out)
        pre = wasm_prelude(program.runtime, pending_for(program), program.evals || nil)
        # A program for wasm assembles nothing, so its functions are IR.
        functions = program.functions #: Array[IR::Function]
        data = program.data.dup
        zero_words(functions, data, pre.data_at.keys)
        functions += stops(functions, [], data, pre.functions)
        IR::Passes.inline(functions).each { |f| IR::Passes.prepare(f) }
        File.binwrite(out, Backend::Wasm.emit(functions, data, prelude: pre))
        nil
      rescue Backend::Refused => e
        e.message
      end

      # The runtime symbols that `program` defines. The runtime's prelude
      # leaves these symbols pending.
      #: (Program program) -> Backend::Wasm::Codegen::pending
      def pending_for(program)
        wants = program.runtime.wants
        { functions: wants[:functions] & program.functions.map(&:name), data: wants[:data] & program.data.map(&:name) }
      end

      # The runtime's wasm prelude, with eval support when `support` is
      # given. It is emitted once for each digest and set of pending
      # symbols, and kept in the cache.
      #
      # It is also kept in memory for the life of the process, as the
      # prelink is. The prelude is 41 MB of Marshal, and a test tier builds
      # one module for each example. A worker forked after the first build
      # shares the one copy. A build never writes to it.
      #: (Runtime runtime, Backend::Wasm::Codegen::pending pending, ?EvalSupport? support) -> Backend::Wasm::Codegen::Prelude
      def wasm_prelude(runtime, pending, support = nil)
        key = Digest::SHA256.hexdigest("#{runtime.digest}\n#{support&.key}\n#{pending.inspect}")
        path = Cache::Store.path(:wasm, key)
        preludes = Session.current.memo(:wasm_preludes) { {} } #: Hash[String, Backend::Wasm::Codegen::Prelude | false]
        kept = preludes[path] ||= File.exist?(path) && Marshal.load(File.binread(path))
        return kept if kept

        # The wasm backend takes only IR.
        functions = support ? runtime.functions + support.functions : runtime.functions #: Array[IR::Function]
        data = support ? runtime.data + support.data : runtime.data.dup
        zero_words(functions, data, pending[:data])
        functions += stops(functions, runtime.raw, data, pending[:functions])
        IR::Passes.inline(functions).each { |f| IR::Passes.prepare(f) }
        pre = Backend::Wasm.prelude(functions, data, pending: pending)
        Cache::Store.write_file(path, Marshal.dump(pre))
        preludes[path] = pre
      end

      # The data symbols that `functions` refer to and `data` does not define.
      #: (Array[IR::Function] functions, Array[Obj::Datum] data) -> Array[String]
      def foreign(functions, data)
        named = data.map(&:name)
        functions.flat_map { |f| f.globals.reject(&:colocated).map(&:symbol) }.uniq - named
      end

      # A zero word into `data` for each foreign data symbol not in `known`.
      #: (Array[IR::Function] functions, Array[Obj::Datum] data, Array[String] known) -> void
      def zero_words(functions, data, known)
        (foreign(functions, data) - known).each do |symbol|
          data << Obj::Datum.new(symbol, :data_const, "\0".b * 8, align: 8)
        end
      end

      # Stop functions for the raw functions and for each undefined callee
      # that is not a wasm import, not in `Backend::Wasm.libc_shims` and
      # not in `known`.
      #: (Array[IR::Function] functions, Array[String] raw, Array[Obj::Datum] data, Array[String] known) -> Array[IR::Function]
      def stops(functions, raw, data, known)
        out = raw.map do |name|
          r = Machine::RAW.fetch(name)
          params = r.params.map { |t| Machine::TYPES.fetch(t) or raise ArgumentError, "#{name}: a Void parameter" }
          stop(name, params, Machine::TYPES.fetch(r.ret), data)
        end
        defined = Set.new(functions.map(&:name) + out.map(&:name) + Backend::Wasm.libc_shims + known)
        functions.each do |f|
          f.callees.each do |c|
            next if c.from || defined.include?(c.symbol)

            # Each callee's signature is in the function's list.
            sig = f.sigs.find { |x| x.sig == c.sig } #: IR::Sig
            out << stop(c.symbol, sig.params, sig.ret, data)
            defined << c.symbol
          end
        end
        out
      end

      #: (String name, Array[String] params, String? ret, Array[Obj::Datum] data) -> IR::Function
      def stop(name, params, ret, data)
        message = "zr: #{name} has no wasm form\n"
        bytes = "zr_stop_#{name}"
        data << Obj::Datum.new(bytes, :text_const, message.b, align: 1)
        f = IR::Function.new(name, params, ret)
        f.call(f.callee("write", %w[i32 i64 i64], "i64", colocated: false), [f.iconst("i32", 2), f.symbol_value(f.symbol(bytes)), f.iconst("i64", message.bytesize)])
        f.call(f.callee("abort", [], nil, colocated: false), [])
        zero = case ret
               when nil then nil
               when "f64" then f.bitcast("f64", f.iconst("i64", 0))
               else f.iconst(ret, 0)
               end
        f.ret(zero)
        f
      end
    end
  end
end
