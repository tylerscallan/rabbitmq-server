%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License
%% at http://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and
%% limitations under the License.
%%
%% The Original Code is RabbitMQ.
%%
%% The Initial Developer of the Original Code is GoPivotal, Inc.
%% Copyright (c) 2007-2019 Pivotal Software, Inc.  All rights reserved.
%%

-module(rabbit_upgrade_functions).

%% If you are tempted to add include("rabbit.hrl"). here, don't. Using record
%% defs here leads to pain later.

-compile([nowarn_export_all, export_all]).

-rabbit_upgrade({remove_user_scope,     mnesia, []}).
-rabbit_upgrade({hash_passwords,        mnesia, []}).
-rabbit_upgrade({add_ip_to_listener,    mnesia, []}).
-rabbit_upgrade({add_opts_to_listener,  mnesia, [add_ip_to_listener]}).
-rabbit_upgrade({internal_exchanges,    mnesia, []}).
-rabbit_upgrade({user_to_internal_user, mnesia, [hash_passwords]}).
-rabbit_upgrade({topic_trie,            mnesia, []}).
-rabbit_upgrade({semi_durable_route,    mnesia, []}).
-rabbit_upgrade({exchange_event_serial, mnesia, []}).
-rabbit_upgrade({trace_exchanges,       mnesia, [internal_exchanges]}).
-rabbit_upgrade({user_admin_to_tags,    mnesia, [user_to_internal_user]}).
-rabbit_upgrade({ha_mirrors,            mnesia, []}).
-rabbit_upgrade({gm,                    mnesia, []}).
-rabbit_upgrade({exchange_scratch,      mnesia, [trace_exchanges]}).
-rabbit_upgrade({mirrored_supervisor,   mnesia, []}).
-rabbit_upgrade({topic_trie_node,       mnesia, []}).
-rabbit_upgrade({runtime_parameters,    mnesia, []}).
-rabbit_upgrade({exchange_scratches,    mnesia, [exchange_scratch]}).
-rabbit_upgrade({policy,                mnesia,
                 [exchange_scratches, ha_mirrors]}).
-rabbit_upgrade({sync_slave_pids,       mnesia, [policy]}).
-rabbit_upgrade({no_mirror_nodes,       mnesia, [sync_slave_pids]}).
-rabbit_upgrade({gm_pids,               mnesia, [no_mirror_nodes]}).
-rabbit_upgrade({exchange_decorators,   mnesia, [policy]}).
-rabbit_upgrade({policy_apply_to,       mnesia, [runtime_parameters]}).
-rabbit_upgrade({queue_decorators,      mnesia, [gm_pids]}).
-rabbit_upgrade({internal_system_x,     mnesia, [exchange_decorators]}).
-rabbit_upgrade({cluster_name,          mnesia, [runtime_parameters]}).
-rabbit_upgrade({down_slave_nodes,      mnesia, [queue_decorators]}).
-rabbit_upgrade({queue_state,           mnesia, [down_slave_nodes]}).
-rabbit_upgrade({recoverable_slaves,    mnesia, [queue_state]}).
-rabbit_upgrade({policy_version,        mnesia, [recoverable_slaves]}).
-rabbit_upgrade({slave_pids_pending_shutdown, mnesia, [policy_version]}).
-rabbit_upgrade({user_password_hashing, mnesia, [hash_passwords]}).
-rabbit_upgrade({operator_policies,     mnesia, [slave_pids_pending_shutdown, internal_system_x]}).
-rabbit_upgrade({vhost_limits,          mnesia, []}).
-rabbit_upgrade({queue_vhost_field,     mnesia, [operator_policies]}).
-rabbit_upgrade({topic_permission,      mnesia,  []}).
-rabbit_upgrade({queue_options,         mnesia, [queue_vhost_field]}).
-rabbit_upgrade({exchange_options,      mnesia, [operator_policies]}).

%% TODO: move that to feature flags
-rabbit_upgrade({remove_explicit_default_exchange_bindings, mnesia, [queue_state]}).

%% -------------------------------------------------------------------

