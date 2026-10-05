$0 = "rbx"
p $0
$0 = "a-longer-title-than-before"
p $0
p Process.setproctitle("title") == "title"
