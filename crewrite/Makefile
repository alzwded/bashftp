CFLAGS ?= -O2 -Wall
PREFIX ?= /usr/local
OBJS = bascftp.o crc.o
bascftp: $(OBJS)
	$(CC) -o $@ $(CFLAGS) $(LDFLAGS) $(OBJS)

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
