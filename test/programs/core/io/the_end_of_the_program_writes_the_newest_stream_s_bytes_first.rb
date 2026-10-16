# At the end, ruby's finalizers write each stream's buffered bytes, the
# newest stream first: each freed stream goes on the head of CRuby's
# zombie list. Streams that share one file show that order.
require "tmpdir"

runs = {
  "a, b, c" => ->(a, b, c) { a.write 1; b.write 2; c.write 3 },
  "c, b, a" => ->(a, b, c) { c.write 3; b.write 2; a.write 1 },
  "b, a, a dup of c, c" => ->(a, b, c) { b.write 2; a.write 1; c.dup.write 4; c.write 3 },
  "a, STDOUT, STDERR, b, both reopened onto c" => lambda do |a, b, c|
    $stdout.reopen(c)
    $stderr.reopen(c)
    a.write 1
    $stdout.write "o"
    $stderr.write "e"
    b.write 2
  end,
}

Dir.mktmpdir do |dir|
  path = File.join(dir, "out")
  runs.each do |name, run|
    File.write(path, "")
    pid = fork do
      run.call(*Array.new(3) { File.open(path, "a") })
      exit
    end
    Process.wait(pid)
    puts "#{name} => #{File.read(path)}"
  end
end
