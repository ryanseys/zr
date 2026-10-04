# With inplace_mode (ruby's -i), ARGF edits each file in place: the file
# moves to its backup name, or goes when the mode is "", and $stdout
# writes a new file of its name with the old file's mode. Standard input
# cannot be edited, so it is skipped with a warning.
require "tmpdir"

Dir.mktmpdir do |dir|
  a = File.join(dir, "a.txt")
  b = File.join(dir, "b.txt")
  File.write(a, "one\ntwo\n")
  File.write(b, "three\n")
  File.chmod(0o640, b)
  p ARGF.inplace_mode
  ARGF.inplace_mode = ".bak"
  p ARGF.inplace_mode
  ARGV.replace([a, b])
  while (line = gets)
    print line.upcase
    ARGF.write("#{ARGF.lineno}\n") if ARGF.file.eof?
  end
  $stdout.close
  $stdout = STDOUT
  p [File.read(a), File.read("#{a}.bak"), File.read(b), File.read("#{b}.bak")]
  p (File.stat(b).mode & 0o777).to_s(8)

  ARGF.inplace_mode = ""
  p ARGF.inplace_mode
  ARGV.replace([a])
  print gets.reverse while ARGF.file.is_a?(File) && !ARGF.file.eof?
  $stdout.close
  $stdout = STDOUT
  p [File.read(a), Dir.children(dir).sort]

  ARGF.inplace_mode = nil
  p ARGF.inplace_mode
  begin
    ARGF.inplace_mode = 1
  rescue TypeError => e
    p e
  end
end
