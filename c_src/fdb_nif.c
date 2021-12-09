/* A thin erlang nif wrapper around the fdb c api
 * https://apple.github.io/foundationdb/api-c.html
 */

#define FDB_API_VERSION 630

#include "erl_nif.h"
#include "foundationdb/fdb_c.h"
#include "stdio.h"
#include "string.h"

#define VERIFY_ARGV(A, M)                                                      \
  if (!(A)) {                                                                  \
    ERL_NIF_TERM reason = string_to_binary(env, "Invalid argument: " M);       \
    return enif_raise_exception(env, reason);                                  \
  }

#define VERIFY(A, M)                                                           \
  if (!(A)) {                                                                  \
    ERL_NIF_TERM reason = string_to_binary(env, "Failed to " M);               \
    return enif_raise_exception(env, reason);                                  \
  }

#ifdef FDB_DEBUG
#define DEBUG_LOG(string) fprintf(stderr, "%s\n", string)
#else
#define DEBUG_LOG(string)
#endif

static ERL_NIF_TERM
string_to_binary(ErlNifEnv *env, const char *string) {
  ErlNifBinary binary;

  enif_alloc_binary(strlen(string), &binary);
  memcpy(binary.data, string, strlen(string));
  return enif_make_binary(env, &binary);
}

ERL_NIF_TERM
make_atom(ErlNifEnv *env, const char *atom) {
  ERL_NIF_TERM ret;

  if (!enif_make_existing_atom(env, atom, &ret, ERL_NIF_LATIN1)) {
    return enif_make_atom(env, atom);
  }

  return ret;
}

#define OPTION_SUCCESS 0xFFFF

typedef struct {
  int code;
  uint8_t const *value;
  int size;
} Option;