-spec remove_user_scope() -> 'ok'.
-spec hash_passwords() -> 'ok'.
-spec add_ip_to_listener() -> 'ok'.
-spec add_opts_to_listener() -> 'ok'.
-spec internal_exchanges() -> 'ok'.
-spec user_to_internal_user() -> 'ok'.
-spec topic_trie() -> 'ok'.
-spec semi_durable_route() -> 'ok'.
-spec exchange_event_serial() -> 'ok'.
-spec trace_exchanges() -> 'ok'.
-spec user_admin_to_tags() -> 'ok'.
-spec ha_mirrors() -> 'ok'.
-spec gm() -> 'ok'.
-spec exchange_scratch() -> 'ok'.
-spec mirrored_supervisor() -> 'ok'.
-spec topic_trie_node() -> 'ok'.
-spec runtime_parameters() -> 'ok'.
-spec policy() -> 'ok'.
-spec sync_slave_pids() -> 'ok'.
-spec no_mirror_nodes() -> 'ok'.
-spec gm_pids() -> 'ok'.
-spec exchange_decorators() -> 'ok'.
-spec policy_apply_to() -> 'ok'.
-spec queue_decorators() -> 'ok'.
-spec internal_system_x() -> 'ok'.
-spec cluster_name() -> 'ok'.
-spec down_slave_nodes() -> 'ok'.
-spec queue_state() -> 'ok'.
-spec recoverable_slaves() -> 'ok'.
-spec user_password_hashing() -> 'ok'.
-spec vhost_limits() -> 'ok'.
-spec operator_policies() -> 'ok'.
-spec queue_vhost_field() -> 'ok'.
-spec queue_options() -> 'ok'.
-spec exchange_options() -> 'ok'.

-spec remove_explicit_default_exchange_bindings() -> 'ok'.

%%--------------------------------------------------------------------

%% replaces vhost.dummy (used to avoid having a single-field record
%% which Mnesia doesn't like) with vhost.limits (which is actually
%% used)
vhost_limits() ->
    transform(
      rabbit_vhost,
      fun ({vhost, VHost, _Dummy}) ->
              {vhost, VHost, undefined}
      end,
      [virtual_host, limits]).

%% It's a bad idea to use records or record_info here, even for the
%% destination form. Because in the future, the destination form of
%% your current transform may not match the record any more, and it
%% would be messy to have to go back and fix old transforms at that
%% point.

remove_user_scope() ->
    transform(
      rabbit_user_permission,
      fun ({user_permission, UV, {permission, _Scope, Conf, Write, Read}}) ->
              {user_permission, UV, {permission, Conf, Write, Read}}
      end,
      [user_vhost, permission]).

%% this is an early migration that hashes passwords using MD5,
%% only relevant to those migrating from 2.1.1.
%% all users created after in 3.6.0 or later will use SHA-256 (unless configured
%% otherwise)
hash_passwords() ->
    transform(
      rabbit_user,
      fun ({user, Username, Password, IsAdmin}) ->
              Hash = rabbit_auth_backend_internal:hash_password(rabbit_password_hashing_md5, Password),
              {user, Username, Hash, IsAdmin}
      end,
      [username, password_hash, is_admin]).

add_ip_to_listener() ->
    transform(
      rabbit_listener,
      fun ({listener, Node, Protocol, Host, Port}) ->
              {listener, Node, Protocol, Host, {0,0,0,0}, Port}
      end,
      [node, protocol, host, ip_address, port]).

add_opts_to_listener() ->
    transform(
      rabbit_listener,
      fun ({listener, Node, Protocol, Host, IP, Port}) ->
              {listener, Node, Protocol, Host, IP, Port, []}
      end,
      [node, protocol, host, ip_address, port, opts]).

internal_exchanges() ->
    Tables = [rabbit_exchange, rabbit_durable_exchange],
    AddInternalFun =
        fun ({exchange, Name, Type, Durable, AutoDelete, Args}) ->
                {exchange, Name, Type, Durable, AutoDelete, false, Args}
        end,
    [ ok = transform(T,
                     AddInternalFun,
                     [name, type, durable, auto_delete, internal, arguments])
      || T <- Tables ],
    ok.

user_to_internal_user() ->
    transform(
      rabbit_user,
      fun({user, Username, PasswordHash, IsAdmin}) ->
              {internal_user, Username, PasswordHash, IsAdmin}
      end,
      [username, password_hash, is_admin], internal_user).

