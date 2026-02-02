<h1 align="center">Welcome to Nexus Kairos</h1>

This is a realtime server that can listen to a postgres database in realtime and emit updates based on your inital query
A developer can also use this as a regular websocket server

So far only postgres is works natively but other database will be accepted. Suchas Mysql, Cassandra, SQLite, etc
There will be a feature that allows any database to be accepted, but you wont be able to listen to the database



# Quick Start

### Using the realtime server SDK

`npm i @nexusrt/kairos`

then import it using 
`import { NexusRT } from '@nexusrt/kairos';`

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
nexus = await NexusRT.create('ws://<link_to_server>/realtime', jwt, {userid});
nexus.connect();
await nexus.useUserChannel("<name_of_topic", { userid });
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
Then listen to the incoming inserts, updates, or deletes coming from the database
'''
nexus.on('<name_of_event>', (msg) => {
  console.log('roast:',msg);
});
'''
The event name is the same event you put in the subscribeAndJoinRoutes.


## Setting Up Postgres

Before you use this on postgres there are a couple of things you need to do first. 
First thing is make sure you have Wal2Json installed in Postgres. 
if you dont know how to do that then I have created a postgres docker image with it installed.

`docker pull nexusrt/postgres-wal2json:latest`

There's a dockerfile and docker compose file under the docker folder. That's where i setup postgres.
You can take that file and run it. Or look at how i set it up and copy the environment variables

these env var are the most important. Make sure these are enabled
```
-c wal_level=logical
-c max_wal_senders=10
-c max_replication_slots=10
```
go inside the postgres image and make sure you have wallevel set to logcical 

`ALTER SYSTEM SET wal_level = 'logical';`
 after that restart postgres.

 Then create a replication slot for Wal2Json

 `SELECT pg_create_logical_replication_slot('wal2json_slot', 'wal2json');`

 After that you have one more thing. By default Wal2Json does not give you all the data from a delete
 in order for nexus kairos to work correctly with deletes you need to do this last step.

 Create all the tables you want to create then after you did that use this query so Wal2Json can get all data from deletes

 `ALTER TABLE <table_name> REPLICA IDENTITY FULL;`

 Now inserts, updates, and deletes should give you everything you need
 Also caveats for deletes. Deletes only send the id of the insert and the database operation.
 Use that to find whatever record was deleted and delete it from memory.


 ## Setting Up Kairos Server

 Setting up the Kairos server is really simple. This server can be used as a regular WebSocket server and or a real-time query engine. I have a Docker image for it
 `docker pull nexusrt/nexusrt:latest`

You can build this yourself when you clone the repository. but the fastest way is to use the Docker image. If you made changes to the repository locally, you can build it
`docker build -t <name_of_docker_image> .`

You can use Kairos with portainer, coolify, etc or you can run it from Docker itself from a linux server. Which ever you are comfortable with.
When using Kairos there are some env var you need to know about.

```
HOSTNAME: string
DBUSERNAME: string
PASSWORD: string
DATABASE: string
DBPORT: string
SLOT: string
POOL_SIZE: integer
MAX_CONCURRENCY: integer
BATCH_SIZE: integer
CHUNK_SIZE: integer
AUTH_SECRET: string
AUTH_ENABLED: boolean
CORS_ORIGINS: string with commas
WEBSOCKET_ORIGINS: string
DATABASE_URL: string
ENABLE_POSTGRES: boolean
```
|Name|Description|Example
|-|-|-|
|HOSTNAME|Database host|localhost/219.42.23.176/<domain_name>.com
|DBUSERNAME|Database user| username123
|PASSWORD|Database password|password123
|DATABASE|Database name|postgres
|DBPORT|Database port|5432
|SLOT|Wal2Json Replication slot namet| wal2json_slot
|POOL_SIZE|DB pool size|40
|MAX_CONCURRENCY|Worker concurrency|40
|AUTH_SECRET|JWT signing secret| op1VZ8yly2HBAGds9Squaet2TyMsoWJ1LrkAnH3kM7p
|AUTH_ENABLED|Enable JWT authentication (false by default)|true/false
|CORS_ORIGINS|Allowed CORS origins|http://localhost:3000,https://<domain_name>.com
|WEBSOCKET_ORIGINS|Allowed WS origins|http://localhost:3000,https://<domain_name>.com
|DATABASE_URL|Full DB connection string|postgres://<your_username>:<your_password>@<server_address>:<database_port>/<database_name>
|ENABLE_POSTGRES|enables postgres functionality(false by default)|true/false

