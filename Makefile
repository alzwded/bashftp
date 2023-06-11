PREFIX ?= /usr/local

check: check_environment tests

check_environment:
	./check_env.sh

tests:
	./test.sh

install:
	install -m 755 -D bashftp.sh $(PREFIX)/bin/bashftp

uninstall:
	rm -f $(PREFIX)/bin/bashftp
