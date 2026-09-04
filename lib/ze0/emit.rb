# frozen_string_literal: true

module Ze0
  # One program's output: its functions, and the tables the sidecar
  # describes -- the read-only bytes the code indexes, the interned
  # symbols, the inline-cache count and the top-level `def`s.
  class Program
    # The methods ruby makes private wherever they are defined.
    ALWAYS_PRIVATE = %w[
      initialize initialize_copy initialize_clone initialize_dup respond_to_missing?
    ].freeze

    attr_reader :file, :frozen_string_literal

    def initialize(file, frozen_string_literal: false)
      @file = file
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
    end

    # A require-gated builtin feature this program loads. The backend
    # registers the classes it gates, concealed until the `require` runs.
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
    def add_class(name:, superclass:, kind:, ivars:, private_constants: [], file: "", line: 0)
      @classes << {
        name: name, superclass: superclass, kind: kind, ivars: ivars,
        private_constants: private_constants, file: file, line: line,
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
          }
        end,
        # A dynamic send can reach any class, and ze0 has no reachability
        # analysis to say which; every table this build carries stays.
        "features" => @features,
        "class_tables" => ["@all"],
        "reg" => ["@boot"],
      ) + "\n"
    end
  end
end
