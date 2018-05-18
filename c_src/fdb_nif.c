#define FDB_API_VERSION 510

#include "stdio.h"
#include "string.h"
#include "erl_nif.h"
#include "foundationdb/fdb_c.h"

#define VERIFY_ARGV(A, M) if(!(A)) { ERL_NIF_TERM reason = string_to_binary(env, "Invalid argument: " M); return enif_raise_exception(env, reason); }

#define VERIFY(A, M) if(!(A)) { ERL_NIF_TERM reason = string_to_binary(env, "Failed to " M); return enif_raise_exception(env, reason); }

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

ERL_NIF_TERM
make_atom(ErlNifEnv* env, const char* atom) {
    ERL_NIF_TERM ret;

    if(!enif_make_existing_atom(env, atom, &ret, ERL_NIF_LATIN1)) {
        return enif_make_atom(env, atom);
    }

    return ret;
}

static ERL_NIF_TERM
get_max_api_version(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  return enif_make_int(env, fdb_get_max_api_version());
}

static ERL_NIF_TERM
select_api_version_impl(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  int runtime_version;
  int header_version;
  fdb_error_t error;

  VERIFY_ARGV(enif_get_int(env, argv[0], &runtime_version), "runtime_version");
  VERIFY_ARGV(enif_get_int(env, argv[1], &header_version), "header_version");

  error = fdb_select_api_version_impl(runtime_version, header_version);
  return enif_make_int(env, error);
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
  VERIFY(fdb_network_tid, "alloc");
  return enif_make_int(env, enif_thread_create(name, fdb_network_tid, &run_network_wrapper, NULL, NULL));
}

static ERL_NIF_TERM
stop_network(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  fdb_error_t error = fdb_stop_network();
  if(error) {
    return enif_make_int(env, error);
  }
  return enif_make_int(env, enif_thread_join(*fdb_network_tid, NULL));
}

static ERL_NIF_TERM
get_error(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  int code;
  VERIFY_ARGV(enif_get_int(env, argv[0], &code), "code");
  return string_to_binary(env, fdb_get_error(code));
}

