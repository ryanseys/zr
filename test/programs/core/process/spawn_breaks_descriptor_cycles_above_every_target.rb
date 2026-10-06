# Redirects that form a cycle go through a copy whose number is above
# every descriptor that the redirects name, closed in the program that
# the child runs.
require "tmpdir"

Dir.chdir(Dir.mktmpdir) do
  # stdout and a file swap, while many other descriptors take stdout.
  [[], [4], (4..30).to_a].each do |others|
    File.open("out", "w") do |f|
      h = { STDOUT => f, f => STDOUT }
      others.each { |fd| h[fd] = STDOUT unless fd == f.fileno }
      Process.wait spawn("echo", "swap", h)
    end
    p [others.size, File.read("out")]
  end

  # Three descriptors in a ring: each child descriptor names the next.
  a, b, c = %w[a b c].map { |name| File.open(name, "w") }
  script = "[#{a.fileno}, #{b.fileno}, #{c.fileno}].each { |fd| IO.new(fd, 'w').print fd }"
  Process.wait spawn("ruby", "-e", script, a => b, b => c, c => a)
  fds = [a, b, c].map(&:fileno)
  [a, b, c].each(&:close)
  # The child wrote its descriptor a into b, b into c and c into a.
  p fds.zip(%w[b c a]).map { |fd, name| File.read(name) == fd.to_s }

  # The copy stays out of the program the child runs.
  File.open("out", "w") do |f|
    script = "print (#{f.fileno + 1}..64).select { |fd| IO.for_fd(fd, autoclose: false) rescue nil }"
    Process.wait spawn("ruby", "-e", script, STDOUT => f, f => STDOUT, 2 => File::NULL)
  end
  p File.read("out")
end
