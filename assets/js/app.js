import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";

const Hooks = {
  AutoScroll: {
    mounted() {
      this.scrollToBottom();
    },
    updated() {
      const el = this.el;
      const isNearBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 120;
      if (isNearBottom) this.scrollToBottom();
    },
    scrollToBottom() {
      this.el.scrollTo({ top: this.el.scrollHeight, behavior: "smooth" });
    },
  },
};

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  ?.getAttribute("content");

const livePath = document
  .querySelector("meta[name='live-path']")
  ?.getAttribute("content") || "/live";

const liveTransport = document
  .querySelector("meta[name='live-transport']")
  ?.getAttribute("content") || "websocket";

const liveSocket = new LiveSocket(livePath, Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
});

liveSocket.connect();
window.liveSocket = liveSocket;