# Security 

Nexus Kairos does have security built in; in later version this will get reworked so users won't have to put the address to the websocket server itself. For now, the way security works is optional. In the Kairos server, you would set `AUTH_ENABLED` env var to true and have a JWT secret set in the env var `AUTH_SECRET`. Then in the SDK you would have the jwt set with the jwt token`nexus = await NexusRT.create('ws://<link_to_server>/realtime', jwt, {userid});`. In the future, you will be able to use HTTP-only tokens, so it won't be exposed. There are also checks on the server side for anything other than select statements for the query. Anything that has delete, update, or insert won't be accepted.

# Benchmarks
I have done a couple of benchmarks. In the K6 folder, you'll find what I did. This is my first time benchmarking, so I could have done it wrong. If you see anything that's wrong or abnormal, let me know.

## Current Users(idle)
|CPU|RAM|Concurrent Users|Passed|
|-|-|-|-|
|1GB|1|10,000|✅|
|4gb|2|10,000|✅|
|8gb|4|10,000|✅|

Based on this benchmark, I have found that a 1gb 1 cpu server from Linode can hold 10K concurrent users, but they are idled. Which means all they did was register in the Mnesia in-memory database, and received a broadcast of their query and sat there not doing anything

## Concurrent Users(receving messages)
|CPU|RAM|Concurrent Users|Time to complete|latency for one message|Records/s|Broadcast/s|
|-|-|-|-|-|-|-|
|1GB|1|5,000|20s|333ms|3|15K
|4gb|2|5,000|12s|200ms|5|25k
|8gb|4|5,000|7s|117ms|8.5|42.8K

This test had 5000 concurrent users all receiving the same message; in other words, every user in the Mnesia database received a broadcast. For the 1gb 1 cpu server, it took 20 seconds to receive all 60 messages, which means each user had 3 messages persecond. With the websocket server broadcasting 15K messages persecond. For the 4gb 2 cpu server, it completed 60 messages in 12 seconds, which resulted in 5 records per second per connected user, and a broadcast of 25K/s. Finally, the 8GB 4 cpu server completed it in 7 seconds. with 8.5 records per user, and 42.8K broadcast/s.

## Concurrent Users(receiving split messages)

The final benchmark I did was to see how well the server would do if everyone weren't listening to the same record. So I split it by using a modulus. I split 5000 into 4. So there will be 1250 users listening to a record instead of the entire 5000. With the VU number, I used the modulus operator by 4, so a __VU id of 1 would be 1%4. __VU id of 2 would be 2%4. This would give me a userid of 1 and 2, respectively. The id ranged from 0 to 3, so I personally listened to user 0. In total userid from 0-3 had 1250 concurrent users listening to it each, with a total of 5000 concurrent users overall. 

To put this into perspective, if a server has 1250 concurrent users and they were all listening to the same record, then for 60 messages, it would be completed in 3 seconds, giving you 20 messages/sec with a 100k broadcast messages/sec

|CPU|RAM|Concurrent Users|per record|Time to complete|latency for one message|Records/s|Broadcast/s|
|-|-|-|-|-|-|-|-|
|4gb|2|5,000|1,250|117ms|7s|8.5|42.8k

All of these benchmarks are under the k6 folder.

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


