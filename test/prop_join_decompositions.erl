%% -------------------------------------------------------------------
%%
%% Copyright (c) 2016 Christopher Meiklejohn.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------
%%

-module(prop_join_decompositions).
-author("Vitor Enes Duarte <vitorenesduarte@gmail.com>").

-include_lib("proper/include/proper.hrl").
-include_lib("eunit/include/eunit.hrl").

-include("state_type.hrl").

%% common
-define(ACTOR, oneof([a, b, c])).
-define(P(T), {T, ?ACTOR}).
-define(L(T), list(?P(T))).

%% primitives
-define(TRUE, true).

%% counters
-define(INC, increment).
-define(DEC, decrement).
-define(INCDEC, oneof([?INC, ?DEC])).

%% sets
-define(ELEMENT, oneof([1, 2, 3])).
-define(ADD, {add, ?ELEMENT}).
-define(RMV, {rmv, ?ELEMENT}).
-define(ADDRMV, oneof([?ADD, ?RMV])).

%% registers
-define(SET, {set, undefined, ?ELEMENT}).


%% primitives
prop_boolean_decomposition() ->
    ?FORALL(L, ?L(?TRUE),
            check_decomposition(create(?BOOLEAN_TYPE, L))).
prop_boolean_redundant() ->
    ?FORALL(L, ?L(?TRUE),
            check_redundant(create(?BOOLEAN_TYPE, L))).

prop_max_int_decomposition() ->
    ?FORALL(L, ?L(?INC),
            check_decomposition(create(?MAX_INT_TYPE, L))).
prop_max_int_redundant() ->
    ?FORALL(L, ?L(?INC),
            check_redundant(create(?MAX_INT_TYPE, L))).


%% counters
prop_gcounter_decomposition() ->
    ?FORALL(L, ?L(?INC),
            check_decomposition(create(?GCOUNTER_TYPE, L))).
prop_gcounter_redundant() ->
    ?FORALL(L, ?L(?INC),
            check_redundant(create(?GCOUNTER_TYPE, L))).
prop_gcounter_irreducible() ->
    ?FORALL({L, A, B}, {?L(?INC), ?P(?INC), ?P(?INC)},
            begin
                check_irreducible(create(?GCOUNTER_TYPE, L),
                                  create(?GCOUNTER_TYPE, [A]),
                                  create(?GCOUNTER_TYPE, [B]))
            end
    ).

prop_pncounter_decomposition() ->
    ?FORALL(L, ?L(?INCDEC),
            check_decomposition(create(?PNCOUNTER_TYPE, L))).
prop_pncounter_redundant() ->
    ?FORALL(L, ?L(?INCDEC),
            check_redundant(create(?PNCOUNTER_TYPE, L))).

%% sets
prop_gset_decomposition() ->
    ?FORALL(L, ?L(?ADD),
            check_decomposition(create(?GSET_TYPE, L))).
prop_gset_redundant() ->
    ?FORALL(L, ?L(?ADD),
            check_redundant(create(?GSET_TYPE, L))).

prop_twopset_decomposition() ->
    ?FORALL(L, ?L(?ADDRMV),
            check_decomposition(create(?TWOPSET_TYPE, L))).
prop_twopset_redundant() ->
    ?FORALL(L, ?L(?ADDRMV),
            check_redundant(create(?TWOPSET_TYPE, L))).

prop_awset_decomposition() ->
    ?FORALL(L, ?L(?ADDRMV),
            check_decomposition(create(?AWSET_TYPE, L))).
prop_awset_redundant() ->
    ?FORALL(L, ?L(?ADDRMV),
            check_redundant(create(?AWSET_TYPE, L))).

prop_orset_decomposition() ->
    ?FORALL(L, ?L(?ADDRMV),
            check_decomposition(create(?ORSET_TYPE, L))).
prop_orset_redundant() ->
    ?FORALL(L, ?L(?ADDRMV),
            check_redundant(create(?ORSET_TYPE, L))).

%% registers
prop_mvregister_decomposition() ->
    ?FORALL(L, ?L(?SET),
            check_decomposition(create(?MVREGISTER_TYPE, L))).
prop_mvregister_redundant() ->
    ?FORALL(L, ?L(?SET),
            check_redundant(create(?MVREGISTER_TYPE, L))).


%% @private
check_decomposition({Type, _}=CRDT) ->
    Bottom = state_type:new(CRDT),

    %% the join of the decomposition should given the CRDT
    JD = Type:join_decomposition(CRDT),
    Merged = merge_all(Bottom, JD),
    Type:equal(CRDT, Merged).

%% @private
check_redundant({Type, _}=CRDT) ->
    Bottom = state_type:new(CRDT),

    ?IMPLIES(
        not Type:is_bottom(CRDT),
        begin
            JD = Type:join_decomposition(CRDT),

            %% if we remove one element from the decomposition,
            %% the rest is not enough to produce the CRDT
            Random = rand:uniform(length(JD)),
            Element = lists:nth(Random, JD),
            Rest = merge_all(Bottom, JD -- [Element]),
            Type:is_strict_inflation(Rest, CRDT)
       end
    ).

%% @private
check_irreducible({Type, _}=CRDT, A, B) ->
    Merged = Type:merge(A, B),
    Tests = lists:map(
        fun(Irreducible) ->
            Test = ?IMPLIES(
                Type:equal(Merged, Irreducible),
                Type:equal(A, Irreducible) orelse
                Type:equal(B, Irreducible)
            ),

            {Irreducible, Test}
        end,
        Type:join_decomposition(CRDT)
    ),

    conjunction(Tests).

%% @private
merge_all({Type, _}=Bottom, L) ->
    lists:foldl(
        fun(Irreducible, Acc) ->
            Type:merge(Irreducible, Acc)
        end,
        Bottom,
        L
    ).

%% @private
create(Type, L) ->
    Actors = lists:usort([Actor || {_Op, Actor} <- L]),
    OpsPerActor = lists:foldl(
        fun(Actor, Acc) ->
            Ops = lists:filter(
                fun({_Op, OpActor}) ->
                    Actor == OpActor
                end,
                L
            ),
            orddict:store(Actor, Ops, Acc)
        end,
        orddict:new(),
        Actors
    ),
    CRDTList = orddict:fold(
        fun(Actor, Ops, Acc) ->
            CRDT = lists:foldl(
                fun({Op, _Actor}, CRDT0) ->
                    {ok, CRDT1} = Type:mutate(Op, Actor, CRDT0),
                    CRDT1
                end,
                Type:new(),
                Ops
            ),

            [CRDT | Acc]
        end,
        [],
        OpsPerActor
    ),

    merge_all(Type:new(), CRDTList).