static ERL_NIF_TERM
option_inspect(ErlNifEnv *env, int i, int argc, const ERL_NIF_TERM argv[],
               Option *option) {
  ErlNifBinary binary_value;
  option->size = 0;
  option->value = NULL;
  VERIFY_ARGV(enif_get_int(env, argv[i], &option->code), "option");

  if (argc == i + 2) {
    VERIFY_ARGV(enif_inspect_binary(env, argv[i + 1], &binary_value), "value");
    enif_inspect_binary(env, argv[i + 1], &binary_value);
    option->value = binary_value.data;
    option->size = binary_value.size;
  }
  return OPTION_SUCCESS;
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
network_set_option(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  Option option;
  ERL_NIF_TERM option_status;
  fdb_error_t error;

  option_status = option_inspect(env, 0, argc, argv, &option);
  if (option_status != OPTION_SUCCESS) {
    return option_status;
  }

  error = fdb_network_set_option(option.code, option.value, option.size);
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
  return enif_make_int(env,
                       enif_thread_create(name, fdb_network_tid,
                                          &run_network_wrapper, NULL, NULL));
}

static ERL_NIF_TERM
stop_network(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  fdb_error_t error = fdb_stop_network();
  if (error) {
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

static ERL_NIF_TERM
get_error_predicate(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  int predicate_test;
  int code;
  fdb_bool_t retryable;
  VERIFY_ARGV(enif_get_int(env, argv[0], &predicate_test), "predicate_test");
  VERIFY_ARGV(enif_get_int(env, argv[1], &code), "code");
  retryable = fdb_error_predicate(predicate_test, code);
  if (retryable) {
    return make_atom(env, "true");
  } else {
    return make_atom(env, "false");
  }
}

typedef enum { RESOURCE } ReferenceType;

typedef struct Reference {
  ReferenceType type;
  void *ptr;
  struct Reference *next;
} Reference;

static Reference *
reference_resource_create(void *resource, Reference *previous) {
  Reference *reference = enif_alloc(sizeof(Reference));
  enif_keep_resource(resource);
  reference->type = RESOURCE;
  reference->ptr = resource;
  reference->next = NULL;
  if (previous) {
    previous->next = reference;
  }
  return reference;
}

static void
reference_destroy_all(Reference *reference) {
  if (reference) {
    Reference *next = reference->next;
    if (reference->type == RESOURCE) {
      enif_release_resource(reference->ptr);
    }
    enif_free(reference);
    reference_destroy_all(next);
  }
}

static ErlNifResourceType *TRANSACTION_RESOURCE_TYPE;
typedef struct {
  FDBTransaction *handle;
  Reference *reference;
} Transaction;

typedef enum {
  VALUE,
  COMMIT,
  KEYVALUE_ARRAY,
  INT64,
  KEY,
  STRING_ARRAY,
  WATCH,
  ERROR
} FutureType;

static ErlNifResourceType *FUTURE_RESOURCE_TYPE;
typedef struct {
  FDBFuture *handle;
  FutureType type;
  Reference *reference;
  void *context;
} Future;

static void
future_destroy(ErlNifEnv *env, void *object) {
  Future *future = (Future *)object;
  fdb_future_destroy(future->handle);
  reference_destroy_all(future->reference);
}

static ERL_NIF_TERM
fdb_future_to_future(ErlNifEnv *env, FDBFuture *fdb_future, FutureType type,
                     Reference *reference, void *context) {
  ERL_NIF_TERM term;
  Future *future = enif_alloc_resource(FUTURE_RESOURCE_TYPE, sizeof(Future));
  future->handle = fdb_future;
  future->type = type;
  future->reference = reference;
  future->context = context;
  term = enif_make_resource(env, future);
  enif_release_resource(future);
  return term;
}

static ErlNifResourceType *DATABASE_RESOURCE_TYPE;
typedef struct {
  FDBDatabase *handle;
} Database;

static void
database_destroy(ErlNifEnv *env, void *object) {
  Database *database = (Database *)object;
  fdb_database_destroy(database->handle);
}

static ERL_NIF_TERM
fdb_database_to_database(ErlNifEnv *env, FDBDatabase *fdb_database) {
  ERL_NIF_TERM term;
  Database *database =
      enif_alloc_resource(DATABASE_RESOURCE_TYPE, sizeof(Database));
  database->handle = fdb_database;
  term = enif_make_resource(env, database);
  enif_release_resource(database);
  return term;
}

static void
transaction_destroy(ErlNifEnv *env, void *object) {
  Transaction *transaction = (Transaction *)object;
  fdb_transaction_destroy(transaction->handle);
  reference_destroy_all(transaction->reference);
}

static ERL_NIF_TERM
fdb_transaction_to_transaction(ErlNifEnv *env, FDBTransaction *fdb_transaction,
                               Reference *reference) {
  ERL_NIF_TERM term;
  Transaction *transaction =
      enif_alloc_resource(TRANSACTION_RESOURCE_TYPE, sizeof(Transaction));
  transaction->handle = fdb_transaction;
  transaction->reference = reference;
  term = enif_make_resource(env, transaction);
  enif_release_resource(transaction);
  return term;
}

static fdb_error_t
future_get(ErlNifEnv *env, Future *future, ERL_NIF_TERM *term) {
  fdb_error_t error;
  error = fdb_future_get_error(future->handle);
  *term = make_atom(env, "nil");

  if (error) {
    return error;
  }

  switch (future->type) {
  case VALUE: {
    fdb_bool_t present;
    uint8_t const *value;
    int value_length;
    error =
        fdb_future_get_value(future->handle, &present, &value, &value_length);
    if (error) {
      return error;
    }
    if (present) {
      *term = enif_make_resource_binary(env, future, value, value_length);
    } else {
      *term = make_atom(env, "nil");
    }
    return error;
  }
  case COMMIT: {
    *term = make_atom(env, "ok");
    return error;
  }
  case KEYVALUE_ARRAY: {
    FDBKeyValue const *out_kv;
    int out_count;
    fdb_bool_t out_more;
    ERL_NIF_TERM list;
    ERL_NIF_TERM result_list;
    int i;

    error = fdb_future_get_keyvalue_array(future->handle, &out_kv, &out_count,
                                          &out_more);
    if (error) {
      return error;
    }

    list = enif_make_list(env, 0);
    for (i = 0; i < out_count; i++) {
      FDBKeyValue key_value = out_kv[i];
      ERL_NIF_TERM key = enif_make_resource_binary(env, future, key_value.key,
                                                   key_value.key_length);
      ERL_NIF_TERM value = enif_make_resource_binary(
          env, future, key_value.value, key_value.value_length);
      list = enif_make_list_cell(env, enif_make_tuple2(env, key, value), list);
    }

    enif_make_reverse_list(env, list, &result_list);
    *term = enif_make_tuple2(env, enif_make_int(env, out_more), result_list);
    return error;
  }
  case INT64: {
    int64_t value;
    error = fdb_future_get_int64(future->handle, &value);
    if (error) {
      return error;
    }
    *term = enif_make_int64(env, value);
    return error;
  }
  case KEY: {
    uint8_t const *key;
    int key_length;
    error = fdb_future_get_key(future->handle, &key, &key_length);
    if (error) {
      return error;
    }
    *term = enif_make_resource_binary(env, future, key, key_length);
    return error;
  }
  case STRING_ARRAY: {
    const char **out_strings;
    int out_count;
    ERL_NIF_TERM list;
    ERL_NIF_TERM result_list;
    int i;

    error =
        fdb_future_get_string_array(future->handle, &out_strings, &out_count);
    if (error) {
      return error;
    }

    list = enif_make_list(env, 0);
    for (i = 0; i < out_count; i++) {
      const char *string = out_strings[i];
      ERL_NIF_TERM string_term =
          enif_make_resource_binary(env, future, string, strlen(string));
      list = enif_make_list_cell(env, string_term, list);
    }

    enif_make_reverse_list(env, list, &result_list);
    *term = result_list;
    return error;
  }
  case WATCH: {
    *term = make_atom(env, "ok");
    return error;
  }
  case ERROR: {
    *term = make_atom(env, "ok");
    return error;
  }
  default:
    error = 1;
    return error;
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
  msg = enif_make_tuple3(env, enif_make_int(env, error), callback_arg->ref,
                         value);

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

  VERIFY_ARGV(
      enif_get_resource(env, argv[0], FUTURE_RESOURCE_TYPE, (void **)&future),
      "future");
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
  error =
      fdb_future_set_callback(future->handle, future_callback, callback_arg);
  return enif_make_int(env, error);
}

static ERL_NIF_TERM
future_is_ready(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  Future *future;
  fdb_bool_t ready;
  VERIFY_ARGV(
      enif_get_resource(env, argv[0], FUTURE_RESOURCE_TYPE, (void **)&future),
      "future");
  ready = fdb_future_is_ready(future->handle);
  if (ready) {
    return make_atom(env, "true");
  } else {
    return make_atom(env, "false");
  }
}

static ERL_NIF_TERM
create_database(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  char *path = NULL;
  ErlNifBinary path_binary;
  fdb_error_t error;
  FDBDatabase *database;
  ERL_NIF_TERM result;

  if (enif_is_binary(env, argv[0])) {
    enif_inspect_binary(env, argv[0], &path_binary);
    path = enif_alloc(sizeof(char) * (path_binary.size + 1));
    memcpy((void *)path, path_binary.data, path_binary.size);
    path[path_binary.size] = '\0';
  }

  error = fdb_create_database(path, &database);
  if (error) {
    return enif_make_tuple2(env, enif_make_int(env, error),
                            make_atom(env, "nil"));
  }
  result = fdb_database_to_database(env, database);
  enif_free(path);
  return enif_make_tuple2(env, enif_make_int(env, error), result);
}

static ERL_NIF_TERM
database_set_option(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  Database *database;
  Option option;
  ERL_NIF_TERM option_status;
  fdb_error_t error;

  VERIFY_ARGV(enif_get_resource(env, argv[0], DATABASE_RESOURCE_TYPE,
                                (void **)&database),
              "database");

  option_status = option_inspect(env, 1, argc, argv, &option);
  if (option_status != OPTION_SUCCESS) {
    return option_status;
  }

  error = fdb_database_set_option(database->handle, option.code, option.value,
                                  option.size);
  return enif_make_int(env, error);
}

static ERL_NIF_TERM
database_create_transaction(ErlNifEnv *env, int argc,
                            const ERL_NIF_TERM argv[]) {
  Database *database;
  FDBTransaction *fdb_transaction;
  Reference *reference;
  fdb_error_t error;
  ERL_NIF_TERM result;
  VERIFY_ARGV(enif_get_resource(env, argv[0], DATABASE_RESOURCE_TYPE,
                                (void **)&database),
              "database");
  error = fdb_database_create_transaction(database->handle, &fdb_transaction);
  if (error) {
    return enif_make_tuple2(env, enif_make_int(env, error),
                            make_atom(env, "nil"));
  }
  reference = reference_resource_create(database, NULL);
  result = fdb_transaction_to_transaction(env, fdb_transaction, reference);
  return enif_make_tuple2(env, enif_make_int(env, error), result);
}

static ERL_NIF_TERM
transaction_set_option(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  Transaction *transaction;
  Option option;
  ERL_NIF_TERM option_status;
  fdb_error_t error;

  VERIFY_ARGV(enif_get_resource(env, argv[0], TRANSACTION_RESOURCE_TYPE,
                                (void **)&transaction),
              "transaction");

  option_status = option_inspect(env, 1, argc, argv, &option);
  if (option_status != OPTION_SUCCESS) {
    return option_status;
  }

  error = fdb_transaction_set_option(transaction->handle, option.code,
                                     option.value, option.size);
  return enif_make_int(env, error);
}

static ERL_NIF_TERM
transaction_get(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  Transaction *transaction;
  FDBFuture *fdb_future;
  ERL_NIF_TERM key_term = argv[1];
  ErlNifBinary key;
  fdb_bool_t snapshot;
  Reference *reference = NULL;
  VERIFY_ARGV(enif_get_resource(env, argv[0], TRANSACTION_RESOURCE_TYPE,
                                (void **)&transaction),
              "transaction");
  VERIFY_ARGV(enif_is_binary(env, key_term), "key");
  VERIFY_ARGV(enif_get_int(env, argv[2], &snapshot), "snapshot");

  enif_inspect_binary(env, key_term, &key);
  fdb_future =
      fdb_transaction_get(transaction->handle, key.data, key.size, snapshot);

  reference = reference_resource_create(transaction, NULL);
  return fdb_future_to_future(env, fdb_future, VALUE, reference, NULL);
}

static ERL_NIF_TERM
transaction_get_read_version(ErlNifEnv *env, int argc,
                             const ERL_NIF_TERM argv[]) {
  Transaction *transaction;
  FDBFuture *fdb_future;
  Reference *reference = NULL;
  VERIFY_ARGV(enif_get_resource(env, argv[0], TRANSACTION_RESOURCE_TYPE,
                                (void **)&transaction),
              "transaction");
  fdb_future = fdb_transaction_get_read_version(transaction->handle);
  reference = reference_resource_create(transaction, NULL);
  return fdb_future_to_future(env, fdb_future, INT64, reference, NULL);
}

static ERL_NIF_TERM
transaction_get_approximate_size(ErlNifEnv *env, int argc,
                                 const ERL_NIF_TERM argv[]) {
  Transaction *transaction;
  FDBFuture *fdb_future;
  Reference *reference = NULL;
  VERIFY_ARGV(enif_get_resource(env, argv[0], TRANSACTION_RESOURCE_TYPE,
                                (void **)&transaction),
              "transaction");
  fdb_future = fdb_transaction_get_approximate_size(transaction->handle);
  reference = reference_resource_create(transaction, NULL);
  return fdb_future_to_future(env, fdb_future, INT64, reference, NULL);
}

static ERL_NIF_TERM
transaction_get_committed_version(ErlNifEnv *env, int argc,
                                  const ERL_NIF_TERM argv[]) {
  Transaction *transaction;
  fdb_error_t error;
  int64_t version;
  VERIFY_ARGV(enif_get_resource(env, argv[0], TRANSACTION_RESOURCE_TYPE,
                                (void **)&transaction),
              "transaction");
  error = fdb_transaction_get_committed_version(transaction->handle, &version);
  if (error) {
    return enif_make_tuple2(env, enif_make_int(env, error),
                            make_atom(env, "nil"));
  }
  return enif_make_tuple2(env, enif_make_int(env, error),
                          enif_make_int64(env, version));
}

static ERL_NIF_TERM
transaction_get_versionstamp(ErlNifEnv *env, int argc,
                             const ERL_NIF_TERM argv[]) {
  Transaction *transaction;
  FDBFuture *fdb_future;
  Reference *reference = NULL;
  VERIFY_ARGV(enif_get_resource(env, argv[0], TRANSACTION_RESOURCE_TYPE,
                                (void **)&transaction),
              "transaction");
  fdb_future = fdb_transaction_get_versionstamp(transaction->handle);
  reference = reference_resource_create(transaction, NULL);
  return fdb_future_to_future(env, fdb_future, KEY, reference, NULL);
}

static ERL_NIF_TERM
transaction_get_key(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  Transaction *transaction;
  FDBFuture *fdb_future;
  ERL_NIF_TERM key_term = argv[1];
  fdb_bool_t or_equal;
  int offset;
  fdb_bool_t snapshot;
  Reference *reference = NULL;

  ErlNifBinary key;

  VERIFY_ARGV(enif_get_resource(env, argv[0], TRANSACTION_RESOURCE_TYPE,
                                (void **)&transaction),
              "transaction");
  VERIFY_ARGV(enif_is_binary(env, key_term), "key");
  VERIFY_ARGV(enif_get_int(env, argv[2], &or_equal), "or_equal");
  VERIFY_ARGV(enif_get_int(env, argv[3], &offset), "offset");
  VERIFY_ARGV(enif_get_int(env, argv[4], &snapshot), "snapshot");

  enif_inspect_binary(env, key_term, &key);
  fdb_future = fdb_transaction_get_key(transaction->handle, key.data, key.size,
                                       or_equal, offset, snapshot);
  reference = reference_resource_create(transaction, NULL);
  return fdb_future_to_future(env, fdb_future, KEY, reference, NULL);
}

static ERL_NIF_TERM
transaction_get_addresses_for_key(ErlNifEnv *env, int argc,
                                  const ERL_NIF_TERM argv[]) {
  Transaction *transaction;
  FDBFuture *fdb_future;
  ERL_NIF_TERM key_term = argv[1];

  ErlNifBinary key;
  Reference *reference = NULL;

  VERIFY_ARGV(enif_get_resource(env, argv[0], TRANSACTION_RESOURCE_TYPE,
                                (void **)&transaction),
              "transaction");
  VERIFY_ARGV(enif_is_binary(env, key_term), "key");

  enif_inspect_binary(env, key_term, &key);
  fdb_future = fdb_transaction_get_addresses_for_key(transaction->handle,
                                                     key.data, key.size);
  reference = reference_resource_create(transaction, NULL);
  return fdb_future_to_future(env, fdb_future, STRING_ARRAY, reference, NULL);
}

static ERL_NIF_TERM
transaction_get_range(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  Transaction *transaction;
  FDBFuture *fdb_future;
  Reference *reference = NULL;

  ERL_NIF_TERM begin_key_term = argv[1];
  fdb_bool_t begin_or_equal;
  int begin_offset;

  ERL_NIF_TERM end_key_term = argv[4];
  fdb_bool_t end_or_equal;
  int end_offset;

  int limit;
  int target_bytes;

  int mode;
  int iteration;
  fdb_bool_t snapshot;
  fdb_bool_t reverse;

  ErlNifBinary begin_key;
  ErlNifBinary end_key;

  VERIFY_ARGV(enif_get_resource(env, argv[0], TRANSACTION_RESOURCE_TYPE,
                                (void **)&transaction),
              "transaction");
  VERIFY_ARGV(enif_is_binary(env, begin_key_term), "begin_key");
  VERIFY_ARGV(enif_get_int(env, argv[2], &begin_or_equal), "begin_or_equal");
  VERIFY_ARGV(enif_get_int(env, argv[3], &begin_offset), "begin_offset");
  VERIFY_ARGV(enif_is_binary(env, end_key_term), "end_key");
  VERIFY_ARGV(enif_get_int(env, argv[5], &end_or_equal), "end_or_equal");
  VERIFY_ARGV(enif_get_int(env, argv[6], &end_offset), "end_offset");
  VERIFY_ARGV(enif_get_int(env, argv[7], &limit), "limit");
  VERIFY_ARGV(enif_get_int(env, argv[8], &target_bytes), "target_bytes");
  VERIFY_ARGV(enif_get_int(env, argv[9], &mode), "mode");
  VERIFY_ARGV(enif_get_int(env, argv[10], &iteration), "iteration");
  VERIFY_ARGV(enif_get_int(env, argv[11], &snapshot), "snapshot");
  VERIFY_ARGV(enif_get_int(env, argv[12], &reverse), "reverse");

  enif_inspect_binary(env, begin_key_term, &begin_key);
  enif_inspect_binary(env, end_key_term, &end_key);

  fdb_future = fdb_transaction_get_range(
      transaction->handle, begin_key.data, begin_key.size, begin_or_equal,
      begin_offset, end_key.data, end_key.size, end_or_equal, end_offset, limit,
      target_bytes, (FDBStreamingMode)mode, iteration, snapshot, reverse);

  reference = reference_resource_create(transaction, NULL);
  return fdb_future_to_future(env, fdb_future, KEYVALUE_ARRAY, reference, NULL);
}

static ERL_NIF_TERM
transaction_set(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  Transaction *transaction;
  ERL_NIF_TERM key_term = argv[1];
  ERL_NIF_TERM value_term = argv[2];
  ErlNifBinary key;
  ErlNifBinary value;

  VERIFY_ARGV(enif_get_resource(env, argv[0], TRANSACTION_RESOURCE_TYPE,
                                (void **)&transaction),
              "transaction");
  VERIFY_ARGV(enif_is_binary(env, key_term), "key");
  VERIFY_ARGV(enif_is_binary(env, value_term), "value");

  enif_inspect_binary(env, key_term, &key);
  enif_inspect_binary(env, value_term, &value);

  fdb_transaction_set(transaction->handle, key.data, key.size, value.data,
                      value.size);
  return enif_make_int(env, 0);
}

static ERL_NIF_TERM
transaction_set_read_version(ErlNifEnv *env, int argc,
                             const ERL_NIF_TERM argv[]) {
  Transaction *transaction;
  ErlNifSInt64 version;

  VERIFY_ARGV(enif_get_resource(env, argv[0], TRANSACTION_RESOURCE_TYPE,
                                (void **)&transaction),
              "transaction");
  VERIFY_ARGV(enif_get_int64(env, argv[1], &version), "version");
  fdb_transaction_set_read_version(transaction->handle, version);
  return enif_make_int(env, 0);
}

static ERL_NIF_TERM
transaction_add_conflict_range(ErlNifEnv *env, int argc,
                               const ERL_NIF_TERM argv[]) {
  Transaction *transaction;
  int conflict_range_type;
  fdb_error_t error;
  ERL_NIF_TERM begin_key_term = argv[1];
  ERL_NIF_TERM end_key_term = argv[2];

  ErlNifBinary begin_key;
  ErlNifBinary end_key;

  VERIFY_ARGV(enif_get_resource(env, argv[0], TRANSACTION_RESOURCE_TYPE,
                                (void **)&transaction),
              "transaction");
  VERIFY_ARGV(enif_is_binary(env, begin_key_term), "begin_key");
  VERIFY_ARGV(enif_is_binary(env, end_key_term), "end_key");
  VERIFY_ARGV(enif_get_int(env, argv[3], &conflict_range_type),
              "conflict_range_type");

  enif_inspect_binary(env, begin_key_term, &begin_key);
  enif_inspect_binary(env, end_key_term, &end_key);

  error = fdb_transaction_add_conflict_range(
      transaction->handle, begin_key.data, begin_key.size, end_key.data,
      end_key.size, conflict_range_type);

  return enif_make_int(env, error);
}

static ERL_NIF_TERM
transaction_get_estimated_range_size_bytes(ErlNifEnv *env, int argc,
                                           const ERL_NIF_TERM argv[]) {
  Transaction *transaction;
  FDBFuture *fdb_future;
  Reference *reference = NULL;

  ERL_NIF_TERM begin_key_term = argv[1];
  ERL_NIF_TERM end_key_term = argv[2];

  ErlNifBinary begin_key;
  ErlNifBinary end_key;

  VERIFY_ARGV(enif_get_resource(env, argv[0], TRANSACTION_RESOURCE_TYPE,
                                (void **)&transaction),
              "transaction");
  VERIFY_ARGV(enif_is_binary(env, begin_key_term), "begin_key");
  VERIFY_ARGV(enif_is_binary(env, end_key_term), "end_key");

  enif_inspect_binary(env, begin_key_term, &begin_key);
  enif_inspect_binary(env, end_key_term, &end_key);

  fdb_future = fdb_transaction_get_estimated_range_size_bytes(
      transaction->handle, begin_key.data, begin_key.size, end_key.data,
      end_key.size);
  reference = reference_resource_create(transaction, NULL);
  return fdb_future_to_future(env, fdb_future, INT64, reference, NULL);
}

static ERL_NIF_TERM
transaction_atomic_op(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  Transaction *transaction;
  ERL_NIF_TERM key_term = argv[1];
  ERL_NIF_TERM param_term = argv[2];
  ErlNifBinary key;
  ErlNifBinary param;
  int operation_type;

  VERIFY_ARGV(enif_get_resource(env, argv[0], TRANSACTION_RESOURCE_TYPE,
                                (void **)&transaction),
              "transaction");
  VERIFY_ARGV(enif_is_binary(env, key_term), "key");
  VERIFY_ARGV(enif_is_binary(env, param_term), "param");
  VERIFY_ARGV(enif_get_int(env, argv[3], &operation_type), "operation_type");

  enif_inspect_binary(env, key_term, &key);
  enif_inspect_binary(env, param_term, &param);

  fdb_transaction_atomic_op(transaction->handle, key.data, key.size, param.data,
                            param.size, operation_type);
  return enif_make_int(env, 0);
}

static ERL_NIF_TERM
transaction_clear(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  Transaction *transaction;
  ERL_NIF_TERM key_term = argv[1];
  ErlNifBinary key;
  VERIFY_ARGV(enif_get_resource(env, argv[0], TRANSACTION_RESOURCE_TYPE,
                                (void **)&transaction),
              "transaction");
  VERIFY_ARGV(enif_is_binary(env, key_term), "key");

  enif_inspect_binary(env, key_term, &key);

  fdb_transaction_clear(transaction->handle, key.data, key.size);
  return enif_make_int(env, 0);
}

static ERL_NIF_TERM
transaction_clear_range(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  Transaction *transaction;
  ERL_NIF_TERM begin_key_term = argv[1];
  ERL_NIF_TERM end_key_term = argv[2];
  ErlNifBinary begin_key;
  ErlNifBinary end_key;
  VERIFY_ARGV(enif_get_resource(env, argv[0], TRANSACTION_RESOURCE_TYPE,
                                (void **)&transaction),
              "transaction");
  VERIFY_ARGV(enif_is_binary(env, begin_key_term), "begin_key");
  VERIFY_ARGV(enif_is_binary(env, end_key_term), "end_key");

  enif_inspect_binary(env, begin_key_term, &begin_key);
  enif_inspect_binary(env, end_key_term, &end_key);

  fdb_transaction_clear_range(transaction->handle, begin_key.data,
                              begin_key.size, end_key.data, end_key.size);
  return enif_make_int(env, 0);
}

static ERL_NIF_TERM
transaction_commit(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  Transaction *transaction;
  FDBFuture *fdb_future;
  Reference *reference = NULL;
  VERIFY_ARGV(enif_get_resource(env, argv[0], TRANSACTION_RESOURCE_TYPE,
                                (void **)&transaction),
              "transaction");

  fdb_future = fdb_transaction_commit(transaction->handle);
  reference = reference_resource_create(transaction, NULL);
  return fdb_future_to_future(env, fdb_future, COMMIT, reference, NULL);
}

static ERL_NIF_TERM
transaction_watch(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  Transaction *transaction;
  ERL_NIF_TERM key_term = argv[1];
  ErlNifBinary key;

  FDBFuture *fdb_future;

  VERIFY_ARGV(enif_get_resource(env, argv[0], TRANSACTION_RESOURCE_TYPE,
                                (void **)&transaction),
              "transaction");
  VERIFY_ARGV(enif_is_binary(env, key_term), "key");

  enif_inspect_binary(env, key_term, &key);

  fdb_future = fdb_transaction_watch(transaction->handle, key.data, key.size);
  return fdb_future_to_future(env, fdb_future, WATCH, NULL, NULL);
}

static ERL_NIF_TERM
transaction_on_error(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  Transaction *transaction;
  fdb_error_t error_code;
  FDBFuture *fdb_future;
  Reference *reference = NULL;
  VERIFY_ARGV(enif_get_resource(env, argv[0], TRANSACTION_RESOURCE_TYPE,
                                (void **)&transaction),
              "transaction");
  VERIFY_ARGV(enif_get_int(env, argv[1], &error_code), "error_code");

  fdb_future = fdb_transaction_on_error(transaction->handle, error_code);
  reference = reference_resource_create(transaction, NULL);
  return fdb_future_to_future(env, fdb_future, ERROR, reference, NULL);
}

static ERL_NIF_TERM
transaction_cancel(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  Transaction *transaction;
  VERIFY_ARGV(enif_get_resource(env, argv[0], TRANSACTION_RESOURCE_TYPE,
                                (void **)&transaction),
              "transaction");
  fdb_transaction_cancel(transaction->handle);
  return enif_make_int(env, 0);
}

int
load(ErlNifEnv *env, void **priv_data, ERL_NIF_TERM load_info) {
  int flags = ERL_NIF_RT_CREATE | ERL_NIF_RT_TAKEOVER;
  FUTURE_RESOURCE_TYPE = enif_open_resource_type(env, "fdb", "Future",
                                                 future_destroy, flags, NULL);
  if (FUTURE_RESOURCE_TYPE == NULL)
    return -1;
  DATABASE_RESOURCE_TYPE = enif_open_resource_type(
      env, "fdb", "Database", database_destroy, flags, NULL);
  if (DATABASE_RESOURCE_TYPE == NULL)
    return -1;
  TRANSACTION_RESOURCE_TYPE = enif_open_resource_type(
      env, "fdb", "Transaction", transaction_destroy, flags, NULL);
  if (TRANSACTION_RESOURCE_TYPE == NULL)
    return -1;
  return 0;
}

static ErlNifFunc nif_funcs[] = {
    {"get_max_api_version", 0, get_max_api_version, 0},
    {"select_api_version_impl", 2, select_api_version_impl, 0},
    {"setup_network", 0, setup_network, 0},
    {"run_network", 0, run_network, 0},
    {"stop_network", 0, stop_network, 0},
    {"network_set_option", 1, network_set_option, 0},
    {"network_set_option", 2, network_set_option, 0},
    {"create_database", 1, create_database, 0},
    {"database_set_option", 2, database_set_option, 0},
    {"database_set_option", 3, database_set_option, 0},
    {"transaction_set_option", 2, transaction_set_option, 0},
    {"transaction_set_option", 3, transaction_set_option, 0},
    {"get_error", 1, get_error, 0},
    {"get_error_predicate", 2, get_error_predicate, 0},
    {"future_resolve", 2, future_resolve, 0},
    {"future_is_ready", 1, future_is_ready, 0},
    {"database_create_transaction", 1, database_create_transaction, 0},
    {"transaction_get", 3, transaction_get, 0},
    {"transaction_get_read_version", 1, transaction_get_read_version, 0},
    {"transaction_get_approximate_size", 1, transaction_get_approximate_size,
     0},
    {"transaction_get_key", 5, transaction_get_key, 0},
    {"transaction_get_addresses_for_key", 2, transaction_get_addresses_for_key,
     0},
    {"transaction_get_range", 13, transaction_get_range, 0},
    {"transaction_set", 3, transaction_set, 0},
    {"transaction_set_read_version", 2, transaction_set_read_version, 0},
    {"transaction_add_conflict_range", 4, transaction_add_conflict_range, 0},
    {"transaction_get_estimated_range_size_bytes", 3,
     transaction_get_estimated_range_size_bytes, 0},
    {"transaction_get_committed_version", 1, transaction_get_committed_version,
     0},
    {"transaction_get_versionstamp", 1, transaction_get_versionstamp, 0},
    {"transaction_atomic_op", 4, transaction_atomic_op, 0},
    {"transaction_clear", 2, transaction_clear, 0},
    {"transaction_clear_range", 3, transaction_clear_range, 0},
    {"transaction_watch", 2, transaction_watch, 0},
    {"transaction_commit", 1, transaction_commit, 0},
    {"transaction_cancel", 1, transaction_cancel, 0},
    {"transaction_on_error", 2, transaction_on_error, 0}};

ERL_NIF_INIT(Elixir.FDB.Native, nif_funcs, load, NULL, NULL, NULL)
