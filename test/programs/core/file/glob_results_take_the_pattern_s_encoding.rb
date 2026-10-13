# Dir.glob and Dir[] give each result in the pattern's encoding, the
# filesystem's for a US-ASCII pattern (push_glob). On darwin the pattern
# matches as UTF-8, so a pattern in another ASCII-compatible encoding
# with non-ASCII bytes finds the UTF-8 names on disk, and each result
# converts back to the pattern's encoding, or to default_internal.
require "tmpdir"

Dir.mktmpdir do |dir|
  Dir.chdir(dir) do
    File.write("file_one.ext", "")
    File.write("two.ext", "")

    pattern = "file_one.ext".encode(Encoding::EUC_JP)
    r = Dir.glob(pattern)
    p [r, r.first.encoding]
    r = Dir[pattern, "*.ext".encode("EUC-JP")]
    p [r, r.map(&:encoding)]
    p Dir.glob(["*.ext".encode("Windows-31J"), "*.ext".b]).map(&:encoding)
    p Dir.glob("*.ext".encode("Windows-31J")).map(&:encoding)
    p Dir.glob("*.ext".b).map(&:encoding)
    p Dir.glob("*.ext".encode("US-ASCII")).map(&:encoding).uniq == [Encoding.find("filesystem")]
    p Dir.glob("*.ext".encode("ISO-8859-1"), base: ".").map(&:encoding)
    p Dir.glob("{file_one,two}.ext".encode("EUC-JP")).map(&:encoding)
    begin
      Dir.glob("*.ext".encode("UTF-16LE"))
    rescue => e
      p e.class
    end

    dir_name = "dir_glob_\u{3042}"
    Dir.mkdir(dir_name)
    File.write(File.join(dir_name, "file.txt"), "")
    sjis = File.join(dir_name, "*.txt").encode(Encoding::Windows_31J)
    r = Dir.glob(sjis)
    p [r, r.map(&:encoding), r == [File.join(dir_name, "file.txt").encode(Encoding::Windows_31J)]]
    r = Dir[File.join(dir_name, "*.txt").encode("EUC-JP"), sjis]
    p [r.map(&:encoding), r.map(&:valid_encoding?)]
    r = Dir.glob(File.join(dir_name, "*.txt"))
    p [r, r.map(&:encoding)]
    # A name that the pattern's encoding cannot hold stays UTF-8.
    r = Dir.glob("dir_glob_*".encode("ISO-8859-1"))
    p [r, r.map(&:encoding)]

    # default_internal takes the place of the pattern's encoding.
    Encoding.default_internal = Encoding::EUC_JP
    p Dir.glob("*.ext").map(&:encoding).uniq
    p Dir.glob("*.ext".encode("Windows-31J")).map(&:encoding).uniq
    Encoding.default_internal = nil
  end
end
