# frozen_string_literal: true

module Ze0
  # A target ze0 emits for: its instruction set, its OS, its object
  # format and the facts a build reads off them. The gem runs on any
  # host; a target says what it builds, and `refusal` says whether this
  # host can build it.
  class Target
    attr_reader :triple, :arch, :os, :libc, :object_format, :word, :page, :symbol_prefix, :ruby_platform, :link, :roads

    # `roads` are the outputs ze0 can build for the target today: `:native`
    # (a binary), `:obj` (an object) and `:wasm` (a module).
    def initialize(triple:, arch:, os:, object_format:, page:, symbol_prefix:, ruby_platform:, link:, roads:, libc: nil, word: 8)
      @triple = triple
      @arch = arch
      @os = os
      @libc = libc
      @object_format = object_format
      @word = word
      @page = page
      @symbol_prefix = symbol_prefix
      @ruby_platform = ruby_platform
      @link = link
      @roads = roads
    end

    def to_s = triple

    # The runtime layer each OS's target is lowered with: rt/kernel/os/,
    # rt/core/os/ and rt/ext/os/ each hold one directory per layer.
    OS_LAYERS = { darwin: "darwin", linux: "linux", wasi: "wasi" }.freeze
    # The machine layer, under rt/kernel/arch/.
    ARCH_LAYERS = { aarch64: "aarch64", wasm32: "wasm32" }.freeze

    def os_layer = OS_LAYERS.fetch(os)
    def arch_layer = ARCH_LAYERS.fetch(arch)

    REGISTRY = {}

    def self.register(target)
      REGISTRY[target.triple] = target
    end

    AARCH64_DARWIN = register(new(triple: "aarch64-apple-darwin", arch: :aarch64, os: :darwin, object_format: :macho,
                                  page: 16_384, symbol_prefix: "_", ruby_platform: "arm64-darwin23",
                                  link: :darwin, roads: %i[native obj]))
    AARCH64_LINUX_MUSL = register(new(triple: "aarch64-linux-musl", arch: :aarch64, os: :linux, libc: :musl,
                                      object_format: :elf, page: 4096, symbol_prefix: "", ruby_platform: "aarch64-linux-musl",
                                      link: :static, roads: %i[native obj]))
    WASM32_WASI = register(new(triple: "wasm32-wasi", arch: :wasm32, os: :wasi, object_format: :wasm,
                               page: 65_536, symbol_prefix: "", ruby_platform: "wasm32-wasi",
                               link: nil, roads: %i[wasm]))

    # The target named `triple`, or nil.
    def self.fetch(triple) = REGISTRY[triple]

    def self.all = REGISTRY.values

    # This host as a triple: `aarch64-apple-darwin`, `aarch64-linux-musl`,
    # or what ruby says.
    def self.host_triple
      require "rbconfig"
      cpu = RbConfig::CONFIG["host_cpu"]
      os = RbConfig::CONFIG["host_os"]
      cpu = "aarch64" if cpu == "arm64"
      return "#{cpu}-apple-darwin" if os.start_with?("darwin")
      return "#{cpu}-linux-musl" if os.start_with?("linux-musl")

      "#{cpu}-#{os}"
    end

    # The target this host runs natively, or nil.
    def self.host = fetch(host_triple)

    # The target a build takes when none is named: the host's own, else
    # aarch64-apple-darwin.
    def self.default = host || AARCH64_DARWIN

    def native? = Target.host_triple == triple

    # The output `emit` names: `:native` for nil, else the symbol.
    def self.road(emit) = emit ? emit.to_sym : :native

    # Whether this host has the tools a native link for this target runs:
    # its C compiler and archiver, the host's own or a cross toolchain's.
    def linkable? = !tool("cc").nil? && !tool("ar").nil?

    # The command this host runs as the target's `name` ("cc" or "ar"), or
    # nil: on the target's own host the plain tool, elsewhere a cross
    # toolchain's, named by the triple as musl-cross and crosstool name
    # theirs (`aarch64-linux-musl-gcc`).
    def tool(name)
      names = native? ? [name] : [name, *CROSS_NAMES[name]].map { |base| "#{triple}-#{base}" }
      names.find { |command| Target.tool?(command) }
    end

    # What a cross toolchain may call a tool instead of its plain name.
    CROSS_NAMES = { "cc" => %w[gcc] }.freeze

    def self.tool?(name)
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
        path = File.join(dir, name)
        File.file?(path) && File.executable?(path)
      end
    end

    # nil when this host can build `emit` (nil for a native binary, "obj"
    # or "wasm") for this target, else the message a refusal prints.
    def refusal(emit)
      road = Target.road(emit)
      return "ze0 does not build #{road == :native ? "a native binary" : "--emit #{emit}"} for #{triple}" unless roads.include?(road)
      return nil unless road == :native
      return nil if linkable?

      if native?
        "a native binary needs cc and ar on the PATH (xcode-select --install); " \
          "--emit wasm and --emit obj work without them"
      else
        "a native binary for #{triple} needs a #{triple} host with cc, or #{triple}-gcc and #{triple}-ar " \
          "on the PATH; this host is #{Target.host_triple}; --emit obj works here"
      end
    end
  end
end
