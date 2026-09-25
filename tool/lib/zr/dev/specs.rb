# frozen_string_literal: true

module Zr
  module Dev
    # Every spec file under `path`, which may be one file or a directory,
    # relative to the root. The spec tools and the oracle read them with
    # `Zr::Reader`, which compiles and runs nothing.
    def self.spec_files(path)
      full = File.expand_path(path, ROOT)
      File.directory?(full) ? Dir[File.join(full, "**/*_test.rb")].sort : [full]
    end

    # Loads the reader. The spec tools need it, and `zr-dev help` does not.
    def self.reader!
      require "digest"
      require_relative "../../../../test/support/reader"
    end
  end
end
