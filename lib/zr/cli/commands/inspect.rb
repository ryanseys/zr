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
          print Gems.table(manifest["gems"].map { |row| Manifest::Row.new(row["name"], row["version"], row["source"]) })
        end
      end
    end
  end
end
