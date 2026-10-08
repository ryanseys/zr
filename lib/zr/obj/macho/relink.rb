# frozen_string_literal: true

require "fiddle"
require_relative "block"
require_relative "image"
require_relative "../../bytes"

module Zr
  module Obj
    module MachO
      # A C extension's precompiled bundle, relinked into an executable
      # (`Executable`, the embed mode of `--native-ext`). Its segments go
      # into the executable at the same distances from each other, so its
      # code reaches its own data as it did. What dyld would do to the
      # bundle at load, the executable's chained fixups do at launch:
      #
      # - each rebase moves with the bundle's new place;
      # - each bind to ruby's C API (`_rb_*`, `_ruby_*`, a data word such as
      #   `_rb_cObject`) becomes a rebase to the runtime's own definition;
      # - each other bind is an import from libSystem or one of the system
      #   dylibs that the bundle loads (liblzma), which the host's loader
      #   says defines it. Lazy binds bind at launch too, so the bundle's
      #   stub helper never runs.
      #
      # dyld does not run the bundle's initializers (`__mod_init_func`'s
      # pointers, or a newer linker's `__init_offsets`, offsets from the
      # bundle's start): the require of the extension runs them before its
      # Init function (`zr_ext_embedded`), as dlopen would. The bundle's link edit, symbol
      # table and unwind registration stay out: zr never unwinds through C.
      class Relink
        # @rbs @image: Image
        # @rbs @bytes: String
        # @rbs @init: String
        # @rbs @vm: Integer

        # One segment of the bundle, at its new address `vm`, with its file
        # bytes and its protection.
        # @rbs skip
        Part = Data.define(:name, :vm, :vmsize, :bytes, :prot)
        # A slot that the executable's fixups fill: a rebase to the address
        # `target`, or a bind to the import `target` (a name) plus `addend`.
        # @rbs skip
        Fixup = Data.define(:address, :kind, :target, :addend)

        SEGMENTS = { "__TEXT" => "__ZRX", "__DATA_CONST" => "__ZRC", "__DATA" => "__ZRD" }.freeze
        WRITE = 2
        # Section types: the initializers, as pointers or as offsets; and
        # what needs a loader zr does not run: thread-local variables.
        SECTION_TYPE = 0xFF
        MOD_INIT_FUNC_POINTERS = 0x9
        INIT_FUNC_OFFSETS = 0x16
        THREAD_LOCAL = (0x11..0x15)
        # The imports of code that throws C++ exceptions, which would unwind
        # through frames whose unwind information the relink leaves out.
        UNWINDS = %w[___cxa_throw __Unwind_RaiseException].freeze
        SYSTEM = %r{\A/(?:usr/lib|System/Library)/}
        # dyld's old entry for lazy binding, which only the stub helper
        # calls: with each lazy bind bound at launch, the helper never runs,
        # and its slot stays null (a newer dyld defines no such name).
        STUB_BINDER = "dyld_stub_binder"

        attr_reader :init #: String

        # The bundle `bytes`, whose Init function is `init` (`Init_nokogiri`).
        #: (String bytes, init: String) -> void
        def initialize(bytes, init:)
          @image = Image.read(bytes)
          @bytes = @image.bytes
          @init = init
          @vm = 0
          refuse_unsupported
        end

        # The bytes of address space that the bundle takes, from its first
        # segment to the end of its last, in pages.
        #: () -> Integer
        def span = Bytes.align(segments.map { |s| s.vmaddr + s.vmsize }.max - segments.first.vmaddr, Chains::PAGE)

        # Puts the bundle at `vm`, a page boundary.
        #: (Integer vm) -> void
        def place!(vm)
          @vm = vm - segments.first.vmaddr
        end

        # The bundle's segments at their new addresses, each named for the
        # extension's `index` among the executable's embeds.
        #: (Integer index) -> Array[Part]
        def parts(index)
          segments.map do |s|
            bytes = @bytes.byteslice(s.fileoff, s.filesize) || raise(Refused, "#{@init}: a segment past the bundle's end")
            Part.new(name: "#{SEGMENTS.fetch(s.name)}#{index}", vm: @vm + s.vmaddr, vmsize: s.vmsize, bytes: bytes.dup,
                     prot: s.initprot)
          end
        end

        # The names that the program's require of the extension reads
        # (`zr_ext_embedded`): its Init function, the start and the end of
        # its initializers' pointers and of their offsets, and the bundle's
        # start, which the offsets count from.
        #: () -> Hash[String, Integer]
        def symbols
          init = @image.exports.find { |e| e.name == "_#{@init}" } or raise Refused, "the bundle has no #{@init}"
          pointers = range(MOD_INIT_FUNC_POINTERS)
          offsets = range(INIT_FUNC_OFFSETS)
          { "_zr_ext_#{@init}" => @vm + (init.address || 0),
            "_zr_ext_inits_#{@init}" => pointers.begin, "_zr_ext_inits_end_#{@init}" => pointers.end,
            "_zr_ext_offsets_#{@init}" => offsets.begin, "_zr_ext_offsets_end_#{@init}" => offsets.end,
            "_zr_ext_base_#{@init}" => @vm + segments.first.vmaddr }
        end

        # The slots that the executable fills, with each bind's import and
        # its dylib. `runtime` gives the address of a name that the
        # executable defines, or nil.
        #: (^(String) -> Integer?) -> [Array[Fixup], Hash[String, String]]
        def fixups(runtime)
          imports = {} #: Hash[String, String]
          # A flat lookup finds a name in the executable first, then in the
          # bundle itself, then in its dylibs.
          own = @image.exports.select(&:address).to_h { |e| [e.name, @vm + e.address.to_i] }
          bound = @image.binds.to_h do |bind|
            at = runtime.call(bind.name) || own[bind.name]
            dylib = dylib_of(bind.name, weak: bind.weak) unless at || bind.name.delete_prefix("_") == STUB_BINDER
            fixup = if at
                      Fixup.new(address: @vm + bind.address, kind: :rebase, target: at + bind.addend, addend: 0)
                    elsif dylib
                      imports[bind.name.delete_prefix("_")] = dylib
                      Fixup.new(address: @vm + bind.address, kind: :bind, target: bind.name.delete_prefix("_"), addend: bind.addend)
                    else
                      # A weak import that no image defines stays null.
                      Fixup.new(address: @vm + bind.address, kind: :null, target: 0, addend: 0)
                    end
            [bind.address, fixup]
          end
          rebased = @image.rebases.reject { |r| bound.key?(r.address) }.map do |r|
            Fixup.new(address: @vm + r.address, kind: :rebase, target: @vm + r.target, addend: 0)
          end
          [rebased + bound.values, imports]
        end

        private

        #: () -> Array[Image::Segment]
        def segments = @image.segments.reject { |s| s.name == "__LINKEDIT" }

        # The new addresses of the section of `type`, or an empty range.
        #: (Integer type) -> Range[Integer]
        def range(type)
          section = @image.sections.find { |s| s.flags & SECTION_TYPE == type }
          section ? (@vm + section.addr)...(@vm + section.addr + section.size) : @vm...@vm
        end

        # The system dylib of the bundle's that defines `name`, as this
        # host's loader finds it; nil for a weak import that none defines.
        #: (String name, weak: bool) -> String?
        def dylib_of(name, weak:)
          symbol = name.delete_prefix("_")
          # A handle's dlsym also searches the dylib's own dependencies,
          # which libSystem is one of, so libSystem comes first.
          [Executable::LIBSYSTEM, *(@image.dylibs - [Executable::LIBSYSTEM])].each do |path|
            Fiddle::Handle.new(path).sym(symbol)
            return path
          rescue Fiddle::DLError
            next
          end
          return nil if weak

          raise Refused, "#{@init}: no dylib of the bundle defines #{symbol}"
        end

        #: () -> void
        def refuse_unsupported
          raise Refused, "#{@init}: a #{@image.filetype}, not a bundle" unless @image.filetype == :bundle

          other = segments.map(&:name) - SEGMENTS.keys
          raise Refused, "#{@init}: the bundle has the segment #{other.first}" unless other.empty?

          tls = @image.sections.find { |s| THREAD_LOCAL.cover?(s.flags & SECTION_TYPE) }
          raise Refused, "#{@init}: thread-local variables (#{tls.name}) need dyld; build with --ext=dynamic" if tls

          throws = @image.undefined & UNWINDS
          raise Refused, "#{@init}: its C++ throws exceptions (#{throws.first}); build with --ext=dynamic" unless throws.empty?

          foreign = @image.dylibs.grep_v(SYSTEM)
          raise Refused, "#{@init}: it loads #{foreign.first}, which is not a system dylib; build with --ext=dynamic" unless foreign.empty?

          fixed = (@image.rebases.map(&:address) + @image.binds.map(&:address)).find do |address|
            segment = segments.find { |s| address >= s.vmaddr && address < s.vmaddr + s.vmsize }
            !segment || (segment.initprot & WRITE).zero?
          end
          raise Refused, "#{@init}: a fixup outside its writable segments" if fixed
        end
      end
    end
  end
end
