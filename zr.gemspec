# frozen_string_literal: true

require_relative "lib/zr/version"

Gem::Specification.new do |spec|
  spec.name = "zr"
  spec.version = Zr::VERSION
  spec.authors = ["Ryan Seys"]
  spec.email = ["ryan@ryanseys.com"]

  spec.summary = "A Ruby compiler, written in Ruby: its programs print what ruby prints, or zr refuses them by name"
  spec.description = <<~TEXT
    zr compiles Ruby programs to native binaries for macOS (Apple Silicon)
    and WASI modules on any host, and to Linux (aarch64 and x86_64)
    binaries with a C toolchain. A compiled program gives the output of ruby
    #{Zr::RUBY_PIN}, the Ruby 4 release that zr targets, or zr refuses it at
    build time. The compiler and the runtime are Ruby, with no C. zr
    carries ruby's standard library itself, so the gem depends on nothing.
  TEXT
  spec.homepage = "https://github.com/ryanseys/zr"
  # zr's own code is MIT. The gem also carries code under each of the
  # other licenses, all at once (not a choice between them):
  # THIRD_PARTY_NOTICES.md names the part that each one covers.
  spec.licenses = ["MIT", "Ruby", "BSD-2-Clause", "BSD-3-Clause", "Zlib", "Apache-2.0", "BSL-1.0", "Unicode-3.0", "CC0-1.0"]
  # Ruby 4 or later. zr carries its own standard library (vendor/ruby), so
  # the host ruby only runs the compiler. zr warns on a ruby of another
  # series than the one that it checks its output against (.ruby-version).
  spec.required_ruby_version = ">= #{Zr::RUBY_MINIMUM}"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    # The docs and the changelog of this version, at its tag.
    "documentation_uri" => "#{spec.homepage}/tree/v#{Zr::VERSION}/docs",
    "changelog_uri" => "#{spec.homepage}/blob/v#{Zr::VERSION}/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  # The compiler, its runtime and the vendored library (vendor/ruby, as
  # upstream ships it), and each target's ruby headers and rbconfig.rb for
  # C extensions (vendor/targets). vendor/src holds only what the tools
  # read. The
  # tests and the tasks stay in the repository.
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL, &:read).split("\x0").select do |file|
    file.match?(%r{\A(exe|lib|licenses|vendor/(ruby|LICENSES|targets))/}) || file == "vendor/vendor.lock" ||
      %w[LICENSE.txt THIRD_PARTY_NOTICES.md README.md CHANGELOG.md].include?(file)
  end
  # Outside a git checkout, the list is empty, and so would the gem be.
  raise "zr.gemspec: `git ls-files` listed no files; build the gem in a git checkout" if spec.files.empty?

  # A platform gem (ZR_GEM_PLATFORM, from Target#gem_platform) also
  # carries its host's built runtime: the bundle of ZR_GEM_RUNTIME,
  # unpacked at data/runtime/<triple> (lib/zr/prebuilt.rb, `bundled`), so
  # its first build builds no runtime. Without them, this is the `ruby`
  # gem, which builds the runtime on its first use, or fetches it.
  if (platform = ENV.fetch("ZR_GEM_PLATFORM", "")) != ""
    runtime = ENV.fetch("ZR_GEM_RUNTIME", "")
    unless runtime.match?(%r{\Adata/runtime/[\w.-]+\z}) && File.file?(File.join(__dir__, runtime, "manifest.json"))
      raise "zr.gemspec: ZR_GEM_PLATFORM needs ZR_GEM_RUNTIME, an unpacked bundle at data/runtime/<triple>"
    end

    spec.platform = platform
    spec.files += Dir.glob("#{runtime}/**/*", base: __dir__).select { |file| File.file?(File.join(__dir__, file)) }.sort
    # The libc in the platform's name (aarch64-linux-gnu, -musl).
    spec.required_rubygems_version = ">= 3.3.22"
  end

  spec.bindir = "exe"
  spec.executables = ["zr"]
  # Only lib/: lib/zr/runtime/ and vendor/ hold files named like ruby's
  # own libraries (rbconfig, set, json), below lib/zr, so they never
  # shadow them.
  spec.require_paths = ["lib"]

  # No runtime dependencies: a program's library is vendor/ruby and
  # lib/zr/runtime/ext, which zr compiles into the program.
end
