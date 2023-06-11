PREFIX ?= /usr/local

check:
	./test.sh

install:
	install -m 755 -D bashftp.sh $(PREFIX)/bin/bashftp

uninstall:
	rm -f $(PREFIX)/bin/bashftp
