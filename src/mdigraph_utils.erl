%%
%% %CopyrightBegin%
%% 
%% Copyright Ericsson AB 1999-2012. All Rights Reserved.
%% 
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%% 
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%% 
%% %CopyrightEnd%
%%
-module(mdigraph_utils).

%%% Operations on directed (and undirected) graphs.
%%%
%%% Implementation based on Launchbury, John: Graph Algorithms with a 
%%% Functional Flavour, in Jeuring, Johan, and Meijer, Erik (Eds.): 
%%% Advanced Functional Programming, Lecture Notes in Computer 
%%% Science 925, Springer Verlag, 1995.

-export([components/1, strong_components/1, cyclic_strong_components/1, 
	 reachable/2, reachable_neighbours/2, 
	 reaching/2, reaching_neighbours/2,
	 topsort/1, is_acyclic/1, 
         arborescence_root/1, is_arborescence/1, is_tree/1, 
         loop_vertices/1,
	 subgraph/2, subgraph/3, condensation/1,
	 preorder/1, postorder/1]).

%%
%%  A convenient type alias
%%
-type vertex() :: mdigraph:vertex().
-type vertices() :: [mdigraph:vertex()].
-type mdigraph() :: mdigraph:mdigraph().

%%
%%  Exported functions
%%

-spec components(Digraph) -> Components when
      Digraph :: mdigraph(),
      Components :: vertices().

components(G) ->
    forest(G, fun inout/3).

-spec strong_components(Digraph) -> StrongComponents when
      Digraph :: mdigraph(),
      StrongComponents :: vertices().

strong_components(G) ->
    forest(G, fun in/3, revpostorder(G)).

-spec cyclic_strong_components(Digraph) -> StrongComponents when
      Digraph :: mdigraph(),
      StrongComponents :: vertices().

cyclic_strong_components(G) ->
    remove_singletons(strong_components(G), G, []).

-spec reachable(Vertices, Digraph) -> Reachable when
      Digraph :: mdigraph(),
      Vertices :: vertices(),
      Reachable :: vertices().

reachable(Vs, G) when is_list(Vs) ->
    lists:append(forest(G, fun out/3, Vs, first)).

-spec reachable_neighbours(Vertices, Digraph) -> Reachable when
      Digraph :: mdigraph(),
      Vertices :: vertices(),
      Reachable :: vertices().

reachable_neighbours(Vs, G) when is_list(Vs) ->
    lists:append(forest(G, fun out/3, Vs, not_first)).

-spec reaching(Vertices, Digraph) -> Reaching when
      Digraph :: mdigraph(),
      Vertices :: vertices(),
      Reaching :: vertices().

reaching(Vs, G) when is_list(Vs) ->
    lists:append(forest(G, fun in/3, Vs, first)).

-spec reaching_neighbours(Vertices, Digraph) -> Reaching when
      Digraph :: mdigraph(),
      Vertices :: vertices(),
      Reaching :: vertices().

reaching_neighbours(Vs, G) when is_list(Vs) ->
    lists:append(forest(G, fun in/3, Vs, not_first)).

-spec topsort(Digraph) -> Vertices | 'false' when
      Digraph :: mdigraph(),
      Vertices :: vertices().

topsort(G) ->
    L = revpostorder(G),
    case length(forest(G, fun in/3, L)) =:= length(mdigraph:vertices(G)) of
	true  -> L;
	false -> false
    end.

-spec is_acyclic(Digraph) -> boolean() when
      Digraph :: mdigraph().

is_acyclic(G) ->
    loop_vertices(G) =:= [] andalso topsort(G) =/= false.

-spec arborescence_root(Digraph) -> 'no' | {'yes', Root} when
      Digraph :: mdigraph(),
      Root :: vertex().

arborescence_root(G) ->
    case mdigraph:no_edges(G) =:= mdigraph:no_vertices(G) - 1 of
        true ->
            try
                F = fun(V, Z) ->
                            case mdigraph:in_degree(G, V) of
                                1 -> Z;
                                0 when Z =:= [] -> [V]
                            end
                    end,
                [Root] = lists:foldl(F, [], mdigraph:vertices(G)),
                {yes, Root}
            catch _:_ ->
                no
            end;
        false ->
            no
    end.

-spec is_arborescence(Digraph) -> boolean() when
      Digraph :: mdigraph().

