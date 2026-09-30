# Braces expand without deduplication, and one that never closes gives
# nothing. A macOS volume matches names without their case, and a plain
# name reads its real case back.
require "tmpdir"
Dir.mktmpdir do |d|
  Dir.chdir(d) do
    %w[a b sub].each { |n| File.write(n, "") }
    File.write("x}y", "")
    File.write("{a}", "")
    p Dir.glob("{a,a}"), Dir.glob("{b,a}"), Dir.glob("{a,b"), Dir.glob("x}y"), Dir.glob("\\{a}"), Dir.glob("{a\\,b}")
    p Dir.glob("A"), Dir.glob("S*"), Dir.glob("A", File::FNM_CASEFOLD)
  end
end
