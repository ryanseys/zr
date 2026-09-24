# frozen_string_literal: true

module Zr
  # A target that zr emits code for: its instruction set, its OS, its
  # object format, and the facts that a build reads from them. The gem
  # runs on any host. A target tells what it builds, and `refusal` tells
  # whether this host can build it.
  class Target
    attr_reader :triple, :arch, :os, :libc, :object_format, :word, :page, :symbol_prefix, :ruby_platform, :link, :outputs

    # `outputs` are the outputs zr can build for the target: `:native`
    # (a binary), `:obj` (an object) and `:wasm` (a module).
    def initialize(triple:, arch:, os:, object_format:, page:, symbol_prefix:, ruby_platform:, link:, outputs:, libc: nil, word: 8)
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
      @outputs = outputs
    end

    def to_s = triple

    # The runtime layer that zr lowers with for each OS. runtime/kernel/os/,
    # runtime/core/os/ and runtime/ext/os/ each contain one directory per layer.
    OS_LAYERS = { darwin: "darwin", linux: "linux", wasi: "wasi" }.freeze
    # The machine layer, under runtime/kernel/arch/.
    ARCH_LAYERS = { aarch64: "aarch64", wasm32: "wasm32" }.freeze

    def os_layer = OS_LAYERS.fetch(os)
    def arch_layer = ARCH_LAYERS.fetch(arch)

    REGISTRY = {}

    def self.register(target)
      REGISTRY[target.triple] = target
    end

    AARCH64_DARWIN = register(new(triple: "aarch64-apple-darwin", arch: :aarch64, os: :darwin, object_format: :macho,
                                  page: 16_384, symbol_prefix: "_", ruby_platform: "arm64-darwin23",
                                  link: :darwin, outputs: %i[native obj]))
    AARCH64_LINUX_MUSL = register(new(triple: "aarch64-linux-musl", arch: :aarch64, os: :linux, libc: :musl,
                                      object_format: :elf, page: 4096, symbol_prefix: "", ruby_platform: "aarch64-linux-musl",
                                      link: :static, outputs: %i[native obj]))
    WASM32_WASI = register(new(triple: "wasm32-wasi", arch: :wasm32, os: :wasi, object_format: :wasm,
                               page: 65_536, symbol_prefix: "", ruby_platform: "wasm32-wasi",
                               link: nil, outputs: %i[wasm]))

    # The target with this `triple`, or nil.
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

    # The target of a build that gives no target: the host's own, else
    # aarch64-apple-darwin.
    def self.default = host || AARCH64_DARWIN

    def native? = Target.host_triple == triple

    # Whether a program for this target can write machine code into
    # itself while it runs. Eval support does this. A wasm module's code
    # is fixed when the engine instantiates it, and WASI gives a guest no
    # way to make a second module. So there, eval uses the tree-walking
    # interpreter (lib/zr/eval/walk.rb).
    def jits? = arch != :wasm32

    # The output for `emit`: `:native` for nil, else the symbol.
    def self.output(emit) = emit ? emit.to_sym : :native

    # Whether this host can link a binary for this target. zr's own
    # Mach-O linker needs no tool on any host, unless `ZR_LINKER=cc`
    # selects the system linker. All other links run the target's C
    # compiler driver: the host's own or a cross toolchain's.
    def linkable?
      return true if link == :darwin && ENV["ZR_LINKER"] != "cc"

      !tool("cc").nil?
    end

    # The command that this host runs for the target's tool `name`
    # ("cc"), or nil. On the target's own host, it is the plain tool.
    # On other hosts, it is a cross toolchain's tool, prefixed with the
    # triple as musl-cross and crosstool do (`aarch64-linux-musl-gcc`).
    def tool(name)
      names = native? ? [name] : [name, *CROSS_NAMES[name]].map { |base| "#{triple}-#{base}" }
      names.find { |command| Target.tool?(command) }
    end

    # Other names that a cross toolchain can use for a tool.
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
      output = Target.output(emit)
      return "zr does not build #{output == :native ? "a native binary" : "--emit #{emit}"} for #{triple}" unless outputs.include?(output)
      return nil unless output == :native
      return nil if linkable?

      if native?
        "a native binary needs cc on the PATH (xcode-select --install); " \
          "--emit wasm and --emit obj work without them"
      else
        "a native binary for #{triple} needs a #{triple} host with cc, or #{triple}-gcc " \
          "on the PATH; this host is #{Target.host_triple}; --emit obj works here"
      end
    end
  end
end
