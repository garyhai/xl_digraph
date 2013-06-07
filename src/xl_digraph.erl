%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 1996-2011. All Rights Reserved.
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
-module(xl_digraph).

-export([new/0, new/1, new/2, delete/1, info/1]).

-export([add_vertex/1, add_vertex/2, add_vertex/3]).
-export([del_vertex/2, del_vertices/2]).
-export([vertex/2, no_vertices/1, vertices/1]).
-export([source_vertices/1, sink_vertices/1]).

-export([add_edge/3, add_edge/4, add_edge/5]).
-export([del_edge/2, del_edges/2, del_path/3]).
-export([edge/2, no_edges/1, edges/1]).

-export([out_neighbours/2, in_neighbours/2]).
-export([out_edges/2, in_edges/2, edges/2]).
-export([out_degree/2, in_degree/2]).
-export([get_path/3, get_cycle/2]).

-export([get_short_path/3, get_short_cycle/2]).

-export_type([xl_digraph/0, d_type/0, vertex/0]).

-record(xl_digraph, {vtab = notable :: ets:tab(),
                     etab = notable :: ets:tab(),
                     ntab = notable :: ets:tab(),
                     cyclic = true  :: boolean()}).
%% A declaration equivalent to the following one is hard-coded in erl_types.
%% That declaration contains hard-coded information about the #digraph{}
%% record and the types of its fields.  So, please make sure that any
%% changes to its structure are also propagated to erl_types.erl.
%%
%% xl_digraph has no hard-coded declaration in erl_types.
-opaque xl_digraph() :: #xl_digraph{}.

-type edge()    :: term().
-type label()   :: term().
-type vertex()  :: term().

-record(edge, {edge, in, out, label}).
-record(neighbour, {name, edge}).

-type add_edge_err_rsn() :: {'bad_edge', Path :: [vertex()]}
                          | {'bad_vertex', V :: vertex()}.

%%
%% Type is a list of
%%  protected | private
%%  acyclic | cyclic
%%
%%  default is [cyclic,protected]
%%
-type d_protection() :: 'private' | 'protected'.
-type d_cyclicity()  :: 'acyclic' | 'cyclic'.
-type d_type()       :: d_cyclicity() | d_protection().

-spec new() -> xl_digraph().

new() -> new([]).

-spec new(Type) -> xl_digraph() when
      Type :: [d_type()].
new(Type) ->
    new(get_random_string(10, "abcdef01234567890"), Type).

-spec new(string(), Type) -> xl_digraph() when
      Type :: [d_type()].
