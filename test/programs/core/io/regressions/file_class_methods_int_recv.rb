# `File.readable?` and `File.binwrite`, plus `Array#pack("C*")`
# on an Integer array, which is the inverse of `String#bytes`.
#
# The shape comes from optcarrot's battery-save code path:
#   `return unless File.readable?(sav)` and
#   `File.binwrite(sav, @wrk.pack("C*"))`.
#
# The test uses a cwd-relative path so that zr and the CRuby
# reference resolve the same place. `/tmp/...` can land in different
# directories on the two sides (see bundle_io_sys.rb).

path = "spinel_file_class_test"

File.binwrite(path, [72, 105, 33].pack("C*"))   # "Hi!"
puts File.readable?(path)
puts File.read(path)
File.delete(path)
puts File.exist?(path)
