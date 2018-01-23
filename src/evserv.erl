%% Event server
-module(evserv).
-compile(export_all).

-record(state, {events,    %% list of #event{} records
                clients}). %% list of Pids

-record(event, {name="",
                pid,
                value}
                ).

%%% User Interface

start() ->
    register(?MODULE, Pid=spawn(?MODULE, init, [])),
    Pid.

start_link() ->
    register(?MODULE, Pid=spawn_link(?MODULE, init, [])),
    Pid.

terminate() ->
    ?MODULE ! shutdown.

init() ->
    %% Loading events from a static file could be done here.
    %% You would need to pass an argument to init (maybe change the functions
    %% start/0 and start_link/0 to start/1 and start_link/1) telling where the
    %% resource to find the events is. Then load it from here.
    %% Another option is to just pass the event straight to the server
    %% through this function.
    EventPid = event:start_link(tlen, 26),
    EventPid2 = event:start_link(temp, 20),
    List = [{tlen, #event{name=tlen, pid=EventPid, value=26}}, {temp, #event{name=temp, pid=EventPid2, value=20}}],
    Events = array:from_list(List),

    loop(#state{events=Events,
                clients=orddict:new()}).

subscribe(Pid) ->
    Ref = erlang:monitor(process, whereis(?MODULE)),
    ?MODULE ! {self(), Ref, {subscribe, Pid}},
    receive
        {Ref, ok} ->
            {ok, Ref};
        {'DOWN', Ref, process, _Pid, Reason} ->
            {error, Reason}
    after 5000 ->
        {error, timeout}
    end.


add_event(Name, Description, TimeOut) ->
    Ref = make_ref(),
    ?MODULE ! {self(), Ref, {add, Name, Description, TimeOut}},
    receive
        {Ref, Msg} -> Msg
    after 5000 ->
        {error, timeout}
    end.

add_event2(Name, Description, TimeOut) ->
    Ref = make_ref(),
    ?MODULE ! {self(), Ref, {add, Name, Description, TimeOut}},
    receive
        {Ref, {error, Reason}} -> erlang:error(Reason);
        {Ref, Msg} -> Msg
    after 5000 ->
        {error, timeout}
    end.

cancel(Name) ->
    Ref = make_ref(),
    ?MODULE ! {self(), Ref, {cancel, Name}},
    receive
        {Ref, ok} -> ok
    after 5000 ->
        {error, timeout}
    end.

listen(Delay) ->
    receive
        M = {done, _Name, _Description} ->
            [M | listen(0)]
    after Delay*1000 ->
        []
    end.

%%% The Server itself

loop(S=#state{}) ->
    receive
        {startWork} -> send_to_events(go, S#state.events);

        {Pid, Name, Val} ->
            Action = handleSensor(S, Pid, Name, Val),
            case Action of
                error -> loop(S);
                _ -> timer:sleep(300), Pid ! {self(), Action}, loop(S)
            end;

        {Pid, MsgRef, {subscribe, Client}} ->
            Ref = erlang:monitor(process, Client),
            NewClients = orddict:store(Ref, Client, S#state.clients),
            Pid ! {MsgRef, ok},
            loop(S#state{clients=NewClients});

        {Pid, MsgRef, {cancel, Name}} ->
            Events = case orddict:find(Name, S#state.events) of
                         {ok, E} ->
                             event:cancel(E#event.pid),
                             orddict:erase(Name, S#state.events);
                         error ->
                             S#state.events
                     end,
            Pid ! {MsgRef, ok},
            loop(S#state{events=Events});
        {done, Name} ->
            case orddict:find(Name, S#state.events) of
                {ok, E} ->
                    send_to_clients({done, E#event.name},
                                    S#state.clients),
                    NewEvents = orddict:erase(Name, S#state.events),
                    loop(S#state{events=NewEvents});
                error ->
                    %% This may happen if we cancel an event and
                    %% it fires at the same time
                    loop(S)
            end;
        shutdown ->
            exit(shutdown);
        {'DOWN', Ref, process, _Pid, _Reason} ->
            loop(S#state{clients=orddict:erase(Ref, S#state.clients)});
        code_change ->
            ?MODULE:loop(S);
        {Pid, debug} -> %% used as a hack to let me do some unit testing
            Pid ! S,
            loop(S);
        Unknown ->
            io:format("Unknown message: ~p~n",[Unknown]),
            loop(S)
    end.


handleSensor(S, Pid, Name, Value) ->
    case orrdict:find(Name, S#state.events) of
        {ok, tlen} when Value > 28 ->
              down;
        {ok, tlen} when Value < 25 ->
            up;
        {ok, tlen} ->
            okVal;
        {ok, temp} when Value > 22 ->
            down;
        {ok, temp} when Value < 17 ->
            up;
        {ok, temp} ->
            okVal;
        error ->
            error
    end.


%updateSensor(min, max, default)


%%% Internal Functions
send_to_clients(Msg, ClientDict) ->
    orddict:map(fun(_Ref, Pid) -> Pid ! Msg end, ClientDict).

send_to_events(Msg, EventDict) ->
    orddict:map(fun(_Ref, Pid) -> Pid ! {self(), Msg} end, EventDict).


%%print({gotoxy,X,Y}) ->
%%    io:format("\e[~p;~pH",[Y,X]);
%%print({printxy,X,Y,Msg}) ->
%%    io:format("\e[~p;~pH~p",[Y,X,Msg]);
%%print({clear}) ->
%%    io:format("\e[2J",[]);
%%print({tlo}) ->
%%    print({printxy,2,4,1.2343}),
%%    io:format("",[])  .
%%
%%printxy({X,Y,Msg}) ->
%%    io:format("\e[~p;~pH~p~n",[Y,X,Msg]).
%%main()->
%%    print({clear}),
%%    print({printxy,1,20, "Ada"}),
%%    print({printxy,10,20, 2012}),
%%
%%    print({tlo}),
%%    print({gotoxy,1,25}).