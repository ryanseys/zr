# rubygems' tar header parses and writes inside a Ractor, as
# test_gem_package_tar_header_ractor.rb checks: its tables are
# shareable, so a Ractor reads them.
require "rubygems/package"
require "stringio"

Warning[:experimental] = false
header = Gem::Package::TarHeader.new(name: "x", mode: 0o644, uid: 1000, gid: 10_000, size: 100, mtime: 12_345,
                                     typeflag: "0", linkname: "link", uname: "user", gname: "group",
                                     devmajor: 1, devminor: 2, prefix: "pre")
bytes = header.to_s

decoded = Ractor.new(bytes) { |str| Gem::Package::TarHeader.from(StringIO.new(str)) }.value
p decoded.name, decoded.size, decoded.mode, decoded.prefix, decoded == header

encoded = Ractor.new(bytes) { |str| Gem::Package::TarHeader.from(StringIO.new(str)).to_s }.value
p encoded == bytes, encoded.bytesize
