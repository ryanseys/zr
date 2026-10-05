# Dir.glob as dir.c: a brace with a slash in it is one part, a trailing
# backslash goes, and the other forms of test_dir's test_glob.
require "tmpdir"
require "fileutils"
Dir.mktmpdir do |root|
  ("a".."z").each { |f| Dir.mkdir(File.join(root, f)) if f.ord.odd?; FileUtils.touch(File.join(root, f)) unless f.ord.odd? }
  r = ->(x) { x.is_a?(Array) ? x.map { |s| s.sub(root, "R") } : x }
  p r[Dir.glob(File.join(root, "*"), File::FNM_DOTMATCH)]
  p r[Dir.glob([root, File.join(root, "*")])]
  p r[Dir.glob(File.join(root, "*/"))]
  p r[Dir.glob(root + "//a")]
  FileUtils.touch(File.join(root, "{}"))
  p r[Dir.glob(File.join(root, '{\{\},a}'))]
  p r[Dir.glob(File.join(root, "["))], r[Dir.glob(File.join(root, '[a-\\'))]
  p r[Dir.glob(File.join(root, 'a\\'))]
  p r[Dir.glob(File.join(root, '[abc/def]'))]
  File.write(File.join(root, "}}{}"), ""); File.write(File.join(root, "}}a"), "")
  p r[Dir.glob(File.join(root, '}}{\{\},a}'))]
  p r[Dir.glob(File.join(root, '{\}\}{\{\},a},b,c}'))]
  [-> { Dir.glob(root + "\0\0\0x") }, -> { Dir.glob(root, sort: 1) }, -> { Dir.glob([[root, "x"].join("\0")]) }].each do |l|
    l.call
  rescue => e
    p [e.class, e.message.sub(root, "R")]
  end
  Dir.chdir(root) do
    %w"c/dir_a c/dir_b c/dir_b/dir".each { |d| FileUtils.mkdir_p(d) }
    %w"c/dir_a/file c/dir_b/dir/file".each { |f| File.write(f, "") }
    p Dir.glob("**/{dir_a,dir_b/dir}/file")
  end
end
