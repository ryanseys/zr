# to_uid and to_gid: nil keeps an id, and anything else converts as
# NUM2UIDT, with to_int. Dir.for_fd takes its descriptor as NUM2INT.
class ToInt < BasicObject
  def initialize(v) = @v = v
  def to_int = @v
end

def t(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue Exception => e
  puts "#{label}: !#{e.class}: #{e.message[0, 100]}"
end

uid = Process.uid
gid = Process.gid
t("chown to_int") { File.chown(ToInt.new(uid), gid, __FILE__) }
t("chown nil") { [File.chown(nil, gid, __FILE__), File.chown(uid, nil, __FILE__, __FILE__), File.chown(nil, nil, __FILE__)] }
t("chown to_int group") { File.chown(uid, ToInt.new(gid), __FILE__) }
t("lchown") { [File.lchown(nil, gid, __FILE__), File.lchown(ToInt.new(uid), nil, __FILE__)] }
t("File#chown") { File.open(__FILE__) { |f| [f.chown(ToInt.new(uid), gid), f.chown(nil, gid), f.chown(uid, ToInt.new(gid))] } }
t("chown string") { File.chown("x", nil, __FILE__) }
t("chown float") { File.chown(uid.to_f, nil, __FILE__) }
t("dir for_fd") { d = Dir.new("."); x = Dir.for_fd(ToInt.new(d.fileno)).class; d.close; x }
t("dir for_fd string") { Dir.for_fd("x") }
