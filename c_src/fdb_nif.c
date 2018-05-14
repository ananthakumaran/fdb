#define FDB_API_VERSION 510

#include "stdio.h"
#include "string.h"
#include "erl_nif.h"
#include "foundationdb/fdb_c.h"

#define verify_argv(A, M) if(!(A)) { ERL_NIF_TERM reason = string_to_binary(env, "Invalid argument: " M); return enif_raise_exception(env, reason); }

#ifdef FDB_DEBUG
#define DEBUG_LOG(string) fprintf(stderr, "%s\n", string)
#else
#define DEBUG_LOG(string)
#endif

static ERL_NIF_TERM
string_to_binary(ErlNifEnv *env, const char *string) {
  ErlNifBinary *binary = enif_alloc(sizeof(ErlNifBinary));

  enif_alloc_binary(strlen(string), binary);
  memcpy(binary->data, string, strlen(string));
  return enif_make_binary(env, binary);
}

static ERL_NIF_TERM
get_max_api_version(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  return enif_make_int(env, fdb_get_max_api_version());
}

static ERL_NIF_TERM
select_api_version_impl(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  int runtime_version;
  int header_version;
  fdb_error_t result;

  verify_argv(enif_get_int(env, argv[0], &runtime_version), "runtime_version");
  verify_argv(enif_get_int(env, argv[1], &header_version), "header_version");

  result = fdb_select_api_version_impl(runtime_version, header_version);
  return enif_make_int(env, result);
}

static ERL_NIF_TERM
setup_network(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  return enif_make_int(env, fdb_setup_network());
}

static void *
run_network_wrapper(void *argv) {
  fdb_run_network();
  return NULL;
}

static ErlNifTid *fdb_network_tid = NULL;

static ERL_NIF_TERM
run_network(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  char *name = "fdb";
  fdb_network_tid = enif_alloc(sizeof(ErlNifTid));
  return enif_make_int(env, enif_thread_create(name, fdb_network_tid, &run_network_wrapper, NULL, NULL));
}

static ERL_NIF_TERM
stop_network(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  int result = fdb_stop_network();
  if(!result) {
    return enif_make_int(env, result);
  }
  return enif_make_int(env, enif_thread_join(*fdb_network_tid, NULL));
}

static ERL_NIF_TERM
get_error(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  int code;
  verify_argv(enif_get_int(env, argv[0], &code), "code");
  return string_to_binary(env, fdb_get_error(code));
}

typedef enum {
  CLUSTER,
  DATABASE
} FutureType;

static ErlNifResourceType *FUTURE_RESOURCE_TYPE;
typedef struct {
  FDBFuture* handle;
  FutureType type;
} Future;

static void
future_destroy(ErlNifEnv *env, void *object) {
  Future *future = (Future*) object;
  fdb_future_destroy(future->handle);
}

static ERL_NIF_TERM
fdb_future_to_future(ErlNifEnv *env, FDBFuture *fdb_future, FutureType type) {
  ERL_NIF_TERM term;
  Future *future = enif_alloc_resource(FUTURE_RESOURCE_TYPE, sizeof(Future));
  future->handle = fdb_future;
  future->type = type;
  term = enif_make_resource(env, future);
  enif_release_resource(future);
  return term;
}

static ErlNifResourceType *CLUSTER_RESOURCE_TYPE;
typedef struct {
  FDBCluster* handle;
} Cluster;

static void
cluster_destroy(ErlNifEnv *env, void *object) {
  Cluster *cluster = (Cluster*) object;
  fdb_cluster_destroy(cluster->handle);
}

static ERL_NIF_TERM
fdb_cluster_to_cluster(ErlNifEnv *env, FDBCluster *fdb_cluster) {
  ERL_NIF_TERM term;
  Cluster *cluster = enif_alloc_resource(CLUSTER_RESOURCE_TYPE, sizeof(Cluster));
  cluster->handle = fdb_cluster;
  term = enif_make_resource(env, cluster);
  enif_release_resource(cluster);
  return term;
}


static ERL_NIF_TERM
future_get(ErlNifEnv *env, Future *future) {

  switch(future->type) {
  case CLUSTER:
    {
      FDBCluster *cluster;
      fdb_future_get_cluster(future->handle, &cluster);
      return fdb_cluster_to_cluster(env, cluster);
    }
  case DATABASE:
    return NULL;
  }
}


typedef struct {
  ErlNifPid *pid;
  Future *future;
} FutureCallbackArgv;

static void
future_callback(FDBFuture *fdb_future, void *argv) {
  FutureCallbackArgv *callback_arg = (FutureCallbackArgv *)argv;
  ERL_NIF_TERM msg;
  int result;
  DEBUG_LOG("Callback");

  ErlNifEnv *msg_env = enif_alloc_env();
  msg = future_get(msg_env, callback_arg->future);
  result = enif_send(NULL, callback_arg->pid, msg_env, msg);
  if (!result) {
    fprintf(stderr, "send failed\n");
  }

  enif_release_resource(callback_arg->future);
  enif_free(callback_arg->pid);
  enif_free_env(msg_env);
  enif_free(callback_arg);
}

static ERL_NIF_TERM
future_resolve(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  Future *future;
  FutureCallbackArgv *callback_arg;
  fdb_error_t result;

  DEBUG_LOG("Resolve");

  verify_argv(enif_get_resource(env, argv[0], FUTURE_RESOURCE_TYPE, (void **)&future), "future");
  callback_arg = enif_alloc(sizeof(FutureCallbackArgv));
  callback_arg->pid = enif_alloc(sizeof(ErlNifPid));
  enif_keep_resource(future);
  callback_arg->future = future;
  enif_self(env, callback_arg->pid);
  result = fdb_future_set_callback(future->handle, future_callback, callback_arg);
  return enif_make_int(env, result);
}


static ERL_NIF_TERM
create_cluster(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  FDBFuture *fdb_future = fdb_create_cluster(NULL);
  return fdb_future_to_future(env, fdb_future, CLUSTER);
}

int
load(ErlNifEnv *env, void **priv_data, ERL_NIF_TERM load_info) {
  int flags = ERL_NIF_RT_CREATE | ERL_NIF_RT_TAKEOVER;
  FUTURE_RESOURCE_TYPE = enif_open_resource_type(env, "fdb", "Future", future_destroy, flags, NULL);
  if(FUTURE_RESOURCE_TYPE == NULL) return -1;
  CLUSTER_RESOURCE_TYPE = enif_open_resource_type(env, "fdb", "Cluster", cluster_destroy, flags, NULL);
  if(CLUSTER_RESOURCE_TYPE == NULL) return -1;
  return 0;
}

static ErlNifFunc nif_funcs[] = {
  {"get_max_api_version", 0, get_max_api_version, 0},
  {"select_api_version_impl", 2, select_api_version_impl, 0},
  {"setup_network", 0, setup_network, 0},
  {"run_network", 0, run_network, 0},
  {"stop_network", 0, stop_network, 0},
  {"create_cluster", 0, create_cluster, 0},
  {"get_error", 1, get_error, 0},
  {"future_resolve", 1, future_resolve, 0}
};

ERL_NIF_INIT(Elixir.FDB.Raw, nif_funcs, load, NULL, NULL, NULL)
