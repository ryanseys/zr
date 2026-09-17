# Changelog

## 0.1.0 (unreleased)

The first release as a RubyGem.

- `gem install ze0` installs the `ze0` command: `run`, `build`, `machine`,
  `targets` and `version`. The older `ze0 zr run|build|machine` names
  still work.
- The gem installs on any host. An Apple Silicon Mac with `cc` builds
  native `aarch64-apple-darwin` binaries; every host builds WASI modules
  and Mach-O objects. A native build this host cannot link exits with
  status 3 and says why.
- ze0 has no C. prism 1.9.0 parses through its Ruby half over a Ruby
  port of its C (`rt/ext/prism/ruby`), on the host and in every binary;
  zlib is a port of zlib 1.3.1 in the kernel dialect, and `Regexp` a port
  of Onigmo, CRuby 4.0.6's engine, in Ruby. All of them work on wasm, and
  the install compiles nothing.
- The runtime cache goes to the user's cache directory
  (`~/Library/Caches/ze0` on macOS), or to `ZE0_CACHE`.
- `cc` runs with `DEVELOPER_DIR` and `SDKROOT` pinned to the
  install the SDK comes from, so ze0 links with the macOS 27.0 SDK when
  the selected Xcode is older than the Command Line Tools.
- `Obj::Exe` decides what libSystem defines from a committed list, so a
  link answers the same on every host.
- MIT License; `THIRD_PARTY_NOTICES.md` names every vendored part.
