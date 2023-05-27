ERLANG_PATH = $(shell erl -eval 'io:format("~s", [lists:concat([code:root_dir(), "/erts-", erlang:system_info(version), "/include"])])' -s init stop -noshell)

CFLAGS += -g -O3 -ansi -pedantic -Wall -Wextra -Wno-unused-parameter
CFLAGS += -I"$(ERLANG_PATH)"
CFLAGS += -Ic_src
CFLAGS += -std=gnu99
CFLAGS += -fPIC

FDB_VERSION = 7.1.5

LDFLAGS += -L/usr/local/lib/ -L/usr/lib/

ifeq ($(shell uname),Linux)
	LDFLAGS += -Wl,--no-as-needed
	LDFLAGS += -lm -lpthread -lrt
endif

ifeq ($(shell uname),Darwin)
	LDFLAGS += -dynamiclib -undefined dynamic_lookup
endif

LDFLAGS += -lfdb_c

LIB_NAME = priv/fdb_nif.so

all: $(LIB_NAME)

$(LIB_NAME): c_src/fdb_nif.c
	$(CC) $(CFLAGS) -shared $(LDFLAGS) -o $@ c_src/fdb_nif.c

clean:
	rm  -rf $(LIB_NAME)*

update-options:
	curl https://raw.githubusercontent.com/apple/foundationdb/$(FDB_VERSION)/fdbclient/vexillographer/fdb.options > priv/fdb.options

start-server:
	fdbserver -p 127.0.0.1:4500 -d data/data/ -L data/logs/

fetch-foundation-source:
	rm -rf foundationdb
	curl -L "https://github.com/apple/foundationdb/archive/$(FDB_VERSION).tar.gz" > foundation.tar.gz
	tar -xf foundation.tar.gz
	rm foundation.tar.gz
	mv foundationdb-$(FDB_VERSION) foundationdb
	cd foundationdb && sed "s:USER_SITE_PATH:$(python3 -m site --user-site):g" ../test/foundationdb.patch | patch -p1

install-foundationdb-pip:
	pip3 install --user -Iv foundationdb==$(FDB_VERSION)
	pip3 show foundationdb

run-bindings-test:
	./test/loop.sh

