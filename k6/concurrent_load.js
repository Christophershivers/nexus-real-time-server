import ws from "k6/ws";
import { check, sleep } from "k6";
import { Rate, Trend } from "k6/metrics";

const subOk = new Rate("subscribe_ok");
const subFail = new Rate("subscribe_fail");
const subLatency = new Trend("subscribe_latency_ms");
const subTimeout = new Rate("subscribe_timeout");

const HOLD_MS = 15 * 60 * 1000;      // keep socket open
const SUB_TIMEOUT_MS = 15000;       // how long we wait for subscribe reply
const BATCH_SIZE = 250;
const NUM_BATCHES = 40;
const BATCH_EVERY_SEC = 15;

export const options = {
  scenarios: Object.fromEntries(
    Array.from({ length: NUM_BATCHES }, (_, i) => {
      const name = `batch${i + 1}`;
      return [
        name,
        {
          executor: "per-vu-iterations",
          vus: BATCH_SIZE,
          iterations: 1,
          startTime: `${i * BATCH_EVERY_SEC}s`,
          maxDuration: "15m",
          gracefulStop: "30s",
        },
      ];
    })
  ),
  thresholds: {
    subscribe_ok: ["rate>0.95"],
    subscribe_latency_ms: ["p(95)<2000"],
  },
};

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
  const userid = String(100000 + __VU);
  const channelTopic = `user:${userid}`;
  const params = { headers: { "Sec-WebSocket-Protocol": "phoenix" } };

  const startedAt = Date.now();

  const res = ws.connect(url, params, (socket) => {
    let subscribeSentAt = null;
    let gotSubscribeReply = false;
    let hbTimer = null;

    socket.on("open", () => {
      // Join
      socket.send(phoenixFrame("1", "1", channelTopic, "phx_join", { userid }));

      // Heartbeat every 50–55s with jitter (reduces timer pressure at 5k)
      const hbMs = 50000 + Math.floor(Math.random() * 5000);
      hbTimer = socket.setInterval(() => {
        socket.send(phoenixFrame(null, "hb", "phoenix", "heartbeat", {}));
      }, hbMs);
    });

    socket.on("message", (data) => {
      let msg;
      try {
        msg = JSON.parse(data);
      } catch {
        return;
      }

      const [join_ref, msgRef, topic, event, payload] = Array.isArray(msg)
        ? msg
        : [null, null, null, null, msg];

      // Join OK -> send subscribe (small jitter so 250 sockets don't stampede at once)
      if (event === "phx_reply" && msgRef === "1" && payload?.status === "ok") {
        const jitterMs = 1 + Math.floor(Math.random() * 500); // 1–500ms
        socket.setTimeout(() => {
          subscribeSentAt = Date.now();
          socket.send(
            phoenixFrame("1", "2", channelTopic, "subscribe", {
              userid,
              table_field: "userid",
              field_value: "57",
              equality: "eq",
              query:
                "select * from posts where (userid = 57) order by updated_at desc limit 5",
              event: "posts",
              pk: "id",
            })
          );
        }, jitterMs);
      }

      // Subscribe reply
      if (event === "phx_reply" && msgRef === "2") {
        gotSubscribeReply = true;
        if (payload?.status === "ok") {
          subOk.add(1);
          if (subscribeSentAt) subLatency.add(Date.now() - subscribeSentAt);
        } else {
          subFail.add(1);
        }
      }
    });

    // If subscribe never replies, mark timeout (so you can see it clearly)
    socket.setTimeout(() => {
      if (!gotSubscribeReply) subTimeout.add(1);
    }, SUB_TIMEOUT_MS);

    // Hold socket open
    socket.setTimeout(() => socket.close(), HOLD_MS);

    socket.on("close", () => {
      if (hbTimer) socket.clearInterval(hbTimer);
    });

    socket.on("error", () => {
      subFail.add(1);
    });
  });

  check(res, { "status is 101": (r) => r && r.status === 101 });

  // Prevent tight-loop CPU if connect returns immediately
  sleep(1);
}
