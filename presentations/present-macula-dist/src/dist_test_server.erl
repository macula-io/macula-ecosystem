%%%-------------------------------------------------------------------
%%% @doc Simple gen_server for cross-node call testing.
%%% Registered as dist_test_server on each node.
%%%-------------------------------------------------------------------
-module(dist_test_server).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    {ok, #{started => erlang:system_time(second)}}.

handle_call(ping, _From, State) ->
    {reply, {pong, node()}, State};
handle_call(get_state, _From, State) ->
    {reply, {ok, State#{node => node(), connected => nodes()}}, State};
handle_call(_Request, _From, State) ->
    {reply, {error, unknown}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Msg, State) ->
    {noreply, State}.
