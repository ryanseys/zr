# frozen_string_literal: true

module Ze0
  # One program's output: its functions, and the tables the sidecar
  # describes -- the read-only bytes the code indexes, the interned
  # symbols, the inline-cache count and the top-level `def`s.
  # The `@all` spelling of `Sidecar::features`: every gated feature this
  # build carries, which only the backend can name.
  ALL_FEATURES = "@all"

  class Program
    # The methods ruby makes private wherever they are defined.
    ALWAYS_PRIVATE = %w[
      initialize initialize_copy initialize_clone initialize_dup respond_to_missing?
    ].freeze

    attr_reader :file, :frozen_string_literal

    def initialize(file, frozen_string_literal: false)
      @file = file
      @data_section = nil
      @frozen_string_literal = frozen_string_literal
      @rodata = "".b
      @rodata_offsets = {}
      @syms = []
      @sym_index = {}
      @callsites = []
      @regexp_sites = 0
      @defs = []
      @classes = []
      @functions = []
      @features = []
      @units = []
      @eval_install = false
    end

    # A require-gated builtin feature this program loads. The backend
    # registers the classes it gates, concealed until the `require` runs.
    # This program can reach a `load` or a require whose name only the
    # run time builds, so it carries the compiler that reads a file the
    # compile never saw.
    def eval_install! = @eval_install = true

    # A `require` whose feature string only the run time builds: it may
    # name any gated builtin, and one no `require` names literally
    # registers no class at all, so the constant would stay a NameError
    # after a require that worked. `@all` asks the backend for every
    # gated feature this build carries, each still CONCEALED.
    def require_any_feature!
      @features << ALL_FEATURES unless @features.include?(ALL_FEATURES)
    end

    # One spelling a `require` may use, and the function that runs the
    # file it names. A file answers to several spellings -- the name as
    # written and the absolute path `require_relative` expands to -- so
    # each is its own row over the one symbol.
    def add_unit(feature, symbol)
      @units << { "feature" => feature, "symbol" => symbol } unless @units.any? { |u| u["feature"] == feature }
    end

    # Where `DATA` reads from: the absolute path of the main file and the
    # offset its `__END__` bytes start at. The binary reopens the file at
    # startup, so the path cannot be relative to where the compile ran.
    def data_section=(pair)
      @data_section = pair && { "path" => pair[0], "offset" => pair[1] }
    end

    def add_feature(name)
      @features << name unless @features.include?(name)
    end

    # `bytes`' offset in the rodata blob (deduplicated).
    def intern(bytes)
      bytes = bytes.b
      @rodata_offsets[bytes] ||= begin
        off = @rodata.bytesize
        @rodata << bytes
        off
      end
    end

    # The `zeo_syms` slot of `name`.
    def sym(name)
      name = name.to_s
      @sym_index[name] ||= begin
        @syms << name
        @syms.size - 1
      end
    end

    # A fresh regexp site. Each non-interpolated literal is one frozen
    # object the runtime keeps per site, and ze0's code is the only caller
    # in the program, so a plain counter names them all.
    def regexp_site
      @regexp_sites += 1
      @regexp_sites - 1
    end

    # A fresh `zeo_callsites` slot, filed under the class whose body the
    # site is written in -- what ruby's visibility barrier compares an
    # explicit receiver's method against. `""` is a receiverless call,
    # which asks nothing.
    def callsite(caller)
      @callsites << caller
      @callsites.size - 1
    end

    def add_function(label, function)
      @functions << [label, function]
    end

    # A `def`'s dispatch and reflection row. An empty owner is the top
    # level, whose `def`s are private methods of `Object`. `visibility` is
    # the mode the class body was in where the `def` was written; ruby
    # makes a handful of names private wherever they appear. A second `def`
    # of one name REPLACES the first, as ruby's redefinition does: both
    # write the same body symbol, and only the last body is emitted.
    def add_def(name:, tramp:, params:, line:, file:, owner: "", singleton: false, visibility: "public")
      visibility = "private" if owner.empty? || ALWAYS_PRIVATE.include?(name.to_s)
      @defs.reject! { |d| d[:name] == name.to_s && d[:owner] == owner && d[:singleton] == singleton }
      @defs << {
        name: name.to_s, tramp: tramp, params: params, line: line, file: file,
        owner: owner, singleton: singleton, visibility: visibility,
      }
    end

    # One class or module. Ids are the backend's to assign, so nothing
    # here is a number.
    # Every row registers its shape before the first statement, so the
    # static MRO has one, and every row is CONCEALED: ruby makes the
    # constant where the `class` statement runs, and the body's own
    # `zeo_rt_reveal_class` is what does that.
    def add_class(name:, superclass:, kind:, ivars:, private_constants: [], file: "", line: 0,
                  singleton_of: nil)
      @classes << {
        name: name, superclass: superclass, kind: kind, ivars: ivars,
        private_constants: private_constants, file: file, line: line,
        singleton_of: singleton_of,
      }
    end

    # The `zeo_class_ids` slot of `name`.
    def class_slot(name)
      @classes.index { |c| c[:name] == name } or raise "no class row for #{name}"
    end

    # The superclass `owner` was declared with, by name.
    def superclass_of(owner)
      @classes.fetch(class_slot(owner))[:superclass]
    end

    # The slot `ivar` sits in on `owner`, which is its index in the class
    # row's declared order.
    def ivar_slot(owner, ivar)
      @classes.fetch(class_slot(owner))[:ivars].index(ivar) or
        raise "#{owner} declares no #{ivar}"
    end

    def clif
      @functions.map { |label, f| ";; #{label}\n#{f}\n" }.join
    end

    def zeodata
      Json.dump(
        "abi_version" => 1,
        "rodata" => @rodata.unpack1("H*"),
        "syms" => @syms,
        "callsites" => @callsites,
        "toplevel" => Names::TOPLEVEL,
        "data_section" => @data_section,
        "defs" => @defs.map do |d|
          {
            "name" => d[:name],
            "tramp" => d[:tramp],
            "params" => d[:params].map { |kind, name| [kind, name.to_s] },
            # A `def` names the file it was WRITTEN in, which a spliced
            # `require_relative` makes different from the program's.
            "file" => d[:file],
            "line" => d[:line],
            "visibility" => d[:visibility],
            "class" => d[:owner],
            "singleton" => d[:singleton],
          }
        end,
        "classes" => @classes.map do |c|
          {
            "name" => c[:name],
            "superclass" => c[:superclass],
            "kind" => c[:kind],
            "ivars" => c[:ivars],
            "private_constants" => c[:private_constants],
            "file" => c[:file],
            "line" => c[:line],
            # A singleton surrogate carries no constant of its own, so
            # there is nothing to conceal -- the row IS the cref.
            "conceal" => c[:singleton_of].nil?,
            # A `class << self` body's cref: the row IS `Owner`'s
            # singleton, and the backend ties the two so
            # `Owner.singleton_class` answers this id.
            "singleton_of" => c[:singleton_of],
          }
        end,
        # A dynamic send can reach any class, and ze0 has no reachability
        # analysis to say which; every table this build carries stays.
        "features" => @features,
        "units" => @units,
        "eval_install" => @eval_install,
        "class_tables" => ["@all"],
        "reg" => ["@boot"],
      ) + "\n"
    end
  end
end
