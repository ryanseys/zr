# frozen_string_literal: true

require_relative "../command"
require_relative "gems"

module Zr
  module CLI
    module Commands
      # `zr inspect [--json] BINARY`: the gem manifest that a binary carries.
      class Inspect < Command
        #: (Array[String] argv) -> void
        def run(argv)
          require "json"
          require_relative "../../manifest"
          json = !argv.delete("--json").nil?
          usage_error("unknown option '#{argv.find { |word| word.start_with?("-") }}'") if argv.any? { |word| word.start_with?("-") }
          usage_error("give one binary") unless argv.size == 1
          path = argv.first
          Errors.file!(path)
          manifest = Manifest.find(File.binread(path))
          abort "zr: #{path} has no gem manifest; zr #{VERSION} did not build it" unless manifest
          return puts(JSON.generate(manifest)) if json

          puts "#{path}: zr #{manifest["zr"]}, ruby #{manifest["ruby"]}, #{manifest["target"]}"
          glibc = Inspect.glibc(path)
          puts "needs glibc #{glibc} or newer" if glibc
          print Gems.table(manifest["gems"].map { |row| Manifest::Row.new(row["name"], row["version"], row["source"]) })
        end

        # The newest glibc version that the ELF binary at `path` needs, or
        # nil for another binary.
        #: (String path) -> String?
        def self.glibc(path)
          require_relative "../../obj/elf/image"
          bytes = File.binread(path)
          Obj::Elf::Image.elf?(bytes) ? Obj::Elf::Image.read(bytes).glibc : nil
        end
      end
    end
  end
end
