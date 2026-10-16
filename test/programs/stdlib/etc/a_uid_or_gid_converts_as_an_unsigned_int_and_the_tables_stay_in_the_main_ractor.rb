require "etc"

# etc.c reads a uid or a gid through NUM2UINT: up to 2**32 - 1, and a
# negative one down to INT_MIN names the same id as its unsigned twin.
def row(reader, id)
  Etc.public_send(reader, id).then { |r| reader == :getpwuid ? r.uid : r.gid }
rescue ArgumentError
  :none
end

%i[getpwuid getgrgid].each do |reader|
  p [reader, row(reader, -2) == row(reader, 2**32 - 2)]
  p [reader, row(reader, 0) == row(reader, 0.9)]
  [2**32, -2**31 - 1, 2**63, -2**63, 2**64 - 1, 2**64, -2**64, 1e20, -1e20, Float::NAN, "0", nil, :x].each do |bad|
    Etc.public_send(reader, bad)
  rescue => e
    p [reader, bad, e.class, e.message]
  end
end
p Etc.getpwuid(Process.uid).uid == Process.uid
p Etc.getgrgid(Process.gid).gid == Process.gid

# The readers of the user and group tables, and sysconfdir, raise in any
# Ractor but main; the rest of the module runs there.
Warning[:experimental] = false
unsafe = %i[getlogin getpwuid getpwnam setpwent endpwent getpwent passwd
  getgrgid getgrnam group setgrent endgrent getgrent sysconfdir]
args = { getpwnam: ["root"], getgrnam: ["wheel"] }
got = Ractor.new(unsafe, args) do |names, given|
  names.map do |name|
    Etc.public_send(name, *given.fetch(name, []))
    [name, :ran]
  rescue Ractor::UnsafeError => e
    [name, e.class, e.message, e.backtrace_locations.first.label]
  end
end.value
got.each { p _1 }
p Ractor.new { [Etc.nprocessors.class, Etc.uname.class, Etc.systmpdir.class, Etc.sysconf(Etc::SC_PAGESIZE).class] }.value
p Ractor.new { Etc::Passwd.each { break } }.value rescue p $!.class
p Ractor.new { Etc::Group.each { break } rescue $!.class }.value
p Ractor.new { Etc::Passwd.each rescue $!.class }.value