topic_trie() ->
    create(rabbit_topic_trie_edge, [{record_name, topic_trie_edge},
                                    {attributes, [trie_edge, node_id]},
                                    {type, ordered_set}]),
    create(rabbit_topic_trie_binding, [{record_name, topic_trie_binding},
                                       {attributes, [trie_binding, value]},
                                       {type, ordered_set}]).

semi_durable_route() ->
    create(rabbit_semi_durable_route, [{record_name, route},
                                       {attributes, [binding, value]}]).

exchange_event_serial() ->
    create(rabbit_exchange_serial, [{record_name, exchange_serial},
                                    {attributes, [name, next]}]).

trace_exchanges() ->
    [declare_exchange(
       rabbit_misc:r(VHost, exchange, <<"amq.rabbitmq.trace">>), topic) ||
        VHost <- rabbit_vhost:list()],
    ok.

user_admin_to_tags() ->
    transform(
      rabbit_user,
      fun({internal_user, Username, PasswordHash, true}) ->
              {internal_user, Username, PasswordHash, [administrator]};
         ({internal_user, Username, PasswordHash, false}) ->
              {internal_user, Username, PasswordHash, [management]}
      end,
      [username, password_hash, tags], internal_user).

ha_mirrors() ->
    Tables = [rabbit_queue, rabbit_durable_queue],
    AddMirrorPidsFun =
        fun ({amqqueue, Name, Durable, AutoDelete, Owner, Arguments, Pid}) ->
                {amqqueue, Name, Durable, AutoDelete, Owner, Arguments, Pid,
                 [], undefined}
        end,
    [ ok = transform(T,
                     AddMirrorPidsFun,
                     [name, durable, auto_delete, exclusive_owner, arguments,
                      pid, slave_pids, mirror_nodes])
      || T <- Tables ],
    ok.

gm() ->
    create(gm_group, [{record_name, gm_group},
                      {attributes, [name, version, members]}]).

exchange_scratch() ->
    ok = exchange_scratch(rabbit_exchange),
    ok = exchange_scratch(rabbit_durable_exchange).

exchange_scratch(Table) ->
    transform(
      Table,
      fun ({exchange, Name, Type, Dur, AutoDel, Int, Args}) ->
              {exchange, Name, Type, Dur, AutoDel, Int, Args, undefined}
      end,
      [name, type, durable, auto_delete, internal, arguments, scratch]).

mirrored_supervisor() ->
    create(mirrored_sup_childspec,
           [{record_name, mirrored_sup_childspec},
            {attributes, [key, mirroring_pid, childspec]}]).

topic_trie_node() ->
    create(rabbit_topic_trie_node,
           [{record_name, topic_trie_node},
            {attributes, [trie_node, edge_count, binding_count]},
            {type, ordered_set}]).

runtime_parameters() ->
    create(rabbit_runtime_parameters,
           [{record_name, runtime_parameters},
            {attributes, [key, value]},
            {disc_copies, [node()]}]).

exchange_scratches() ->
    ok = exchange_scratches(rabbit_exchange),
    ok = exchange_scratches(rabbit_durable_exchange).

exchange_scratches(Table) ->
    transform(
      Table,
      fun ({exchange, Name, Type = <<"x-federation">>, Dur, AutoDel, Int, Args,
            Scratch}) ->
              Scratches = orddict:store(federation, Scratch, orddict:new()),
              {exchange, Name, Type, Dur, AutoDel, Int, Args, Scratches};
          %% We assert here that nothing else uses the scratch mechanism ATM
          ({exchange, Name, Type, Dur, AutoDel, Int, Args, undefined}) ->
              {exchange, Name, Type, Dur, AutoDel, Int, Args, undefined}
      end,
      [name, type, durable, auto_delete, internal, arguments, scratches]).

policy() ->
    ok = exchange_policy(rabbit_exchange),
    ok = exchange_policy(rabbit_durable_exchange),
    ok = queue_policy(rabbit_queue),
    ok = queue_policy(rabbit_durable_queue).

