import fs from "node:fs";
import ffmpeg from "fluent-ffmpeg";
import ffmpegPath from "ffmpeg-static";
import ffprobeStatic from "ffprobe-static";
import { config } from "../config";

ffmpeg.setFfmpegPath(ffmpegPath);
ffmpeg.setFfprobePath(ffprobeStatic.path);

export class TranscodeError extends Error {}
export class TranscoderBusyError extends Error {}

export interface TranscodeResult {
  durationSeconds: number | null;
}

// ffmpeg is the one expensive thing an anonymous sender can trigger: cap how many run
// at once, and refuse (503) rather than queue without bound when the box is saturated.
const MAX_CONCURRENT = 2;
const MAX_QUEUED = 10;
// Generous for a ≤2 min clip on a small box; anything slower is a hostile input.
const TIMEOUT_SECONDS = 60;

let running = 0;
const waiting: Array<() => void> = [];

async function withSlot<T>(fn: () => Promise<T>): Promise<T> {
  if (running >= MAX_CONCURRENT) {
    if (waiting.length >= MAX_QUEUED) throw new TranscoderBusyError("transcoder_busy");
    await new Promise<void>((resolve) => waiting.push(resolve));
  }
  running++;
  try {
    return await fn();
  } finally {
    running--;
    waiting.shift()?.();
  }
}

function probeDuration(filePath: string): Promise<number | null> {
  return new Promise((resolve) => {
    ffmpeg.ffprobe(filePath, (err, data) => {
      if (err) return resolve(null);
      resolve(data.format.duration ?? null);
    });
  });
}

/**
 * Normalizes any browser-recorded upload (webm/opus, mp4/aac, ogg/opus, ...) to a single
 * AAC/.m4a output. This is what lets the iOS app play every incoming message reliably —
 * AVAudioPlayer has no dependable webm/opus support, but every sender's browser format
 * converges here before it's ever stored or broadcast.
 *
 * The 2-minute limit is enforced by the web page, but anyone can POST directly — so the
 * output is also cut at `maxDurationSeconds` here (a low-bitrate file under the upload
 * size limit can hold far more audio than that, which the iOS app would then auto-play).
 */
export function transcodeToM4a(inputPath: string, outputPath: string): Promise<TranscodeResult> {
  return withSlot(
    () =>
      new Promise<TranscodeResult>((resolve, reject) => {
        ffmpeg(inputPath, { timeout: TIMEOUT_SECONDS })
          .noVideo()
          .audioCodec("aac")
          .audioBitrate("64k")
          .audioChannels(1)
          .duration(config.maxDurationSeconds)
          .outputOptions(["-movflags", "+faststart"])
          .format("mp4")
          .on("error", (err: Error) => {
            cleanup(outputPath);
            reject(new TranscodeError(err.message));
          })
          .on("end", async () => {
            const durationSeconds = await probeDuration(outputPath);
            resolve({ durationSeconds });
          })
          .save(outputPath);
      })
  );
}

function cleanup(filePath: string): void {
  fs.rm(filePath, { force: true }, () => {});
}