is_arborescence(G) ->
    arborescence_root(G) =/= no.

-spec is_tree(Digraph) -> boolean() when
      Digraph :: mdigraph().

is_tree(G) ->
    (mdigraph:no_edges(G) =:= mdigraph:no_vertices(G) - 1)
    andalso (length(components(G)) =:= 1).

-spec loop_vertices(Digraph) -> Vertices when
      Digraph :: mdigraph(),
      Vertices :: vertices().

loop_vertices(G) ->
    [V || V <- mdigraph:vertices(G), is_reflexive_vertex(V, G)].

-spec subgraph(Digraph, Vertices) -> SubGraph when
      Digraph :: mdigraph(),
      Vertices :: vertices(),
      SubGraph :: mdigraph().

subgraph(G, Vs) ->
    try
	subgraph_opts(G, Vs, [])
    catch
	throw:badarg ->
	    erlang:error(badarg)
    end.

-spec subgraph(Digraph, Vertices, Options) -> SubGraph when
      Digraph :: mdigraph(),
      SubGraph :: mdigraph(),
      Vertices :: vertices(),
      Options :: [{'type', SubgraphType} | {'keep_labels', boolean()}],
      SubgraphType :: 'inherit' | [mdigraph:d_type()].

subgraph(G, Vs, Opts) ->
    try
	subgraph_opts(G, Vs, Opts)
    catch
	throw:badarg ->
	    erlang:error(badarg)
    end.

-spec condensation(Digraph) -> CondensedDigraph when
      Digraph :: mdigraph(),
      CondensedDigraph :: mdigraph().

condensation(G) ->
    SCs = strong_components(G),
    %% Each component is assigned a number.
    %% V2I: from vertex to number.
    %% I2C: from number to component.
    V2I = ets:new(condensation, []),
    I2C = ets:new(condensation, []),
    CFun = fun(SC, N) -> lists:foreach(fun(V) -> 
					  true = ets:insert(V2I, {V,N}) 
				       end, 
				       SC), 
			 true = ets:insert(I2C, {N, SC}), 
			 N + 1 
	   end,
    lists:foldl(CFun, 1, SCs),
    SCG = subgraph_opts(G, [], []),
    lists:foreach(fun(SC) -> condense(SC, G, SCG, V2I, I2C) end, SCs),
    ets:delete(V2I),
    ets:delete(I2C),
    SCG.

-spec preorder(Digraph) -> Vertices when
      Digraph :: mdigraph(),
      Vertices :: vertices().

preorder(G) ->
    lists:reverse(revpreorder(G)).

-spec postorder(Digraph) -> Vertices when
      Digraph :: mdigraph(),
      Vertices :: vertices().

postorder(G) ->
    lists:reverse(revpostorder(G)).

%%
%%  Local functions
%%

forest(G, SF) ->
    forest(G, SF, mdigraph:vertices(G)).

forest(G, SF, Vs) ->
    forest(G, SF, Vs, first).

forest(G, SF, Vs, HandleFirst) ->
    T = ets:new(forest, [set]),
    F = fun(V, LL) -> pretraverse(HandleFirst, V, SF, G, T, LL) end,
    LL = lists:foldl(F, [], Vs),
    ets:delete(T),
    LL.

pretraverse(first, V, SF, G, T, LL) ->
    ptraverse([V], SF, G, T, [], LL);
pretraverse(not_first, V, SF, G, T, LL) ->
    case ets:member(T, V) of
	false -> ptraverse(SF(G, V, []), SF, G, T, [], LL);
	true  -> LL
    end.

ptraverse([V | Vs], SF, G, T, Rs, LL) ->
    case ets:member(T, V) of
	false ->
	    ets:insert(T, {V}),
	    ptraverse(SF(G, V, Vs), SF, G, T, [V | Rs], LL);
	true ->
	    ptraverse(Vs, SF, G, T, Rs, LL)
    end;
ptraverse([], _SF, _G, _T, [], LL) ->
    LL;
ptraverse([], _SF, _G, _T, Rs, LL) ->
    [Rs | LL].

revpreorder(G) ->
    lists:append(forest(G, fun out/3)).

revpostorder(G) ->
    T = ets:new(forest, [set]),
    L = posttraverse(mdigraph:vertices(G), G, T, []),
    ets:delete(T),
    L.