exchange_policy(Table) ->
    transform(
      Table,
      fun ({exchange, Name, Type, Dur, AutoDel, Int, Args, Scratches}) ->
              {exchange, Name, Type, Dur, AutoDel, Int, Args, Scratches,
               undefined}
      end,
      [name, type, durable, auto_delete, internal, arguments, scratches,
       policy]).

queue_policy(Table) ->
    transform(
      Table,
      fun ({amqqueue, Name, Dur, AutoDel, Excl, Args, Pid, SPids, MNodes}) ->
              {amqqueue, Name, Dur, AutoDel, Excl, Args, Pid, SPids, MNodes,
               undefined}
      end,
      [name, durable, auto_delete, exclusive_owner, arguments, pid,
       slave_pids, mirror_nodes, policy]).

sync_slave_pids() ->
    Tables = [rabbit_queue, rabbit_durable_queue],
    AddSyncSlavesFun =
        fun ({amqqueue, N, D, AD, Excl, Args, Pid, SPids, MNodes, Pol}) ->
                {amqqueue, N, D, AD, Excl, Args, Pid, SPids, [], MNodes, Pol}
        end,
    [ok = transform(T, AddSyncSlavesFun,
                    [name, durable, auto_delete, exclusive_owner, arguments,
                     pid, slave_pids, sync_slave_pids, mirror_nodes, policy])
     || T <- Tables],
    ok.

no_mirror_nodes() ->
    Tables = [rabbit_queue, rabbit_durable_queue],
    RemoveMirrorNodesFun =
        fun ({amqqueue, N, D, AD, O, A, Pid, SPids, SSPids, _MNodes, Pol}) ->
                {amqqueue, N, D, AD, O, A, Pid, SPids, SSPids, Pol}
        end,
    [ok = transform(T, RemoveMirrorNodesFun,
                    [name, durable, auto_delete, exclusive_owner, arguments,
                     pid, slave_pids, sync_slave_pids, policy])
     || T <- Tables],
    ok.

gm_pids() ->
    Tables = [rabbit_queue, rabbit_durable_queue],
    AddGMPidsFun =
        fun ({amqqueue, N, D, AD, O, A, Pid, SPids, SSPids, Pol}) ->
                {amqqueue, N, D, AD, O, A, Pid, SPids, SSPids, Pol, []}
        end,
    [ok = transform(T, AddGMPidsFun,
                    [name, durable, auto_delete, exclusive_owner, arguments,
                     pid, slave_pids, sync_slave_pids, policy, gm_pids])
     || T <- Tables],
    ok.

exchange_decorators() ->
    ok = exchange_decorators(rabbit_exchange),
    ok = exchange_decorators(rabbit_durable_exchange).

exchange_decorators(Table) ->
    transform(
      Table,
      fun ({exchange, Name, Type, Dur, AutoDel, Int, Args, Scratches,
            Policy}) ->
              {exchange, Name, Type, Dur, AutoDel, Int, Args, Scratches, Policy,
                {[], []}}
      end,
      [name, type, durable, auto_delete, internal, arguments, scratches, policy,
       decorators]).

policy_apply_to() ->
    transform(
      rabbit_runtime_parameters,
      fun ({runtime_parameters, Key = {_VHost, <<"policy">>, _Name}, Value}) ->
              ApplyTo = apply_to(proplists:get_value(<<"definition">>, Value)),
              {runtime_parameters, Key, [{<<"apply-to">>, ApplyTo} | Value]};
          ({runtime_parameters, Key, Value}) ->
              {runtime_parameters, Key, Value}
      end,
      [key, value]),
    rabbit_policy:invalidate(),
    ok.

apply_to(Def) ->
    case [proplists:get_value(K, Def) ||
             K <- [<<"federation-upstream-set">>, <<"ha-mode">>]] of
        [undefined, undefined] -> <<"all">>;
        [_,         undefined] -> <<"exchanges">>;
        [undefined, _]         -> <<"queues">>;
        [_,         _]         -> <<"all">>
    end.

queue_decorators() ->
    ok = queue_decorators(rabbit_queue),
    ok = queue_decorators(rabbit_durable_queue).

