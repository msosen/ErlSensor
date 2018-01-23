-module(event).
-export([start/2, start_link/2, cancel/1]).
-export([init/3, loop/1]).
-record(state, {server,
                name="",
                value
                }).

%%% Public interface
start(EventName, Value) ->
    spawn(?MODULE, init, [self(), EventName, Value]).

start_link(EventName, Value) ->
    spawn_link(?MODULE, init, [self(), EventName, Value]).

cancel(Pid) ->
    %% Monitor in case the process is already dead
    Ref = erlang:monitor(process, Pid),
    Pid ! {self(), Ref, cancel},
    receive
        {Ref, ok} ->
            erlang:demonitor(Ref, [flush]),
            ok;
        {'DOWN', Ref, process, Pid, _Reason} ->
            ok
    end.

%%% Event's innards
init(Server, EventName, Value) ->



    loop(#state{server=Server,
                name=EventName,
                value = Value
                }).

%% Loop uses a list for times in order to go around the ~49 days limit
%% on timeouts.
loop(S = #state{server=Server}) ->
    receive
      {Server, okVal} ->
        NewS = S#state{value = S#state.value+random()},
        Server ! {self(), S#state.name, S#state.value},
        loop(NewS);
      {Server, down} ->
        NewS = S#state{value = S#state.value-0.3},
        Server ! {self(), S#state.name, S#state.value},
        loop(NewS);
      {Server, up} ->
        NewS = S#state{value = S#state.value+0.3},
        Server ! {self(), S#state.name, S#state.value},
        loop(NewS);
      {Server, go} ->
        NewS = S#state{value = S#state.value+random()},
        Server ! {self(), S#state.name, S#state.value},
        loop(NewS)
      after 10000 ->
          ok
      end.

random() -> (rand:uniform()*2)-1.




%%%%% private functions
%%time_to_go(TimeOut={{_,_,_}, {_,_,_}}) ->
%%    Now = calendar:local_time(),
%%    ToGo = calendar:datetime_to_gregorian_seconds(TimeOut) -
%%           calendar:datetime_to_gregorian_seconds(Now),
%%    Secs = if ToGo > 0  -> ToGo;
%%              ToGo =< 0 -> 0
%%           end,
%%    normalize(Secs).
%%
%%%% Because Erlang is limited to about 49 days (49*24*60*60*1000) in
%%%% milliseconds, the following function is used
%%normalize(N) ->
%%    Limit = 49*24*60*60,
%%    [N rem Limit | lists:duplicate(N div Limit, Limit)].
