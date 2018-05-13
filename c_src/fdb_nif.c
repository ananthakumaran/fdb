#define FDB_API_VERSION 510

#include "erl_nif.h"
#include "foundationdb/fdb_c.h"

static ERL_NIF_TERM
get_max_api_version(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  return enif_make_int(env, fdb_get_max_api_version());
}

static ErlNifFunc nif_funcs[] = {
  {"get_max_api_version", 0, get_max_api_version}
};

ERL_NIF_INIT(Elixir.FDB.Raw, nif_funcs, NULL, NULL, NULL, NULL);
