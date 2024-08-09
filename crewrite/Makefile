CFLAGS ?= -g -DHAVE_SENDFILE
PREFIX ?= /usr/local
bascftp: bascftp.o crc.o
	gcc -o $@ $(CFLAGS) $(LDFLAGS) $^

check: check_environment tests

check_environment:
	./check_env.sh

tests: bascftp
	./test.sh

install: bascftp
	install -m 755 -D ./bascftp $(PREFIX)/bin/bashftp

uninstall:
	rm -f $(PREFIX)/bin/bashftp

clean:
	rm -rf *.o bascftp
