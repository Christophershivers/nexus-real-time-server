import ws from "k6/ws";
import { check } from "k6";
import { Rate, Trend } from "k6/metrics";

const subOk = new Rate("subscribe_ok");
const subLatency = new Trend("subscribe_latency_ms");
const broadcastLatency = new Trend("broadcast_latency_ms");

export const options = {
  scenarios: Object.fromEntries(
    Array.from({ length: 20 }, (_, i) => [
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
  const url = "ws://<your_server_address>:4000/realtime/websocket?vsn=2.0.0";

  // Split VUs into 4 buckets (0..3):
  // 1->1, 2->2, 3->3, 4->0, 5->1 ...
  const fieldValueNum = __VU % 4;
  const field_value = String(fieldValueNum);

  // Unique routing id per VU (unchanged)
  const userid = String(100000 + __VU);

  // Use the bucket value in the route topic (instead of hardcoded :57)
  let channelTopic;
  //change these to the correct route topic
  if(fieldValueNum === 0){
    channelTopic = `rt:6446eee0f3058b1e579d16882291a586492ec2e6aa05bbb5713d3c0701b25e01:0`;
  }
  else if(fieldValueNum === 1){
    channelTopic = `rt:032d82aac02d5d559e305fbb29738cd11c64b2ec8ff9fa1e667498499c236c23:1`;
  }else if(fieldValueNum === 2){
    channelTopic = `rt:4b6219d424cb89f0aa2f369774ae3b20ddd311859ba29c1284a306b1d4e89ec6:2`;
  }else{
    channelTopic = `rt:cc1a664e725bf80475fd22f22253fe9f6b13a575a0f1b6b56ad3f99de1775a19:3`;
  }
    

  const params = {
    headers: { "Sec-WebSocket-Protocol": "phoenix" },
  };

  const res = ws.connect(url, params, (socket) => {
    let subSentAt = null;
    let hbTimer = null;

    socket.on("open", () => {
      socket.send(phoenixFrame("1", "1", channelTopic, "phx_join", { userid }));

      hbTimer = socket.setInterval(() => {
        socket.send(phoenixFrame(null, "hb", "phoenix", "heartbeat", {}));
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

      if (event === "phx_reply" && msgRef === "1" && payload?.status === "ok") {
        subSentAt = Date.now();

        socket.send(
          phoenixFrame("1", "2", channelTopic, "subscribe", {
            topic: "posts:userid",
            userid: userid,
            table_field: "userid",
            field_value: field_value,         // <-- bucket (0..3)
            equality: "eq",
            query: `select * from posts where (userid = ${field_value}) order by updated_at desc limit 5`,
            event: "posts",
            pk: "id",
            alias: null,
          })
        );
      }

      if (event === "phx_reply" && msgRef === "2" && payload?.status === "ok") {
        subOk.add(1);
        if (subSentAt) subLatency.add(Date.now() - subSentAt);
      }

      if (event === "posts") {
        const receivedAt = Date.now();
        const sentAt = payload?.sent_at;
        if (sentAt) broadcastLatency.add(receivedAt - sentAt);
      }
    });

    socket.setTimeout(() => socket.close(), 150000);

    socket.on("close", () => {
      if (hbTimer) socket.clearInterval(hbTimer);
    });
  });

  check(res, {
    "status 101": (r) => r && r.status === 101,
  });
}
