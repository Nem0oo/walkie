import fs from "node:fs";
import ffmpeg from "fluent-ffmpeg";
import ffmpegPath from "ffmpeg-static";
import ffprobeStatic from "ffprobe-static";

ffmpeg.setFfmpegPath(ffmpegPath);
ffmpeg.setFfprobePath(ffprobeStatic.path);

export class TranscodeError extends Error {}

export interface TranscodeResult {
  durationSeconds: number | null;
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
 */
export function transcodeToM4a(inputPath: string, outputPath: string): Promise<TranscodeResult> {
  return new Promise((resolve, reject) => {
    ffmpeg(inputPath)
      .noVideo()
      .audioCodec("aac")
      .audioBitrate("64k")
      .audioChannels(1)
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
  });
}

function cleanup(filePath: string): void {
  fs.rm(filePath, { force: true }, () => {});
}
