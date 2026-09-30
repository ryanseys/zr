# glob walks depth first and sorts each directory's names, and shows "."
# only in the first directory it reads.
require "tmpdir"
require "fileutils"
Dir.mktmpdir do |d|
  Dir.chdir(d) do
    %w[a/x a-b a.c A2 b/B/c .hid/q Z sub/.d sub/deep/e].each { |n| FileUtils.mkdir_p(File.dirname(n)); File.write(n, "") }
    p Dir.glob("**/*")
    p Dir.glob("**/*", File::FNM_DOTMATCH)
    p Dir.glob("sub/**/*", File::FNM_DOTMATCH), Dir.glob("*/*", File::FNM_DOTMATCH)
    p Dir.glob("**/.*"), Dir.glob("**/"), Dir.glob("sub/**/"), Dir.glob("sub/"), Dir.glob("sub//deep")
  end
end