new(Name, Type) ->
    case check_type(Type, protected, []) of
	{_Access, Ts} ->
	    V = list_to_atom("vertices-" ++ Name),
	    E = list_to_atom("edges-" ++ Name),
	    N = list_to_atom("neighbours-" ++ Name),
	    mnesia:create_table(V, [{type,set}]),
	    mnesia:create_table(E, [{type,set},
                                    {attributes,
                                     record_info(fields, edge)}]),
	    mnesia:create_table(N, [{type,bag},
                                    {attributes,
                                     record_info(fields, neighbour)}]),
	    Fun = fun() ->
			  mnesia:write({N, '$vid', 0}),
			  mnesia:write({N, '$eid', 0})
		  end,
	    {atomic, _} = mnesia:transaction(Fun),
	    set_type(Ts, #xl_digraph{vtab=V, etab=E, ntab=N});
	error ->
	    erlang:error(badarg)
    end.

%% generate a random string to be used in tables name
-spec get_random_string(integer(), string() ) -> [].
get_random_string(Length, AllowedChars) ->
    %% set seed for random genarator
    {A1, A2, A3} = now(),
    random:seed(A1, A2, A3),
    lists:foldl(fun(_, Acc) ->
                        [lists:nth(random:uniform(length(AllowedChars)),
                                   AllowedChars)]
                            ++ Acc
                end, [], lists:seq(1, Length)).


%%
%% Check type of graph
%%
%-spec check_type([d_type()], d_protection(), [{'cyclic', boolean()}]) ->
%       	{d_protection(), [{'cyclic', boolean()}]}.

check_type([acyclic|Ts], A, L) ->
    check_type(Ts, A,[{cyclic,false} | L]);
check_type([cyclic | Ts], A, L) ->
    check_type(Ts, A, [{cyclic,true} | L]);
check_type([protected | Ts], _, L) ->
    check_type(Ts, protected, L);
check_type([private | Ts], _, L) ->
    check_type(Ts, private, L);
check_type([], A, L) -> {A, L};
check_type(_, _, _) -> error.

%%
%% Set graph type
%%
-spec set_type([{'cyclic', boolean()}], xl_digraph()) -> xl_digraph().

set_type([{cyclic,V} | Ks], G) ->
    set_type(Ks, G#xl_digraph{cyclic = V});
set_type([], G) -> G.


%% Data access functions

-spec delete(G) -> 'true' when
      G :: xl_digraph().

delete(G) ->
    case 
	begin
	    mnesia:delete_table(G#xl_digraph.vtab),
	    mnesia:delete_table(G#xl_digraph.etab),
	    mnesia:delete_table(G#xl_digraph.ntab)
	end of
	{atomic, ok} -> true;
	{aborted, Reason} -> {aborted, Reason}
    end.

-spec info(G) -> InfoList when
      G :: xl_digraph(),
      InfoList :: [{'cyclicity', Cyclicity :: d_cyclicity()} |
                   {'memory', NoWords :: non_neg_integer()} |
                   {'protection', Protection :: d_protection()}].

info(G) ->
    VT = G#xl_digraph.vtab,
    ET = G#xl_digraph.etab,
    NT = G#xl_digraph.ntab,
    Cyclicity = case G#xl_digraph.cyclic of
		    true  -> cyclic;
		    false -> acyclic
		end,
%    Protection = ets:info(VT, protection),
    Protection = protected,     % TODO: Fake a protection response for now
    Memory = mnesia:table_info(VT, memory) +
        mnesia:table_info(ET, memory) +
        mnesia:table_info(NT, memory),
    [{cyclicity, Cyclicity}, {memory, Memory}, {protection, Protection}].

-spec add_vertex(G) -> vertex() when
      G :: xl_digraph().

add_vertex(G) ->
    do_add_vertex({new_vertex_id(G), []}, G).

-spec add_vertex(G, V) -> vertex() when
      G :: xl_digraph(),
      V :: vertex().

add_vertex(G, V) ->
    do_add_vertex({V, []}, G).

-spec add_vertex(G, V, Label) -> vertex() when
      G :: xl_digraph(),
      V :: vertex(),
      Label :: label().

add_vertex(G, V, D) ->
    do_add_vertex({V, D}, G).

-spec del_vertex(G, V) -> 'true' | {abort, Reason::any()}  when
      G :: xl_digraph(),
      V :: vertex().

del_vertex(G, V) ->
    case do_del_vertex(V, G) of
	{atomic, ok} ->
	    true;
	{aborted, Reason} ->
	    {abort, Reason}
    end.

-spec del_vertices(G, Vertices) -> 'true' when
      G :: xl_digraph(),
      Vertices :: [vertex()].

del_vertices(G, Vs) -> 
    do_del_vertices(Vs, G).

-spec vertex(G, V) -> {V, Label} | 'false' when
      G :: xl_digraph(),
      V :: vertex(),
      Label :: label().

vertex(G, V) ->
    Fun = 
	fun() ->
		case mnesia:read(G#xl_digraph.vtab, V) of
		    [] -> false;
		    [{_Tbl, Vertex, Label}] -> {Vertex, Label}
		end
	end,
    {atomic, Result} = mnesia:transaction(Fun),
    Result.

-spec no_vertices(G) -> non_neg_integer() when
      G :: xl_digraph().

no_vertices(G) ->
    mnesia:table_info(G#xl_digraph.vtab, size).

-spec vertices(G) -> Vertices when
      G :: xl_digraph(),
      Vertices :: [vertex()].

vertices(G) ->
    Fun = fun()->
                  mnesia:select(G#xl_digraph.vtab,
                                [{{'_', '$1', '_'}, [], ['$1']}])
          end,
    {atomic, Result} = mnesia:transaction(Fun),
    Result.

-spec source_vertices(xl_digraph()) -> [vertex()].

source_vertices(G) ->
    collect_vertices(G, in).

-spec sink_vertices(xl_digraph()) -> [vertex()].

sink_vertices(G) ->
    collect_vertices(G, out).

degree(G, V, InOrOut) ->
    Fun = fun() -> mnesia:read(G#xl_digraph.ntab, {InOrOut, V}) end,
    {atomic, A} = mnesia:transaction(Fun),
    length(A).

-spec in_degree(G, V) -> non_neg_integer() when
      G :: xl_digraph(),
      V :: vertex().

in_degree(G, V) ->
    degree(G, V, in).

neighbours(G, V, InOrOut, Index) ->
    ET = G#xl_digraph.etab,
    NT = G#xl_digraph.ntab,
    Fun = fun() -> mnesia:read(NT, {InOrOut, V}) end,
    {atomic, A} = mnesia:transaction(Fun),
    collect_elems(A, ET, Index).

-spec in_neighbours(G, V) -> Vertex when
      G :: xl_digraph(),
      V :: vertex(),
      Vertex :: [vertex()].

in_neighbours(G, V) ->
    neighbours(G, V, in, 3).

-spec in_edges(G, V) -> Edges when
      G :: xl_digraph(),
      V :: vertex(),
      Edges :: [edge()].

in_edges(G, V) ->
    Fun = fun() ->
                  mnesia:select(G#xl_digraph.ntab,
                                [{{'$1', {in, V}, '$2'}, [], ['$2']}])
          end,
    {atomic, Result} = mnesia:transaction(Fun),
    Result.

-spec out_degree(G, V) -> non_neg_integer() when
      G :: xl_digraph(),
      V :: vertex().

out_degree(G, V) ->
    degree(G, V, out).

-spec out_neighbours(G, V) -> Vertices when
      G :: xl_digraph(),
      V :: vertex(),
      Vertices :: [vertex()].

out_neighbours(G, V) ->
    neighbours(G, V, out, 4).

-spec out_edges(G, V) -> Edges when
      G :: xl_digraph(),
      V :: vertex(),
      Edges :: [edge()].

out_edges(G, V) ->
    Fun = fun() ->
                  mnesia:select(G#xl_digraph.ntab,
                                [{{'$1', {out, V}, '$2'}, [], ['$2']}])
          end,
    {atomic,Result} = mnesia:transaction(Fun),
    Result.

-spec add_edge(G, V1, V2) -> edge() | {'error', add_edge_err_rsn()} when
      G :: xl_digraph(),
      V1 :: vertex(),
      V2 :: vertex().

add_edge(G, V1, V2) ->
    do_add_edge({new_edge_id(G), V1, V2, []}, G).

-spec add_edge(G, V1, V2, Label) -> edge() | {'error', add_edge_err_rsn()} when
      G :: xl_digraph(),
      V1 :: vertex(),
      V2 :: vertex(),
      Label :: label().

add_edge(G, V1, V2, D) ->
    do_add_edge({new_edge_id(G), V1, V2, D}, G).

-spec add_edge(G, E, V1, V2, Label) -> edge() | {'error', add_edge_err_rsn()} when
      G :: xl_digraph(),
      E :: edge(),
      V1 :: vertex(),
      V2 :: vertex(),
      Label :: label().

add_edge(G, E, V1, V2, D) ->
    do_add_edge({E, V1, V2, D}, G).

-spec del_edge(G, E) -> 'true' when
      G :: xl_digraph(),
      E :: edge().

del_edge(G, E) ->
    do_del_edges([E], G).

-spec del_edges(G, Edges) -> 'true' when
      G :: xl_digraph(),
      Edges :: [edge()].

del_edges(G, Es) ->
    do_del_edges(Es, G).

-spec no_edges(G) -> non_neg_integer() when
      G :: xl_digraph().

no_edges(G) ->
    mnesia:table_info(G#xl_digraph.etab, size).

-spec edges(G) -> Edges when
      G :: xl_digraph(),
      Edges :: [edge()].

edges(G) ->
    Fun = fun()->
                  mnesia:select(G#xl_digraph.etab,
                                [{{'_', '$1', '_', '_', '_'}, [], ['$1']}])
          end,
    {atomic, Result} = mnesia:transaction(Fun),
    Result.

-spec edges(G, V) -> Edges when
      G :: xl_digraph(),
      V :: vertex(),
      Edges :: [edge()].

edges(G, V) ->
    Fun = fun()->
                  mnesia:select(G#xl_digraph.ntab,
                                [{{'_',{out, V},'$1'}, [], ['$1']},
                                 {{{in, V}, '$1'}, [], ['$1']}])
          end,
    {atomic, Result} = mnesia:transaction(Fun),
    Result.

-spec edge(G, E) -> {E, V1, V2, Label} | 'false' when
      G :: xl_digraph(),
      E :: edge(),
      V1 :: vertex(),
      V2 :: vertex(),
      Label :: label().

edge(G, E) ->
    Fun = fun()->
                  mnesia:read(G#xl_digraph.etab,E)
          end,
    {atomic, A} = mnesia:transaction(Fun),

    case A of
        [] -> false;
        [{_, Edge, V1, V2, Label}] -> {Edge, V1, V2, Label}
    end.

%%
%% Generate a "unique" edge identifier (relative to this graph)
%%
-spec new_edge_id(xl_digraph()) -> edge().

new_edge_id(G) ->
    ['$e' | get_id(G, '$eid')].

%%
%% Generate a "unique" vertex identifier (relative to this graph)
%%
-spec new_vertex_id(xl_digraph()) -> vertex().

new_vertex_id(G) ->
    ['$v' | get_id(G, '$vid')].

%%
%% Generate a "unique" identifier (relative to this graph)
%%
get_id(G, Id) ->
    Fun = fun() ->
                  NT = G#xl_digraph.ntab,
                  [{Tab, Id, K}] = mnesia:read(NT, Id),
                  ok = mnesia:delete_object(NT, {Tab, Id, K}, write),
                  ok = mnesia:write({NT, Id, K + 1}),
                  K
          end,
    {atomic, Result} = mnesia:transaction(Fun),
    Result.

%%
%% Collect elements for a index in a tuple
%%
collect_elems(Keys, Table, Index) ->
    collect_elems(Keys, Table, Index, []).

collect_elems([{_, _, Key}|Keys], Table, Index, Acc) ->
    collect_elems(Keys, Table, Index,
		  [lookup(Table, Key, Index)|Acc]);
collect_elems([], _, _, Acc) -> Acc.

%% replacement for ets:lookup_element(Table, Key, Index),
%%  probably there is a better way of doing lookup
lookup(Table, Key) ->
    %%{atomic, R} = mnesia:transaction(fun() -> mnesia:read(Table, Key) end),
    mnesia:ets(fun() -> mnesia:read(Table, Key) end).
lookup(Table, Key, Index) ->
    [R] = lookup(Table, Key),
    element(Index, R).

-spec do_add_vertex({vertex(), label()}, xl_digraph()) -> vertex().
do_add_vertex({V, Label}, G) ->
    Fun = fun()->
                  mnesia:write(G#xl_digraph.vtab,
                               {G#xl_digraph.vtab, V, Label}, write)
          end,
    mnesia:transaction(Fun),
    V.

%%
%% Collect either source or sink vertices.
%%
collect_vertices(G, Type) ->
    Vs = vertices(G),
    lists:foldl(fun(V, A) ->
                        T = mnesia:transaction(fun() ->
                              mnesia:read({G#xl_digraph.ntab, {Type,V}})
                              end),
                        case T of
                            {atomic, []} -> [V|A];
                            {atomic, [_|_]} -> A
                        end
                end, [], Vs).

%%
%% Delete vertices
%%
do_del_vertices([V | Vs], G) ->
    do_del_vertex(V, G),
    do_del_vertices(Vs, G);
do_del_vertices([], #xl_digraph{}) -> true.

do_del_vertex(V, G) ->
    {atomic, E1} = mnesia:transaction(fun() -> 
            mnesia:read({G#xl_digraph.ntab, {in, V}}) 
        end),
    do_del_nedges(E1, G),

    {atomic, E2} = mnesia:transaction(fun() -> 
            mnesia:read({G#xl_digraph.ntab, {out, V}}) 
        end),
    do_del_nedges(E2, G),

    mnesia:transaction(fun() ->
        mnesia:delete({G#xl_digraph.vtab, V})
    end).

do_del_nedges([{_, _, E}|Ns], G) ->
    {atomic, R} = mnesia:transaction(fun() ->
        mnesia:read({G#xl_digraph.etab, E})
    end),
    case R of
        [{_, E, V1, V2, _}] ->
            do_del_edge(E, V1, V2, G),
            do_del_nedges(Ns, G);
        [] -> % cannot happen
            do_del_nedges(Ns, G)
    end;
do_del_nedges([], #xl_digraph{}) -> true.

%%
%% Delete edges
%%
do_del_edges([E|Es], G) ->
    case lookup(G#xl_digraph.etab, E) of
	[{_,E,V1,V2,_}] ->
	    do_del_edge(E,V1,V2,G),
	    do_del_edges(Es, G);
	[] ->
	    do_del_edges(Es, G)
    end;
do_del_edges([], #xl_digraph{}) -> true.

do_del_edge(E, _V1, _V2, G) ->
    {atomic, Result} =
	mnesia:transaction(
	  fun() ->
		  A = mnesia:select(G#xl_digraph.ntab,
                                    [{{'$1','$2', E}, [], [{{'$1','$2', E}}]}],
                                    write),
		  lists:foreach(fun(R) -> mnesia:delete_object(R) end, A),
		  [ER] = mnesia:read({G#xl_digraph.etab, E}),
		  mnesia:delete_object(ER)
	  end),
    Result.

-spec rm_edges([vertex(),...], xl_digraph()) -> 'true'.

rm_edges([V1, V2|Vs], G) ->
    rm_edge(V1, V2, G),
    rm_edges([V2|Vs], G);
rm_edges(_, _) -> true.

-spec rm_edge(vertex(), vertex(), xl_digraph()) -> 'ok'.

rm_edge(V1, V2, G) ->
    Es = out_edges(G, V1),
    rm_edge_0(Es, V1, V2, G).
    
rm_edge_0([E|Es], V1, V2, G) ->
    case lookup(G#xl_digraph.etab, E) of
	[{_, E, V1, V2, _}]  ->
            do_del_edge(E, V1, V2, G),
	    rm_edge_0(Es, V1, V2, G);
	_ ->
	    rm_edge_0(Es, V1, V2, G)
    end;
rm_edge_0([], _, _, #xl_digraph{}) -> ok.
    
%%
%% Check that endpoints exist
%%
-spec do_add_edge({edge(), vertex(), vertex(), label()}, xl_digraph()) ->
	edge() | {'error', add_edge_err_rsn()}.

do_add_edge({E, V1, V2, Label}, G) ->
    %% @todo probably need to replace ets:member with some mnesia func.
    case ets:member(G#xl_digraph.vtab, V1) of
	false -> {error, {bad_vertex, V1}};
	true  ->
	    case ets:member(G#xl_digraph.vtab, V2) of
		false -> {error, {bad_vertex, V2}};
                true ->
                    case other_edge_exists(G, E, V1, V2) of
                        true -> {error, {bad_edge, [V1, V2]}};
                        false when G#xl_digraph.cyclic =:= false ->
                            acyclic_add_edge(E, V1, V2, Label, G);
                        false ->
                            do_insert_edge(E, V1, V2, Label, G)
                    end
	    end
    end.

other_edge_exists(#xl_digraph{etab = ET}, E, V1, V2) ->
    case lookup(ET, E) of
        [{_, E, Vert1, Vert2, _}] when Vert1 =/= V1; Vert2 =/= V2 ->
            true;
        _ ->
            false
    end.

-spec do_insert_edge(edge(),
                     vertex(),
                     vertex(),
                     label(),
                     xl_digraph()) -> edge().

do_insert_edge(E, V1, V2, Label, #xl_digraph{ntab=NT, etab=ET}) ->
    Fun = fun() ->
                  mnesia:write({NT, {out, V1}, E}),
                  mnesia:write({NT, {in, V2}, E}),
                  mnesia:write({ET, E, V1, V2, Label})
          end,
    {atomic, _} = mnesia:transaction(Fun),
    E.

-spec acyclic_add_edge(edge(), vertex(), vertex(), label(), xl_digraph()) ->
	edge() | {'error', {'bad_edge', [vertex()]}}.

acyclic_add_edge(_E, V1, V2, _L, _G) when V1 =:= V2 ->
    {error, {bad_edge, [V1, V2]}};
acyclic_add_edge(E, V1, V2, Label, G) ->
    case get_path(G, V2, V1) of
	false -> do_insert_edge(E, V1, V2, Label, G);
	Path -> {error, {bad_edge, Path}}
    end.

%%
%% Delete all paths from vertex V1 to vertex V2
%%

-spec del_path(G, V1, V2) -> 'true' when
      G :: xl_digraph(),
      V1 :: vertex(),
      V2 :: vertex().

del_path(G, V1, V2) ->
    case get_path(G, V1, V2) of
	false -> true;
	Path ->
	    rm_edges(Path, G),
	    del_path(G, V1, V2)
    end.

%%
%% Find a cycle through V
%% return the cycle as list of vertices [V ... V]
%% if no cycle exists false is returned
%% if only a cycle of length one exists it will be
%% returned as [V] but only after longer cycles have
%% been searched.
%%

-spec get_cycle(G, V) -> Vertices | 'false' when
      G :: xl_digraph(),
      V :: vertex(),
      Vertices :: [vertex(),...].

get_cycle(G, V) ->
    case one_path(out_neighbours(G, V), V, [], [V], [V], 2, G, 1) of
	false ->
	    case lists:member(V, out_neighbours(G, V)) of
		true -> [V];
		false -> false
	    end;
	Vs -> Vs
    end.

%%
%% Find a path from V1 to V2
%% return the path as list of vertices [V1 ... V2]
%% if no path exists false is returned
%%

-spec get_path(G, V1, V2) -> Vertices | 'false' when
      G :: xl_digraph(),
      V1 :: vertex(),
      V2 :: vertex(),
      Vertices :: [vertex(),...].

get_path(G, V1, V2) ->
    one_path(out_neighbours(G, V1), V2, [], [V1], [V1], 1, G, 1).

%%
%% prune_short_path (evaluate conditions on path)
%% short : if path is too short
%% ok    : if path is ok
%%
prune_short_path(Counter, Min) when Counter < Min ->
    short;
prune_short_path(_Counter, _Min) ->
    ok.

one_path([W|Ws], W, Cont, Xs, Ps, Prune, G, Counter) ->
    case prune_short_path(Counter, Prune) of
	short -> one_path(Ws, W, Cont, Xs, Ps, Prune, G, Counter);
	ok -> lists:reverse([W|Ps])
    end;
one_path([V|Vs], W, Cont, Xs, Ps, Prune, G, Counter) ->
    case lists:member(V, Xs) of
	true ->  one_path(Vs, W, Cont, Xs, Ps, Prune, G, Counter);
	false -> one_path(out_neighbours(G, V), W, 
			  [{Vs,Ps} | Cont], [V|Xs], [V|Ps], 
			  Prune, G, Counter+1)
    end;
one_path([], W, [{Vs,Ps}|Cont], Xs, _, Prune, G, Counter) ->
    one_path(Vs, W, Cont, Xs, Ps, Prune, G, Counter-1);
one_path([], _, [], _, _, _, _, _Counter) -> false.

%%
%% Like get_cycle/2, but a cycle of length one is preferred.
%%

-spec get_short_cycle(G, V) -> Vertices | 'false' when
      G :: xl_digraph(),
      V :: vertex(),
      Vertices :: [vertex(),...].

get_short_cycle(G, V) ->
    get_short_path(G, V, V).

%%
%% Like get_path/3, but using a breadth-first search makes it possible
%% to find a short path.
%%

-spec get_short_path(G, V1, V2) -> Vertices | 'false' when
      G :: xl_digraph(),
      V1 :: vertex(),
      V2 :: vertex(),
      Vertices :: [vertex(),...].

get_short_path(G, V1, V2) ->
    T = new(),
    add_vertex(T, V1),
    Q = queue:new(),
    Q1 = queue_out_neighbours(V1, G, Q),
    L = spath(Q1, G, V2, T),
    delete(T),
    L.
    
spath(Q, G, Sink, T) ->
    case queue:out(Q) of
	{{value, E}, Q1} ->
	    {_E, V1, V2, _Label} = edge(G, E),
	    if 
		Sink =:= V2 ->
		    follow_path(V1, T, [V2]);
		true ->
		    case vertex(T, V2) of
			false ->
			    add_vertex(T, V2),
			    add_edge(T, V2, V1),
			    NQ = queue_out_neighbours(V2, G, Q1),
			    spath(NQ, G, Sink, T);
			_V ->
			    spath(Q1, G, Sink, T)
		    end
	    end;
	{empty, _Q1} ->
	    false
    end.

follow_path(V, T, P) ->
    P1 = [V | P],
    case out_neighbours(T, V) of
	[N] ->
	    follow_path(N, T, P1);
	[] ->
	    P1
    end.

queue_out_neighbours(V, G, Q0) ->
    lists:foldl(fun(E, Q) -> queue:in(E, Q) end, Q0, out_edges(G, V)).