posttraverse([V | Vs], G, T, L) ->
    L1 = case ets:member(T, V) of
	     false ->
		 ets:insert(T, {V}),
		 [V | posttraverse(out(G, V, []), G, T, L)];
	     true ->
		 L
	 end,
    posttraverse(Vs, G, T, L1);
posttraverse([], _G, _T, L) ->
    L.

in(G, V, Vs) ->
    mdigraph:in_neighbours(G, V) ++ Vs.

out(G, V, Vs) ->
    mdigraph:out_neighbours(G, V) ++ Vs.

inout(G, V, Vs) ->
    in(G, V, out(G, V, Vs)).

remove_singletons([C=[V] | Cs], G, L) ->
    case is_reflexive_vertex(V, G) of
	true  -> remove_singletons(Cs, G, [C | L]);
	false -> remove_singletons(Cs, G, L)
    end;
remove_singletons([C | Cs], G, L) ->
    remove_singletons(Cs, G, [C | L]);
remove_singletons([], _G, L) ->
    L.

is_reflexive_vertex(V, G) ->
    lists:member(V, mdigraph:out_neighbours(G, V)).

subgraph_opts(G, Vs, Opts) ->
    subgraph_opts(Opts, inherit, true, G, Vs).

subgraph_opts([{type, Type} | Opts], _Type0, Keep, G, Vs)
  when Type =:= inherit; is_list(Type) ->
    subgraph_opts(Opts, Type, Keep, G, Vs);
subgraph_opts([{keep_labels, Keep} | Opts], Type, _Keep0, G, Vs)
  when is_boolean(Keep) ->
    subgraph_opts(Opts, Type, Keep, G, Vs);
subgraph_opts([], inherit, Keep, G, Vs) ->
    Info = mdigraph:info(G),
    {_, {_, Cyclicity}} = lists:keysearch(cyclicity, 1, Info),
    {_, {_, Protection}} = lists:keysearch(protection, 1, Info),
    subgraph(G, Vs, [Cyclicity, Protection], Keep);
subgraph_opts([], Type, Keep, G, Vs) ->
    subgraph(G, Vs, Type, Keep);
subgraph_opts(_, _Type, _Keep, _G, _Vs) ->
    throw(badarg).

subgraph(G, Vs, Type, Keep) ->
    try mdigraph:new(Type) of
	SG ->
	    lists:foreach(fun(V) -> subgraph_vertex(V, G, SG, Keep) end, Vs),
	    EFun = fun(V) -> lists:foreach(fun(E) -> 
					       subgraph_edge(E, G, SG, Keep) 
                                           end,
                                           mdigraph:out_edges(G, V))
		   end,
	    lists:foreach(EFun, mdigraph:vertices(SG)),
	    SG
    catch
	error:badarg ->
	    throw(badarg)
    end.

subgraph_vertex(V, G, SG, Keep) ->
    case mdigraph:vertex(G, V) of
	false -> ok;
	_ when not Keep -> mdigraph:add_vertex(SG, V);
	{_V, Label} when Keep -> mdigraph:add_vertex(SG, V, Label)
    end.

subgraph_edge(E, G, SG, Keep) ->
    {_E, V1, V2, Label} = mdigraph:edge(G, E),
    case mdigraph:vertex(SG, V2) of
	false -> ok;
	_ when not Keep -> mdigraph:add_edge(SG, E, V1, V2, []);
	_ when Keep -> mdigraph:add_edge(SG, E, V1, V2, Label)
    end.

condense(SC, G, SCG, V2I, I2C) ->
    T = ets:new(condense, []),
    NFun = fun(Neighbour) ->
		   [{_V,I}] = ets:lookup(V2I, Neighbour),
		   ets:insert(T, {I})
	   end,
    VFun = fun(V) -> lists:foreach(NFun, mdigraph:out_neighbours(G, V)) end,
    lists:foreach(VFun, SC),
    mdigraph:add_vertex(SCG, SC),
    condense(ets:first(T), T, SC, G, SCG, I2C),
    ets:delete(T).

condense('$end_of_table', _T, _SC, _G, _SCG, _I2C) ->
    ok;
condense(I, T, SC, G, SCG, I2C) ->
    [{_,C}] = ets:lookup(I2C, I),
    mdigraph:add_vertex(SCG, C),
    [mdigraph:add_edge(SCG, SC, C) || C =/= SC],
    condense(ets:next(T, I), T, SC, G, SCG, I2C).
