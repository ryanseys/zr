# frozen_string_literal: true

require_relative "lib/zr/version"

Gem::Specification.new do |spec|
  spec.name = "zr"
  spec.version = Zr::VERSION
  spec.authors = ["Ryan Seys"]
  spec.email = ["ryan@ryanseys.com"]

  spec.summary = "A Ruby compiler, written in Ruby: its programs give ruby 4.0.7's output, or zr refuses them by name"
  spec.description = <<~TEXT
    zr compiles Ruby programs to native aarch64-apple-darwin binaries and
    WASI modules on any host, and to static aarch64-linux-musl binaries
    with a musl toolchain. A compiled program gives ruby 4.0.7's output,
    or zr refuses it at build time. The compiler and the runtime are Ruby,
    with no C. zr carries ruby's standard library itself, so the gem
    depends on nothing.
  TEXT
  spec.homepage = "https://github.com/ryanseys/zr"
  spec.license = "MIT" # the vendored parts: THIRD_PARTY_NOTICES.md
  # The ruby that zr checks its output against (.ruby-version), or a later
  # 4.0 release. zr carries its own standard library (stdlib/), so the
  # host ruby only runs the compiler. zr warns on any ruby but Zr::RUBY.
  spec.required_ruby_version = [">= #{Zr::RUBY}", "< 4.1"]

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    # The docs and the changelog of this version, at its tag.
    "documentation_uri" => "#{spec.homepage}/tree/v#{Zr::VERSION}/docs",
    "changelog_uri" => "#{spec.homepage}/blob/v#{Zr::VERSION}/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  # The compiler, its runtime, its standard library and the vendored
  # sources. The tests and the tasks stay in the repository.
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL, &:read).split("\x0").select do |file|
    file.match?(%r{\A(exe|lib|licenses|runtime|stdlib|vendor/(ext|prelude))/}) ||
      %w[LICENSE.txt THIRD_PARTY_NOTICES.md README.md CHANGELOG.md].include?(file)
  end
  # Outside a git checkout, the list is empty, and so would the gem be.
  raise "zr.gemspec: `git ls-files` listed no files; build the gem in a git checkout" if spec.files.empty?

  spec.bindir = "exe"
  spec.executables = ["zr"]
  # Only lib/: runtime/, stdlib/ and vendor/ hold files named like ruby's
  # own libraries (rbconfig, set, json), and must never shadow them.
  spec.require_paths = ["lib"]

  # No runtime dependencies: a program's library is stdlib/ and
  # vendor/ext, which zr compiles into the program.
end