queue_decorators(Table) ->
    transform(
      Table,
      fun ({amqqueue, Name, Durable, AutoDelete, ExclusiveOwner, Arguments,
            Pid, SlavePids, SyncSlavePids, Policy, GmPids}) ->
              {amqqueue, Name, Durable, AutoDelete, ExclusiveOwner, Arguments,
               Pid, SlavePids, SyncSlavePids, Policy, GmPids, []}
      end,
      [name, durable, auto_delete, exclusive_owner, arguments, pid, slave_pids,
       sync_slave_pids, policy, gm_pids, decorators]).

internal_system_x() ->
    transform(
      rabbit_durable_exchange,
      fun ({exchange, Name = {resource, _, _, <<"amq.rabbitmq.", _/binary>>},
            Type, Dur, AutoDel, _Int, Args, Scratches, Policy, Decorators}) ->
              {exchange, Name, Type, Dur, AutoDel, true, Args, Scratches,
               Policy, Decorators};
          (X) ->
              X
      end,
      [name, type, durable, auto_delete, internal, arguments, scratches, policy,
       decorators]).

cluster_name() ->
    {atomic, ok} = mnesia:transaction(fun cluster_name_tx/0),
    ok.

cluster_name_tx() ->
    %% mnesia:transform_table/4 does not let us delete records
    T = rabbit_runtime_parameters,
    mnesia:write_lock_table(T),
    Ks = [K || {_VHost, <<"federation">>, <<"local-nodename">>} = K
                   <- mnesia:all_keys(T)],
    case Ks of
        []     -> ok;
        [K|Tl] -> [{runtime_parameters, _K, Name}] = mnesia:read(T, K, write),
                  R = {runtime_parameters, cluster_name, Name},
                  mnesia:write(T, R, write),
                  case Tl of
                      [] -> ok;
                      _  -> {VHost, _, _} = K,
                            error_logger:warning_msg(
                              "Multiple local-nodenames found, picking '~s' "
                              "from '~s' for cluster name~n", [Name, VHost])
                  end
    end,
    [mnesia:delete(T, K, write) || K <- Ks],
    ok.

down_slave_nodes() ->
    ok = down_slave_nodes(rabbit_queue),
    ok = down_slave_nodes(rabbit_durable_queue).

down_slave_nodes(Table) ->
    transform(
      Table,
      fun ({amqqueue, Name, Durable, AutoDelete, ExclusiveOwner, Arguments,
            Pid, SlavePids, SyncSlavePids, Policy, GmPids, Decorators}) ->
              {amqqueue, Name, Durable, AutoDelete, ExclusiveOwner, Arguments,
               Pid, SlavePids, SyncSlavePids, [], Policy, GmPids, Decorators}
      end,
      [name, durable, auto_delete, exclusive_owner, arguments, pid, slave_pids,
       sync_slave_pids, down_slave_nodes, policy, gm_pids, decorators]).

queue_state() ->
    ok = queue_state(rabbit_queue),
    ok = queue_state(rabbit_durable_queue).

queue_state(Table) ->
    transform(
      Table,
      fun ({amqqueue, Name, Durable, AutoDelete, ExclusiveOwner, Arguments,
            Pid, SlavePids, SyncSlavePids, DSN, Policy, GmPids, Decorators}) ->
              {amqqueue, Name, Durable, AutoDelete, ExclusiveOwner, Arguments,
               Pid, SlavePids, SyncSlavePids, DSN, Policy, GmPids, Decorators,
               live}
      end,
      [name, durable, auto_delete, exclusive_owner, arguments, pid, slave_pids,
       sync_slave_pids, down_slave_nodes, policy, gm_pids, decorators, state]).

recoverable_slaves() ->
    ok = recoverable_slaves(rabbit_queue),
    ok = recoverable_slaves(rabbit_durable_queue).

recoverable_slaves(Table) ->
    transform(
      Table, fun (Q) -> Q end, %% Don't change shape of record
      [name, durable, auto_delete, exclusive_owner, arguments, pid, slave_pids,
       sync_slave_pids, recoverable_slaves, policy, gm_pids, decorators,
       state]).

policy_version() ->
    ok = policy_version(rabbit_queue),
    ok = policy_version(rabbit_durable_queue).

