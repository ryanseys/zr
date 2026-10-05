# Process.groups lists every group, past the 16 that a plain getgroups
# gives on macOS.
groups = Process.groups
p groups.all?(Integer)
p groups.uniq.sort == `id -G`.split.map(&:to_i).uniq.sort
