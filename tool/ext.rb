# frozen_string_literal: true

require_relative "lib/zr/dev"
require_relative "../lib/zr/ext/capi"

module Zr
  module Dev
    # Tools for C extensions.
    class ExtTools < Group
      summary "Tools for C extensions"

      # Lists what a C extension takes from ruby, against zr's C API.
      #
      #   zr-dev ext imports path/to/msgpack.bundle
      #   zr-dev ext imports --all a.bundle b.o
      #
      # Each argument is a bundle or an object file. The tool prints its
      # ruby imports that the C API lacks (kernel/capi/*.rb), one a line,
      # after a count; `--all` prints every import, `+` for those that the
      # C API has and `-` for the others. It fails when one is missing,
      # as a build of the extension would.
      class Imports < Command
        summary "List a C extension's ruby imports that zr's C API lacks"
        usage "[--all] <bundle-or-object>..."

        def defaults = @all = false

        def options(o) = o.on("--all", "list every import, with + or -") { @all = true }

        def run(argv)
          fail!("give the path of a bundle or an object file") if argv.empty?

          argv.map { |path| complete?(path) }.all?
        end

        # Prints the imports of the file at `path`; whether the C API has
        # them all.
        def complete?(path)
          fail!("#{path}: no such file") unless File.file?(path)

          imports = Zr::Ext::CApi.imports(path).uniq.sort
          missing = Zr::Ext::CApi.missing(imports)
          puts "#{path}: #{imports.size} ruby imports, #{missing.size} not in zr's C API"
          (@all ? imports : missing).each { |name| puts "  #{mark(name, missing)}#{name}" }
          missing.empty?
        end

        # `+ ` or `- ` before each import under --all.
        def mark(name, missing)
          return "" unless @all

          missing.include?(name) ? "- " : "+ "
        end
      end

      commands("imports" => ["List a C extension's ruby imports that zr's C API lacks", -> { Imports }])
    end
  end
end
