(() => {
  const MAX_DURATION_SECONDS = 120;
  const AUDIO_BITS_PER_SECOND = 24_000;
  const SENDER_STORAGE_KEY = "walkie:sender-name";
  const MIME_CANDIDATES = ["audio/mp4", "audio/webm;codecs=opus", "audio/webm", "audio/ogg;codecs=opus"];

  const code = location.pathname.split("/").filter(Boolean)[1];

  const el = (id) => document.getElementById(id);
  const states = ["loading", "invalid", "ready", "uploading", "sent", "error"];
  function showState(name) {
    for (const s of states) el(`state-${s}`).hidden = s !== name;
  }

  const senderInput = el("sender-input");
  senderInput.value = localStorage.getItem(SENDER_STORAGE_KEY) ?? "";
  senderInput.addEventListener("change", () => {
    localStorage.setItem(SENDER_STORAGE_KEY, senderInput.value.trim());
  });

  const recordBtn = el("record-btn");
  const timerEl = el("timer");
  const preview = el("preview");
  const reviewActions = el("review-actions");
  const sendBtn = el("send-btn");
  const discardBtn = el("discard-btn");

  let mediaRecorder = null;
  let chunks = [];
  let recordedBlob = null;
  let startedAt = 0;
  let timerHandle = null;
  let autoStopHandle = null;

  function pickMimeType() {
    return MIME_CANDIDATES.find((type) => window.MediaRecorder?.isTypeSupported?.(type)) ?? "";
  }

  function formatTime(totalSeconds) {
    const m = Math.floor(totalSeconds / 60);
    const s = Math.floor(totalSeconds % 60)
      .toString()
      .padStart(2, "0");
    return `${m}:${s}`;
  }

  function updateTimer() {
    const elapsed = (Date.now() - startedAt) / 1000;
    timerEl.textContent = `${formatTime(elapsed)} / ${formatTime(MAX_DURATION_SECONDS)}`;
  }

  async function startRecording() {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    const mimeType = pickMimeType();
    mediaRecorder = new MediaRecorder(stream, mimeType ? { mimeType, audioBitsPerSecond: AUDIO_BITS_PER_SECOND } : {});
    chunks = [];

    mediaRecorder.ondataavailable = (e) => {
      if (e.data.size > 0) chunks.push(e.data);
    };
    mediaRecorder.onstop = () => {
      stream.getTracks().forEach((t) => t.stop());
      recordedBlob = new Blob(chunks, { type: mediaRecorder.mimeType || mimeType || "audio/webm" });
      preview.src = URL.createObjectURL(recordedBlob);
      preview.hidden = false;
      reviewActions.hidden = false;
      recordBtn.hidden = true;
    };

    mediaRecorder.start();
    startedAt = Date.now();
    timerEl.hidden = false;
    updateTimer();
    timerHandle = setInterval(updateTimer, 500);
    autoStopHandle = setTimeout(stopRecording, MAX_DURATION_SECONDS * 1000);

    recordBtn.textContent = "Arrêter";
  }

  function stopRecording() {
    clearInterval(timerHandle);
    clearTimeout(autoStopHandle);
    if (mediaRecorder && mediaRecorder.state !== "inactive") mediaRecorder.stop();
  }

  function resetRecorder() {
    recordedBlob = null;
    preview.hidden = true;
    preview.removeAttribute("src");
    reviewActions.hidden = true;
    recordBtn.hidden = false;
    timerEl.hidden = true;
    recordBtn.textContent = "Enregistrer";
  }

  recordBtn.addEventListener("click", async () => {
    if (!mediaRecorder || mediaRecorder.state === "inactive") {
      try {
        await startRecording();
      } catch (err) {
        el("error-message").textContent = "Impossible d'accéder au microphone.";
        showState("error");
      }
    } else {
      stopRecording();
    }
  });

  discardBtn.addEventListener("click", resetRecorder);

  async function uploadRecording() {
    showState("uploading");
    const form = new FormData();
    const ext = (recordedBlob.type.split("/")[1] || "webm").split(";")[0];
    form.append("audio", recordedBlob, `recording.${ext}`);
    form.append("sender", senderInput.value.trim());

    try {
      const res = await fetch(`/channels/${code}/messages`, { method: "POST", body: form });
      if (!res.ok) throw new Error(`upload_failed_${res.status}`);
      showState("sent");
    } catch (err) {
      el("error-message").textContent = "Échec de l'envoi. Vérifiez votre connexion et réessayez.";
      showState("error");
    }
  }

  sendBtn.addEventListener("click", uploadRecording);
  el("retry-btn").addEventListener("click", () => {
    if (recordedBlob) uploadRecording();
    else {
      showState("ready");
      resetRecorder();
    }
  });
  el("record-again-btn").addEventListener("click", () => {
    resetRecorder();
    showState("ready");
  });

  async function init() {
    if (!code) {
      showState("invalid");
      return;
    }
    try {
      const res = await fetch(`/channels/${code}`);
      showState(res.ok ? "ready" : "invalid");
    } catch (err) {
      showState("invalid");
    }
  }

  init();
})();
