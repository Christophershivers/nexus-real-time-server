import ws from "k6/ws";
import { check } from "k6";
import { Rate, Trend } from "k6/metrics";

const subOk = new Rate("subscribe_ok");
const subLatency = new Trend("subscribe_latency_ms");
const broadcastLatency = new Trend("broadcast_latency_ms");

export const options = {
  scenarios: Object.fromEntries(
    Array.from({ length: 5 }, (_, i) => [
      `batch${i + 1}`,
      {
        executor: "per-vu-iterations",
        vus: 250,
        iterations: 1,
        startTime: `${i * 3.75}s`,
        maxDuration: "2.5m",
        gracefulStop: "30s",
      },
    ])
  ),
};

/**
 * Phoenix V2 JSON Serializer Frame
 * format: [join_ref, ref, topic, event, payload]
 */
function phoenixFrame(joinRef, ref, topic, event, payload) {
  return JSON.stringify([
    joinRef ? String(joinRef) : null,
    String(ref),
    String(topic),
    String(event),
    payload || {},
  ]);
}

export default function () {
  const url = "ws://172.234.16.196:4000/realtime/websocket?vsn=2.0.0";

  // The Routing ID and Channel Topic are now identical
  const userid = String(100000 + __VU);
  const channelTopic =
    __ENV.ROUTE_TOPIC ||
    "rt:6446eee0f3058b1e579d16882291a586492ec2e6aa05bbb5713d3c0701b25e01:0";

  const params = {
    headers: { "Sec-WebSocket-Protocol": "phoenix" },
  };

  const res = ws.connect(url, params, (socket) => {
    let subSentAt = null;
    let hbTimer = null;

    socket.on("open", () => {
      // Step 1: Join using the exact userid as the channel topic
      socket.send(
        phoenixFrame("1", "1", channelTopic, "phx_join", { userid })
      );

      // Heartbeat to keep the connection alive
      hbTimer = socket.setInterval(() => {
        socket.send(
          phoenixFrame(null, "hb", "phoenix", "heartbeat", {})
        );
      }, 50000);
    });

    socket.on("message", (data) => {
      let msg;
      try {
        msg = JSON.parse(data);
      } catch {
        return;
      }

      const [joinRef, msgRef, topic, event, payload] = msg;

      // Step 2: On Join OK, send the Nexus Matcher Subscription
      if (event === "phx_reply" && msgRef === "1" && payload?.status === "ok") {
        console.log("ok");

        subSentAt = Date.now();

        socket.send(
          phoenixFrame("1", "2", channelTopic, "subscribe", {
            topic: "posts:userid", // Nexus matching topic
            userid: userid,        // Routing ID
            table_field: "userid",
            field_value: "57",
            equality: "eq",
            query:
              "select * from posts where (userid = 57) order by updated_at desc limit 5",
            event: "posts",        // Event to listen for
            pk: "id",
            alias: null,
          })
        );
      }

      // Step 3: Track Subscription confirmation
      if (event === "phx_reply" && msgRef === "2" && payload?.status === "ok") {
        subOk.add(1);
        if (subSentAt) {
          subLatency.add(Date.now() - subSentAt);
        }
      }

      // Step 4: BROADCAST LISTENER
      // All VUs idle here waiting for broadcasts from your external machine
      if (event === "posts") {
        const receivedAt = Date.now();
        const sentAt = payload?.sent_at;

        console.log("event received:");

        if (sentAt) {

          const latency = receivedAt - sentAt;
          broadcastLatency.add(latency);
        }
      }
    });

    // Hold connection open for 2.5 minutes
    socket.setTimeout(() => socket.close(), 150000);

    socket.on("close", () => {
      if (hbTimer) socket.clearInterval(hbTimer);
    });
  });

  check(res, {
    "status 101": (r) => r && r.status === 101,
  });
}
