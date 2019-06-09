ERLANG_PATH = $(shell erl -eval 'io:format("~s", [lists:concat([code:root_dir(), "/erts-", erlang:system_info(version), "/include"])])' -s init stop -noshell)

CFLAGS += -g -O3 -ansi -pedantic -Wall -Wextra -Wno-unused-parameter
CFLAGS += -I"$(ERLANG_PATH)"
CFLAGS += -Ic_src
CFLAGS += -std=gnu99
CFLAGS += -fPIC

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
	curl https://raw.githubusercontent.com/apple/foundationdb/6.1.8/fdbclient/vexillographer/fdb.options > priv/fdb.options