policy_version(Table) ->
    transform(
      Table,
      fun ({amqqueue, Name, Durable, AutoDelete, ExclusiveOwner, Arguments,
            Pid, SlavePids, SyncSlavePids, DSN, Policy, GmPids, Decorators,
            State}) ->
              {amqqueue, Name, Durable, AutoDelete, ExclusiveOwner, Arguments,
               Pid, SlavePids, SyncSlavePids, DSN, Policy, GmPids, Decorators,
               State, 0}
      end,
      [name, durable, auto_delete, exclusive_owner, arguments, pid, slave_pids,
       sync_slave_pids, recoverable_slaves, policy, gm_pids, decorators, state,
       policy_version]).

slave_pids_pending_shutdown() ->
    ok = slave_pids_pending_shutdown(rabbit_queue),
    ok = slave_pids_pending_shutdown(rabbit_durable_queue).

slave_pids_pending_shutdown(Table) ->
    transform(
      Table,
      fun ({amqqueue, Name, Durable, AutoDelete, ExclusiveOwner, Arguments,
            Pid, SlavePids, SyncSlavePids, DSN, Policy, GmPids, Decorators,
            State, PolicyVersion}) ->
              {amqqueue, Name, Durable, AutoDelete, ExclusiveOwner, Arguments,
               Pid, SlavePids, SyncSlavePids, DSN, Policy, GmPids, Decorators,
               State, PolicyVersion, []}
      end,
      [name, durable, auto_delete, exclusive_owner, arguments, pid, slave_pids,
       sync_slave_pids, recoverable_slaves, policy, gm_pids, decorators, state,
       policy_version, slave_pids_pending_shutdown]).

operator_policies() ->
    ok = exchange_operator_policies(rabbit_exchange),
    ok = exchange_operator_policies(rabbit_durable_exchange),
    ok = queue_operator_policies(rabbit_queue),
    ok = queue_operator_policies(rabbit_durable_queue).

exchange_operator_policies(Table) ->
    transform(
      Table,
      fun ({exchange, Name, Type, Dur, AutoDel, Internal,
                      Args, Scratches, Policy, Decorators}) ->
              {exchange, Name, Type, Dur, AutoDel, Internal,
                         Args, Scratches, Policy, undefined, Decorators}
      end,
      [name, type, durable, auto_delete, internal, arguments, scratches, policy,
       operator_policy, decorators]).

queue_operator_policies(Table) ->
    transform(
      Table,
      fun ({amqqueue, Name, Durable, AutoDelete, ExclusiveOwner, Arguments,
            Pid, SlavePids, SyncSlavePids, DSN, Policy, GmPids, Decorators,
            State, PolicyVersion, SlavePidsPendingShutdown}) ->
              {amqqueue, Name, Durable, AutoDelete, ExclusiveOwner, Arguments,
               Pid, SlavePids, SyncSlavePids, DSN, Policy, undefined, GmPids,
               Decorators, State, PolicyVersion, SlavePidsPendingShutdown}
      end,
      [name, durable, auto_delete, exclusive_owner, arguments, pid, slave_pids,
       sync_slave_pids, recoverable_slaves, policy, operator_policy,
       gm_pids, decorators, state, policy_version, slave_pids_pending_shutdown]).


queue_vhost_field() ->
    ok = queue_vhost_field(rabbit_queue),
    ok = queue_vhost_field(rabbit_durable_queue),
    {atomic, ok} = mnesia:add_table_index(rabbit_queue, vhost),
    {atomic, ok} = mnesia:add_table_index(rabbit_durable_queue, vhost),
    ok.

queue_vhost_field(Table) ->
    transform(
      Table,
      fun ({amqqueue, Name = {resource, VHost, queue, _QName}, Durable, AutoDelete, ExclusiveOwner, Arguments,
            Pid, SlavePids, SyncSlavePids, DSN, Policy, OperatorPolicy, GmPids, Decorators,
            State, PolicyVersion, SlavePidsPendingShutdown}) ->
              {amqqueue, Name, Durable, AutoDelete, ExclusiveOwner, Arguments,
               Pid, SlavePids, SyncSlavePids, DSN, Policy, OperatorPolicy, GmPids, Decorators,
               State, PolicyVersion, SlavePidsPendingShutdown, VHost}
      end,
      [name, durable, auto_delete, exclusive_owner, arguments, pid, slave_pids,
       sync_slave_pids, recoverable_slaves, policy, operator_policy,
       gm_pids, decorators, state, policy_version, slave_pids_pending_shutdown, vhost]).