typedef enum {
  CLUSTER,
  DATABASE,
  VALUE
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


static ErlNifResourceType *DATABASE_RESOURCE_TYPE;
typedef struct {
  FDBDatabase* handle;
} Database;

static void
database_destroy(ErlNifEnv *env, void *object) {
  Database *database = (Database*) object;
  fdb_database_destroy(database->handle);
}

static ERL_NIF_TERM
fdb_database_to_database(ErlNifEnv *env, FDBDatabase *fdb_database) {
  ERL_NIF_TERM term;
  Database *database = enif_alloc_resource(DATABASE_RESOURCE_TYPE, sizeof(Database));
  database->handle = fdb_database;
  term = enif_make_resource(env, database);
  enif_release_resource(database);
  return term;
}

static ErlNifResourceType *TRANSACTION_RESOURCE_TYPE;
typedef struct {
  FDBTransaction* handle;
  ErlNifEnv *env;
} Transaction;

static void
transaction_destroy(ErlNifEnv *env, void *object) {
  Transaction *transaction = (Transaction*) object;
  fdb_transaction_destroy(transaction->handle);
  enif_free_env(transaction->env);
}

static ERL_NIF_TERM
fdb_transaction_to_transaction(ErlNifEnv *env, FDBTransaction *fdb_transaction) {
  ERL_NIF_TERM term;
  Transaction *transaction = enif_alloc_resource(TRANSACTION_RESOURCE_TYPE, sizeof(Transaction));
  transaction->handle = fdb_transaction;
  transaction->env = enif_alloc_env();
  term = enif_make_resource(env, transaction);
  enif_release_resource(transaction);
  return term;
}


static fdb_error_t
future_get(ErlNifEnv *env, Future *future, ERL_NIF_TERM *term) {
  fdb_error_t error;

  switch(future->type) {
  case CLUSTER:
    {
      FDBCluster *cluster;
      error = fdb_future_get_cluster(future->handle, &cluster);
      if(error) {
        return error;
      }
      *term = fdb_cluster_to_cluster(env, cluster);
      return error;
    }
  case DATABASE:
    {
      FDBDatabase *database;
      error = fdb_future_get_database(future->handle, &database);
      if(error) {
        return error;
      }
      *term = fdb_database_to_database(env, database);
      return error;
    }
  case VALUE:
    {
      fdb_bool_t present;
      uint8_t const* value;
      int value_length;
      error = fdb_future_get_value(future->handle, &present, &value, &value_length);
      if(error) {
        return error;
      }
      if (present) {
        *term = enif_make_resource_binary(env, future, value, value_length);
      } else {
        *term = make_atom(env, "nil");
      }
      return error;
    }
  }
}


typedef struct {
  ErlNifPid *pid;
  ERL_NIF_TERM ref;
  Future *future;
  ErlNifEnv *env;
} FutureCallbackArgv;

static void
future_callback(FDBFuture *fdb_future, void *argv) {
  FutureCallbackArgv *callback_arg = (FutureCallbackArgv *)argv;
  ERL_NIF_TERM value;
  ERL_NIF_TERM msg;
  int send_result;
  ErlNifEnv *env = callback_arg->env;

  fdb_error_t error = future_get(env, callback_arg->future, &value);
  if (error) {
    value = make_atom(env, "nil");
  }
  msg = enif_make_tuple3(env, enif_make_int(env, error), callback_arg->ref, value);

  send_result = enif_send(NULL, callback_arg->pid, env, msg);
  if (!send_result) {
    DEBUG_LOG("Failed to send message");
  }

  enif_release_resource(callback_arg->future);
  enif_free(callback_arg->pid);
  enif_free_env(env);
  enif_free(callback_arg);
}

static ERL_NIF_TERM
future_resolve(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  Future *future;
  FutureCallbackArgv *callback_arg;
  fdb_error_t error;
  ERL_NIF_TERM ref;
  ErlNifEnv *callback_env;

  VERIFY_ARGV(enif_get_resource(env, argv[0], FUTURE_RESOURCE_TYPE, (void **)&future), "future");
  ref = argv[1];
  VERIFY_ARGV(enif_is_ref(env, ref), "reference");

  callback_env = enif_alloc_env();
  VERIFY(callback_env, "alloc_env");
  callback_arg = enif_alloc(sizeof(FutureCallbackArgv));
  callback_arg->env = callback_env;
  callback_arg->ref = enif_make_copy(callback_env, ref);
  callback_arg->pid = enif_alloc(sizeof(ErlNifPid));
  enif_keep_resource(future);
  callback_arg->future = future;
  VERIFY(enif_self(env, callback_arg->pid), "self");
  error = fdb_future_set_callback(future->handle, future_callback, callback_arg);
  return enif_make_int(env, error);
}


static ERL_NIF_TERM
create_cluster(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  FDBFuture *fdb_future = fdb_create_cluster(NULL);
  return fdb_future_to_future(env, fdb_future, CLUSTER);
}

static ERL_NIF_TERM
cluster_create_database(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  const uint8_t db_name[] = {'D', 'B'};
  Cluster *cluster;
  FDBFuture *fdb_future;
  VERIFY_ARGV(enif_get_resource(env, argv[0], CLUSTER_RESOURCE_TYPE, (void **)&cluster), "cluster");
  fdb_future = fdb_cluster_create_database(cluster->handle, db_name, 2);
  return fdb_future_to_future(env, fdb_future, DATABASE);
}


static ERL_NIF_TERM
database_create_transaction(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  Database *database;
  FDBTransaction *fdb_transaction;
  fdb_error_t error;
  ERL_NIF_TERM result;
  VERIFY_ARGV(enif_get_resource(env, argv[0], DATABASE_RESOURCE_TYPE, (void **)&database), "database");
  error = fdb_database_create_transaction(database->handle, &fdb_transaction);
  if (error) {
    return enif_make_tuple2(env, enif_make_int(env, error), make_atom(env, "nil"));
  }
  result = fdb_transaction_to_transaction(env, fdb_transaction);
  return enif_make_tuple2(env, enif_make_int(env, error), result);
}

static ERL_NIF_TERM
transaction_get(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  Transaction *transaction;
  FDBFuture *fdb_future;
  ERL_NIF_TERM key_term = argv[1];
  ErlNifBinary *key = enif_alloc(sizeof(ErlNifBinary));
  fdb_bool_t snapshot;
  VERIFY_ARGV(enif_get_resource(env, argv[0], TRANSACTION_RESOURCE_TYPE, (void **)&transaction), "transaction");
  VERIFY_ARGV(enif_is_binary(env, key_term), "key");
  VERIFY_ARGV(enif_get_int(env, argv[2], &snapshot), "snapshot");

  enif_inspect_binary(transaction->env, enif_make_copy(transaction->env, key_term), key);
  fdb_future = fdb_transaction_get(transaction->handle, key->data, key->size, snapshot);
  return fdb_future_to_future(env, fdb_future, VALUE);
}

int
load(ErlNifEnv *env, void **priv_data, ERL_NIF_TERM load_info) {
  int flags = ERL_NIF_RT_CREATE | ERL_NIF_RT_TAKEOVER;
  FUTURE_RESOURCE_TYPE = enif_open_resource_type(env, "fdb", "Future", future_destroy, flags, NULL);
  if(FUTURE_RESOURCE_TYPE == NULL) return -1;
  CLUSTER_RESOURCE_TYPE = enif_open_resource_type(env, "fdb", "Cluster", cluster_destroy, flags, NULL);
  if(CLUSTER_RESOURCE_TYPE == NULL) return -1;
  DATABASE_RESOURCE_TYPE = enif_open_resource_type(env, "fdb", "Database", database_destroy, flags, NULL);
  if(DATABASE_RESOURCE_TYPE == NULL) return -1;
  TRANSACTION_RESOURCE_TYPE = enif_open_resource_type(env, "fdb", "Transaction", transaction_destroy, flags, NULL);
  if(TRANSACTION_RESOURCE_TYPE == NULL) return -1;
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
  {"future_resolve", 2, future_resolve, 0},
  {"cluster_create_database", 1, cluster_create_database, 0},
  {"database_create_transaction", 1, database_create_transaction, 0},
  {"transaction_get", 3, transaction_get, 0}
};

ERL_NIF_INIT(Elixir.FDB.Native, nif_funcs, load, NULL, NULL, NULL)
