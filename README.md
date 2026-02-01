<h1 align="center">Welcome to Nexus Kairos</h1>

This is a realtime server that can listen to a postgres database in realtime and emit updates based on your inital query
A developer can also use this as a regular websocket server

So far only postgres is works natively but other database will be accepted. Suchas Mysql, Cassandra, SQLite, etc
There will be a feature that allows any database to be accepted, but you wont be able to listen to the database



## Quick Start

### Using the realtime server

`Npm i nexusrt/kairos`

You have two options to use kairos as a regular websocket server. Which means to follow a topic and subscribe to an event,
or to use it as a realtime query engine

#### Using it as a websocket server

Let's first start off by talking about using it as a regular websocket server.
This means two clients connect to the server by subscribing to the same topic.
And then listening to the same event.
```
nexus = await NexusRT.create('ws://<link_to_server>/realtime');
nexus2.current.connect();
await nexus2.current.useUserChannel("<topic_name>”);
nexus.on('<name_of_event', (msg) => {
  console.log('roast:',msg);
});
```


To send to the event you’re subscribed to or someone else is subscribed to you have two options. Either emit to the topic you already connected to and push to the event. Or pick the topic and event

Choose which event and topic:
`nexus.emitTo('<name_of_topic>', '<name_of_event>', {body:{<payload>}})`

Emit to the topic your nexus has subscribed to earlier:
`nexus.emit('<name_of_event>', {body:{<payload>}})`

Now both clients can talk to each other. This is perfect for real time chat apps that are public. if you want a private chatapp, make sure your users are subscribed to the correct topic
if your private messages are based on the url, use the url query parameter as the topic.

#### Using the realtime query engine

It’s almost the same as using it as a regular websocket server with a few changes 
```
nexus = await NexusRT.create('ws://<link_to_server>/realtime', {userid});
nexus.connect();
await nexus.current.useUserChannel("<name_of_topic", { userid });
const { result } = await nexus
  .select('*')
  .from('<name_of_table>')
  .where(`id=’2’`)
  .limit(1)
  .subscribeAndJoinRoutes({
	tableField: '<database_column_name>',
	fieldValue: `<value_of_the_column`,
	equality: '<comparison_operator>',
	event: '<event_name>', 
	table: '<name_of_table>',
	pk: '<name_of_primary_key>',
	alias: '<name_of_alias>',
});
```



# NexusRealtimeServer

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix


