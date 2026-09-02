# frozen_string_literal: true

module Ze0
  # One program's output: its functions, and the tables the sidecar
  # describes -- the read-only bytes the code indexes, the interned
  # symbols, the inline-cache count and the top-level `def`s.
  class Program
    attr_reader :file

    def initialize(file)
      @file = file
      @rodata = "".b
      @rodata_offsets = {}
      @syms = []
      @sym_index = {}
      @callsites = 0
      @defs = []
      @functions = []
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

    # A fresh `zeo_callsites` slot.
    def callsite
      @callsites += 1
      @callsites - 1
    end

    def add_function(label, function)
      @functions << [label, function]
    end

    # A top-level `def`'s dispatch and reflection row.
    def add_def(name:, tramp:, params:, line:)
      @defs << { name: name.to_s, tramp: tramp, params: params, line: line }
    end

    def clif
      @functions.map { |label, f| ";; #{label}\n#{f}\n" }.join
    end

    def zeodata
      Json.dump(
        "abi_version" => 1,
        "rodata" => @rodata.unpack1("H*"),
        "syms" => @syms,
        "callsites" => Array.new(@callsites, 0xFFFF_FFFF),
        "toplevel" => Names::TOPLEVEL,
        "defs" => @defs.map do |d|
          {
            "name" => d[:name],
            "tramp" => d[:tramp],
            "params" => d[:params].map { |p| ["req", p.to_s] },
            "file" => @file,
            "line" => d[:line],
            "visibility" => "private",
          }
        end,
        # A dynamic send can reach any class, and ze0 has no reachability
        # analysis to say which; every table this build carries stays.
        "class_tables" => ["@all"],
        "reg" => ["@boot"],
      ) + "\n"
    end
  end
end