queue_options() ->
    ok = queue_options(rabbit_queue),
    ok = queue_options(rabbit_durable_queue),
    ok.

queue_options(Table) ->
    transform(
      Table,
      fun ({amqqueue, Name, Durable, AutoDelete, ExclusiveOwner, Arguments,
            Pid, SlavePids, SyncSlavePids, DSN, Policy, OperatorPolicy, GmPids, Decorators,
            State, PolicyVersion, SlavePidsPendingShutdown, VHost}) ->
              {amqqueue, Name, Durable, AutoDelete, ExclusiveOwner, Arguments,
               Pid, SlavePids, SyncSlavePids, DSN, Policy, OperatorPolicy, GmPids, Decorators,
               State, PolicyVersion, SlavePidsPendingShutdown, VHost, #{}}
      end,
      [name, durable, auto_delete, exclusive_owner, arguments, pid, slave_pids,
       sync_slave_pids, recoverable_slaves, policy, operator_policy,
       gm_pids, decorators, state, policy_version, slave_pids_pending_shutdown, vhost, options]).

%% Prior to 3.6.0, passwords were hashed using MD5, this populates
%% existing records with said default.  Users created with 3.6.0+ will
%% have internal_user.hashing_algorithm populated by the internal
%% authn backend.
user_password_hashing() ->
    transform(
      rabbit_user,
      fun ({internal_user, Username, Hash, Tags}) ->
              {internal_user, Username, Hash, Tags, rabbit_password_hashing_md5}
      end,
      [username, password_hash, tags, hashing_algorithm]).

topic_permission() ->
    create(rabbit_topic_permission,
        [{record_name, topic_permission},
         {attributes, [topic_permission_key, permission]},
         {disc_copies, [node()]}]).

exchange_options() ->
    ok = exchange_options(rabbit_exchange),
    ok = exchange_options(rabbit_durable_exchange).

exchange_options(Table) ->
    transform(
      Table,
      fun ({exchange, Name, Type, Dur, AutoDel, Internal,
            Args, Scratches, Policy, OperatorPolicy, Decorators}) ->
              {exchange, Name, Type, Dur, AutoDel, Internal,
               Args, Scratches, Policy, OperatorPolicy, Decorators, #{}}
      end,
      [name, type, durable, auto_delete, internal, arguments, scratches, policy,
       operator_policy, decorators, options]).

remove_explicit_default_exchange_bindings() ->
    Tab = rabbit_durable_queue,
    rabbit_table:wait([Tab]),
    %% Default exchange bindings are now implicit
    %% (not stored in the route tables).
    %% It should be safe to remove them outside of a
    %% transaction.
    Queues = mnesia:dirty_all_keys(Tab),
    N      = length(Queues),
    case N of
        0 -> ok;
        _ ->
            error_logger:info_msg("Will delete explicit default exchange bindings for ~p queues. "
                                  "This can take some time...", [N]),
            [rabbit_binding:remove_default_exchange_binding_rows_of(Q) || Q <- Queues]
    end,
    ok.

%%--------------------------------------------------------------------

transform(TableName, Fun, FieldList) ->
    rabbit_table:wait([TableName]),
    {atomic, ok} = mnesia:transform_table(TableName, Fun, FieldList),
    ok.

transform(TableName, Fun, FieldList, NewRecordName) ->
    rabbit_table:wait([TableName]),
    {atomic, ok} = mnesia:transform_table(TableName, Fun, FieldList,
                                          NewRecordName),
    ok.

create(Tab, TabDef) ->
    {atomic, ok} = mnesia:create_table(Tab, TabDef),
    ok.

%% Dumb replacement for rabbit_exchange:declare that does not require
%% the exchange type registry or worker pool to be running by dint of
%% not validating anything and assuming the exchange type does not
%% require serialisation.  NB: this assumes the
%% pre-exchange-scratch-space format
declare_exchange(XName, Type) ->
    X = {exchange, XName, Type, true, false, false, []},
    ok = mnesia:dirty_write(rabbit_durable_exchange, X).
