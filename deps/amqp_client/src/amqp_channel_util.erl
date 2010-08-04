%%   The contents of this file are subject to the Mozilla Public License
%%   Version 1.1 (the "License"); you may not use this file except in
%%   compliance with the License. You may obtain a copy of the License at
%%   http://www.mozilla.org/MPL/
%%
%%   Software distributed under the License is distributed on an "AS IS"
%%   basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
%%   License for the specific language governing rights and limitations
%%   under the License.
%%
%%   The Original Code is the RabbitMQ Erlang Client.
%%
%%   The Initial Developers of the Original Code are LShift Ltd.,
%%   Cohesive Financial Technologies LLC., and Rabbit Technologies Ltd.
%%
%%   Portions created by LShift Ltd., Cohesive Financial
%%   Technologies LLC., and Rabbit Technologies Ltd. are Copyright (C)
%%   2007 LShift Ltd., Cohesive Financial Technologies LLC., and Rabbit
%%   Technologies Ltd.;
%%
%%   All Rights Reserved.
%%
%%   Contributor(s): Ben Hood <0x6e6562@gmail.com>.

%% @private
-module(amqp_channel_util).

-include("amqp_client.hrl").

-export([open_channel/5]).
-export([terminate_channel_infrastructure/2]).
-export([do/4]).

%%---------------------------------------------------------------------------
%% Starting and terminating channels
%%---------------------------------------------------------------------------

%% Spawns a new channel supervision tree linked under the given connection
%% supervisor, starts monitoring the channel and registers it with the channel
%% manager
open_channel(ChMgr, ChSupSup, ProposedNumber, Driver, InfraArgs) ->
    case amqp_channels_manager:new_number(ChMgr, ProposedNumber) of
        {ok, ChNumber} ->
            {ok, ChSup} = amqp_channel_sup_sup:start_channel_sup(
                                  ChSupSup, ChNumber, Driver, InfraArgs),
            [Ch] = supervisor2:find_child(ChSup, channel),
            Framing = case supervisor2:find_child(ChSup, framing) of
                          [F] -> F;
                          []  -> undefined
                      end,
            case amqp_channels_manager:register(ChMgr, ChNumber, Ch, Framing) of
                ok     -> #'channel.open_ok'{} =
                              amqp_channel:call(Ch, #'channel.open'{}),
                          {ok, Ch};
                noproc -> {error, channel_died}
            end;
        {error, _} = Error ->
            Error
    end.

terminate_channel_infrastructure(network, Sup) ->
    [Writer] = supervisor2:find_child(Sup, writer),
    rabbit_writer:flush(Writer),
    ok;
terminate_channel_infrastructure(direct, Sup) ->
    [RChannel] = supervisor2:find_child(Sup, rabbit_channel),
    rabbit_channel:shutdown(RChannel),
    ok.

%%---------------------------------------------------------------------------
%% Do
%%---------------------------------------------------------------------------

do(network, Writer, Method, Content) ->
    case Content of
        none -> rabbit_writer:send_command_and_signal_back(Writer, Method,
                                                           self());
        _    -> rabbit_writer:send_command_and_signal_back(Writer, Method,
                                                           Content, self())
    end,
    receive
        rabbit_writer_send_command_signal -> ok
    end;
do(direct, RabbitChannel, Method, Content) ->
    case Content of
        none -> rabbit_channel:do(RabbitChannel, Method);
        _    -> rabbit_channel:do(RabbitChannel, Method, Content)
    end.
