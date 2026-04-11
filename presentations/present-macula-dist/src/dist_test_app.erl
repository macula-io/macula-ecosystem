-module(dist_test_app).
-behaviour(application).
-export([start/2, stop/1]).

start(_Type, _Args) ->
    dist_test_sup:start_link().

stop(_State) ->
    ok.
