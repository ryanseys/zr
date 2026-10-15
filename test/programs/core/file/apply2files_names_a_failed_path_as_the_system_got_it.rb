# File.delete, chmod and the other apply2files methods give the system
# each path in UTF-8 (rb_str_encode_ospath), and an error names the path
# so. File.open names the path as it was given.
require "tmpdir"

Dir.mktmpdir do |dir|
  Dir.chdir(dir) do
    paths = ["\u{30eb}d".encode("EUC-JP"), "café".encode("ISO-8859-1"), "\xff".b, "ok"]
    paths.each do |name|
      [-> { File.delete(File.join(name, "f")) }, -> { File.chmod(0o644, File.join(name, "g")) }].each do |code|
        code.call
      rescue SystemCallError => e
        p [e.message, e.message.encoding]
      end
    end
    File.write("é".encode("ISO-8859-1"), "x")
    p File.delete("é".encode("ISO-8859-1")), Dir.children(".")
    begin
      File.open("\u{30eb}".encode("Shift_JIS"))
    rescue SystemCallError => e
      p [e.message, e.message.encoding]
    end
  end
end
